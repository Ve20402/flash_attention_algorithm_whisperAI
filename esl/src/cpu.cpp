#include "header/cpu.h"
#include "header/datatypes.h"
#include "header/dma.h"
#include "header/interconnect.h"
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <vector>

using namespace sc_core;
using namespace tlm;
using namespace tlm_utils;
using namespace std;

static const uint64_t ADDR_INPUT = 0ULL;
static const size_t DMA_BUFFER_WORDS = 1024 * 1024 / sizeof(uint32_t);

static void mmio_w1(simple_initiator_socket<Cpu> &sock, uint64_t addr,
                    unsigned char val, sc_time &loct) {
	tlm_generic_payload pl;
	pl.set_command(TLM_WRITE_COMMAND);
	pl.set_address(addr);
	pl.set_data_ptr(&val);
	pl.set_data_length(1);
	pl.set_streaming_width(1);
	pl.set_byte_enable_ptr(0);
	pl.set_response_status(TLM_INCOMPLETE_RESPONSE);
	sock->b_transport(pl, loct);
}

static void mmio_w8(simple_initiator_socket<Cpu> &sock, uint64_t addr,
                    uint64_t value, sc_time &loct) {
	tlm_generic_payload pl;
	pl.set_command(TLM_WRITE_COMMAND);
	pl.set_address(addr);
	pl.set_data_ptr(reinterpret_cast<unsigned char *>(&value));
	pl.set_data_length(8);
	pl.set_streaming_width(8);
	pl.set_byte_enable_ptr(0);
	pl.set_response_status(TLM_INCOMPLETE_RESPONSE);
	sock->b_transport(pl, loct);
}

static unsigned char mmio_r1(simple_initiator_socket<Cpu> &sock, uint64_t addr,
                             sc_time &loct) {
	tlm_generic_payload pl;
	unsigned char val = 0;
	pl.set_command(TLM_READ_COMMAND);
	pl.set_address(addr);
	pl.set_data_ptr(&val);
	pl.set_data_length(1);
	pl.set_streaming_width(1);
	pl.set_byte_enable_ptr(0);
	pl.set_response_status(TLM_INCOMPLETE_RESPONSE);
	sock->b_transport(pl, loct);
	return val;
}

static size_t compact_input_word_count(const attn::AttentionConfig &config) {
	const size_t columns = config.heads * config.head_dim;
	return static_cast<size_t>(config.query_rows) * columns +
	       2ULL * config.kv_rows * columns;
}

static void load_fixed_input(const string &filename, HostMemory *host_ram,
                             uint64_t address, size_t expected_words) {
	ifstream file(filename, ios::binary);
	if (!file.is_open())
		SC_REPORT_FATAL("CPU", "cannot open fixed point input file");

	file.seekg(0, ios::end);
	const auto byte_count = file.tellg();
	file.seekg(0, ios::beg);
	const uint64_t expected_bytes = expected_words * sizeof(uint32_t);
	if (byte_count < 0 || static_cast<uint64_t>(byte_count) != expected_bytes) {
		ostringstream message;
		message << "fixed input: expected " << expected_bytes
		        << " bytes, loaded " << byte_count;
		SC_REPORT_FATAL("CPU", message.str().c_str());
	}

	vector<unsigned char> chunk(4 * 1024 * 1024);
	uint64_t offset = 0;
	while (offset < expected_bytes) {
		const size_t current = static_cast<size_t>(
		    min<uint64_t>(chunk.size(), expected_bytes - offset));
		file.read(reinterpret_cast<char *>(chunk.data()), current);
		if (static_cast<size_t>(file.gcount()) != current)
			SC_REPORT_FATAL("CPU", "Kratak fixed-point ulaz");
		host_ram->write(address + offset, chunk.data(), current);
		offset += current;
	}
}

