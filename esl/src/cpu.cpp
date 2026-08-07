#include "header/cpu.h"
#include "header/dma.h"
#include "header/interconnect.h"
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <vector>

using namespace sc_core;
using namespace tlm;
using namespace tlm_utils;
using namespace std;

static const int ROWS = 1500, COLS = 512, HEAD_DIM = 64, NUM_HEADS = 8;
static const int B = 32, BC = 64;

static const uint64_t ADDR_FEED = 0ULL;

static void mmio_w1(simple_initiator_socket<Cpu> &sock, uint64_t addr, unsigned char val, sc_time &loct) {
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

static void mmio_w8(simple_initiator_socket<Cpu> &sock, uint64_t addr, uint64_t value, sc_time &loct) {
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

static unsigned char mmio_r1(simple_initiator_socket<Cpu> &sock, uint64_t addr, sc_time &loct) {
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

static vector<float> read_floats(const string &filename) {
	ifstream file(filename);
	if (!file.is_open()) {
		cerr << "ERROR: cannot open " << filename << endl;
		return {};
	}
	vector<float> buf;
	float v;
	while (file >> v)
		buf.push_back(v);
	return buf;
}

static vector<float> build_feed(const vector<float> &Q, const vector<float> &K,
                                const vector<float> &V, const vector<float> &W,
                                const vector<float> &b) {
	vector<float> feed;
	feed.reserve(86ULL * 1024 * 1024);

	for (int c = 0; c < COLS; c++)
		feed.push_back(b[c]);

	for (int qi = 0; qi < ROWS; qi += B) {
		int br = min(B, ROWS - qi);
		for (int h = 0; h < NUM_HEADS; h++) {

			for (int r = 0; r < br; r++)
				for (int d = 0; d < HEAD_DIM; d++)
					feed.push_back(Q[(qi + r) * COLS + h * HEAD_DIM + d]);

			for (int j = 0; j < ROWS; j += BC) {
				int bc = min(BC, ROWS - j);
				for (int r = 0; r < bc; r++)
					for (int d = 0; d < HEAD_DIM; d++)
						feed.push_back(K[(j + r) * COLS + h * HEAD_DIM + d]);
				for (int r = 0; r < bc; r++)
					for (int d = 0; d < HEAD_DIM; d++)
						feed.push_back(V[(j + r) * COLS + h * HEAD_DIM + d]);
			}

			for (int r = 0; r < HEAD_DIM; r++)
				for (int c = 0; c < COLS; c++)
					feed.push_back(W[(h * HEAD_DIM + r) * COLS + c]);
		}
	}
	return feed;
}

void Cpu::run() {
	sc_time loct = SC_ZERO_TIME;

	cout << "\nCPU : Loading matrices..." << endl;
	vector<float> Q = read_floats("../data/matrice/multihead_ulaz_Q.txt");
	vector<float> K = read_floats("../data/matrice/multihead_ulaz_K.txt");
	vector<float> V = read_floats("../data/matrice/multihead_ulaz_V.txt");
	vector<float> W = read_floats("../data/matrice/multihead_W_out.txt");
	vector<float> b = read_floats("../data/matrice/multihead_b_out.txt");

	cout << "CPU : Building stream order..." << endl;
	vector<float> feed = build_feed(Q, K, V, W, b);
	uint64_t feed_len = feed.size();

	uint64_t feed_bytes = feed_len * 4;
	uint64_t feed_end = ADDR_FEED + feed_bytes;
	uint64_t addr_y = ((feed_end + 7) / 8) * 8;
	host_ram->write(ADDR_FEED, reinterpret_cast<unsigned char *>(feed.data()), feed_bytes);

	cout << "CPU : Setting up DMA (SRC=feed, DST=Y)..." << endl;
	mmio_w8(socket, ADDR_DMA_SRC_ADDR, ADDR_FEED, loct);
	mmio_w8(socket, ADDR_DMA_SRC_LEN, feed_len, loct);
	mmio_w8(socket, ADDR_DMA_DST_ADDR, addr_y, loct);
	mmio_w8(socket, ADDR_DMA_DST_LEN, (uint64_t)ROWS * COLS, loct);

	cout << "CPU : Starting DMA and IP..." << endl;
	mmio_w1(socket, ADDR_DMA_START, 0x03, loct);
	mmio_w1(socket, ADDR_CTRL, 0x01, loct);

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

	cout << "CPU : Saving Y..." << endl;
	save_matrix("../data/vp_output.txt", addr_y, ROWS, COLS);

	cout << "CPU : Complete @ " << sc_time_stamp() << endl;
	sc_stop();
}

void Cpu::save_matrix(const string &filename, uint64_t addr, int rows, int cols) {
	vector<float> buf(rows * cols);
	host_ram->read(addr, reinterpret_cast<unsigned char *>(buf.data()),
	               buf.size() * 4);
	ofstream file(filename);
	for (int r = 0; r < rows; r++) {
		for (int c = 0; c < cols; c++) {
			file << fixed << setprecision(8) << buf[r * cols + c];
			if (c < cols - 1)
				file << " ";
		}
		file << "\n";
	}
	cout << "CPU : Saved " << buf.size() << " floats to " << filename << endl;
}
