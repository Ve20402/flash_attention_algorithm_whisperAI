#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "fa_axis.h"

static long ms_since(const struct timespec *a, const struct timespec *b)
{
	return (b->tv_sec - a->tv_sec) * 1000L +
	       (b->tv_nsec - a->tv_nsec) / 1000000L;
}

static void *load_file(const char *path, size_t expect)
{
	struct stat st;
	FILE *f;
	void *buf;

	f = fopen(path, "rb");
	if (!f) {
		fprintf(stderr, "open %s: %s\n", path, strerror(errno));
		return NULL;
	}
	if (fstat(fileno(f), &st) != 0) {
		fprintf(stderr, "stat %s: %s\n", path, strerror(errno));
		fclose(f);
		return NULL;
	}
	if ((size_t)st.st_size != expect) {
		fprintf(stderr, "%s: size %zu, expected %zu\n", path,
			(size_t)st.st_size, expect);
		fclose(f);
		return NULL;
	}
	buf = malloc(expect);
	if (!buf) {
		fprintf(stderr, "malloc %zu failed\n", expect);
		fclose(f);
		return NULL;
	}
	if (fread(buf, 1, expect, f) != expect) {
		fprintf(stderr, "short read from %s\n", path);
		free(buf);
		fclose(f);
		return NULL;
	}
	fclose(f);
	return buf;
}

static int build_stream(uint32_t *dst, const uint32_t *qkv)
{
	const uint32_t *q = qkv;
	const uint32_t *k = q + FA_MATRIX_WORDS;
	const uint32_t *v = k + FA_MATRIX_WORDS;
	uint32_t *out = dst;
	const size_t bytes = FA_HEAD_DIM * sizeof(uint32_t);

	for (uint32_t qi = 0; qi < FA_ROWS; qi += FA_B) {
		uint32_t br = (FA_ROWS - qi) < FA_B ? (FA_ROWS - qi) : FA_B;

		for (uint32_t head = 0; head < FA_HEADS; ++head) {
			uint32_t col = head * FA_HEAD_DIM;

			for (uint32_t row = 0; row < br; ++row) {
				memcpy(out, &q[(qi + row) * FA_COLS + col], bytes);
				out += FA_HEAD_DIM;
			}

			for (uint32_t j = 0; j < FA_ROWS; j += FA_BC) {
				uint32_t bc = (FA_ROWS - j) < FA_BC ?
					      (FA_ROWS - j) : FA_BC;

				for (uint32_t row = 0; row < bc; ++row) {
					memcpy(out, &k[(j + row) * FA_COLS + col], bytes);
					out += FA_HEAD_DIM;
				}
				for (uint32_t row = 0; row < bc; ++row) {
					memcpy(out, &v[(j + row) * FA_COLS + col], bytes);
					out += FA_HEAD_DIM;
				}
			}
		}
	}

	return (size_t)(out - dst) == FA_INPUT_WORDS ? 0 : -1;
}

int main(int argc, char **argv)
{
	const char *qkv_path = argc > 1 ? argv[1] : "fa_real_qkv.bin";
	const char *golden_path = argc > 2 ? argv[2] : "fa_real_golden.bin";
	const size_t qkv_bytes = 3UL * FA_MATRIX_WORDS * sizeof(uint32_t);
	struct fa_info info;
	struct timespec t0, t1;
	const int64_t *golden;
	int64_t *got;
	uint32_t *qkv;
	void *tx, *rx;
	long page;
	int fd, i, errors = 0;

	fd = open("/dev/fa_axis", O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "open /dev/fa_axis: %s\n", strerror(errno));
		return 1;
	}
	if (ioctl(fd, FA_IOC_GET_INFO, &info) != 0) {
		fprintf(stderr, "FA_IOC_GET_INFO: %s\n", strerror(errno));
		return 1;
	}
	printf("fa_axis: tx=%u rx=%u in_words=%u out_words=%u\n",
	       info.tx_size, info.rx_size, info.input_words, info.output_words);

	page = sysconf(_SC_PAGESIZE);
	tx = mmap(NULL, info.tx_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
		  FA_MMAP_TX * page);
	if (tx == MAP_FAILED) {
		fprintf(stderr, "mmap TX: %s\n", strerror(errno));
		return 1;
	}
	rx = mmap(NULL, info.rx_size, PROT_READ, MAP_SHARED, fd,
		  FA_MMAP_RX * page);
	if (rx == MAP_FAILED) {
		fprintf(stderr, "mmap RX: %s\n", strerror(errno));
		return 1;
	}

	qkv = load_file(qkv_path, qkv_bytes);
	got = load_file(golden_path, FA_RX_SIZE);
	if (!qkv || !got)
		return 1;
	golden = got;

	printf("building stream...\n");
	if (build_stream(tx, qkv) != 0) {
		fprintf(stderr, "stream size mismatch\n");
		return 1;
	}
	free(qkv);

	clock_gettime(CLOCK_MONOTONIC, &t0);
	if (ioctl(fd, FA_IOC_RUN) != 0) {
		fprintf(stderr, "FA_IOC_RUN: %s\n", strerror(errno));
		return 1;
	}
	clock_gettime(CLOCK_MONOTONIC, &t1);
	printf("run completed in %ld ms\n", ms_since(&t0, &t1));

	got = rx;
	for (i = 0; i < (int)FA_OUTPUT_WORDS; ++i) {
		if (got[i] != golden[i]) {
			if (errors < 8)
				printf("mismatch[%d] got=%016llx expected=%016llx\n",
				       i, (unsigned long long)got[i],
				       (unsigned long long)golden[i]);
			++errors;
		}
	}

	if (errors) {
		printf("FAILED: %d / %u mismatches\n", errors, FA_OUTPUT_WORDS);
		return 1;
	}
	printf("PASSED: %u / %u exact Q14.34 matches\n",
	       FA_OUTPUT_WORDS, FA_OUTPUT_WORDS);
	return 0;
}