void Cpu::run() {
	sc_time loct = SC_ZERO_TIME;

	cout << "\nCPU : Loading compact Q6.18 Q/K/V matrices..." << endl;
	const uint64_t columns = config.heads * config.head_dim;
	const uint64_t q_words = static_cast<uint64_t>(config.query_rows) * columns;
	const uint64_t kv_words = static_cast<uint64_t>(config.kv_rows) * columns;
	const uint64_t input_words = compact_input_word_count(config);
	const uint64_t input_bytes = input_words * sizeof(uint32_t);
	const uint64_t addr_q = ADDR_INPUT;
	const uint64_t addr_k = addr_q + q_words * sizeof(uint32_t);
	const uint64_t addr_v = addr_k + kv_words * sizeof(uint32_t);
	const uint64_t addr_tx = (ADDR_INPUT + input_bytes + 7) & ~uint64_t{7};
	const uint64_t addr_y = addr_tx + DMA_BUFFER_WORDS * sizeof(uint32_t);
	const uint64_t output_words = static_cast<uint64_t>(config.query_rows) * columns;
	const uint64_t required_memory = addr_y + output_words * sizeof(fixed_word_t);
	if (required_memory > host_ram->size)
		SC_REPORT_FATAL("CPU", "low host memory");
	load_fixed_input(input_path, host_ram, ADDR_INPUT, input_words);

	cout << "CPU : Starting output DMA and IP..." << endl;
	mmio_w8(socket, ADDR_DMA_DST_ADDR, addr_y, loct);
	mmio_w8(socket, ADDR_DMA_DST_LEN, output_words, loct);
	mmio_w1(socket, ADDR_DMA_START, 0x02, loct);
	mmio_w1(socket, ADDR_CTRL, 0x01, loct);

	vector<uint32_t> tx(DMA_BUFFER_WORDS);
	size_t used = 0;
	uint64_t sent = 0;
	uint64_t transfers = 0;

	auto flush = [&] {
		if (used == 0)
			return;
		host_ram->write(addr_tx, reinterpret_cast<unsigned char *>(tx.data()), used * sizeof(uint32_t));
		mmio_w8(socket, ADDR_DMA_SRC_ADDR, addr_tx, loct);
		mmio_w8(socket, ADDR_DMA_SRC_LEN, used, loct);
		mmio_w1(socket, ADDR_DMA_START, 0x01, loct);
		while ((mmio_r1(socket, ADDR_DMA_STATUS, loct) & 0x01) == 0)
			wait(sc_time(100, SC_NS));
		sent += used;
		++transfers;
		used = 0;
	};

	auto emit_rows = [&](uint64_t matrix, int row_start, int row_count, int column) {
		for (int row = 0; row < row_count; ++row) {
			if (used + config.head_dim > tx.size())
				flush();
			const uint64_t word =
			    static_cast<uint64_t>(row_start + row) * columns + column;
			host_ram->read(matrix + word * sizeof(uint32_t), reinterpret_cast<unsigned char *>(tx.data() + used), config.head_dim * sizeof(uint32_t));
			used += config.head_dim;
		}
	};

	cout << "CPU : Streaming Q/K/V tiles through DMA..." << endl;
	for (int query_start = 0; query_start < config.query_rows;
	     query_start += attn::B) {
		const int query_rows = min(attn::B, config.query_rows - query_start);
		for (int head = 0; head < config.heads; ++head) {
			const int column = head * config.head_dim;
			emit_rows(addr_q, query_start, query_rows, column);
			for (int kv_start = 0; kv_start < config.kv_rows;
			     kv_start += attn::BC) {
				const int kv_rows = min(attn::BC, config.kv_rows - kv_start);
				emit_rows(addr_k, kv_start, kv_rows, column);
				emit_rows(addr_v, kv_start, kv_rows, column);
			}
		}
	}
	flush();
	cout << "CPU : Sent " << sent << " words in " << transfers
	     << " DMA transfers" << endl;

	cout << "CPU : Polling IP status..." << endl;
	while (true) {
		if (mmio_r1(socket, ADDR_STATUS, loct) == 1)
			break;
		wait(sc_time(100, SC_NS));
	}

	cout << "CPU : Polling DMA D2H status..." << endl;
	while (true) {
		if (mmio_r1(socket, ADDR_DMA_STATUS, loct) & 0x02)
			break;
		wait(sc_time(100, SC_NS));
	}

	cout << "CPU : Saving raw Q14.34 output..." << endl;
	save_matrix(output_path, addr_y, config.query_rows,
	            config.heads * config.head_dim);

	cout << "CPU : Complete @ " << sc_time_stamp() << endl;
	sc_stop();
}

void Cpu::save_matrix(const string &filename, uint64_t addr, int rows, int cols) {
	vector<fixed_word_t> buf(rows * cols);
	host_ram->read(addr, reinterpret_cast<unsigned char *>(buf.data()), buf.size() * sizeof(fixed_word_t));
	const bool binary = filename.size() >= 4 && filename.substr(filename.size() - 4) == ".bin";
	ofstream file(filename, binary ? ios::binary : ios::out);
	if (!file.is_open())
		SC_REPORT_FATAL("CPU", "cannot open VP output file");
	if (binary) {
		file.write(reinterpret_cast<const char *>(buf.data()), static_cast<streamsize>(buf.size() * sizeof(fixed_word_t)));
	} else {
		for (int r = 0; r < rows; r++) {
			for (int c = 0; c < cols; c++) {
				const uint64_t raw = static_cast<uint64_t>(buf[r * cols + c]) & ((uint64_t{1} << attn::ACC_BITS) - 1);
				file << uppercase << hex << setw(12) << setfill('0') << raw << "\n";
			}
		}
	}
	cout << "CPU : Saved " << dec << buf.size() << " raw 48-bit words to "
	     << filename << endl;
}
