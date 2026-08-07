#include "header/ip.h"
#include "header/bram_tlm.h"
#include "header/datatypes.h"
#include "header/interconnect.h"
#include "header/matrix_ops.h"
#include <algorithm>
#include <iostream>

using namespace std;
using namespace sc_core;
using namespace tlm;
using namespace attn;

IP::IP(sc_module_name name)
    : sc_module(name), ctrl_socket("ctrl_socket"), bram_socket("bram_socket"),
      stream_in("stream_in"), stream_out("stream_out"), bram_base(nullptr),
      dmi_write_latency(SC_ZERO_TIME), done_flag(false) {
	ctrl_socket.register_b_transport(this, &IP::ctrl_b_transport);
	SC_THREAD(run);
}

void IP::ctrl_b_transport(tlm_generic_payload &trans, sc_time &delay) {
	uint64_t offset = trans.get_address();
	tlm_command cmd = trans.get_command();

	if (offset == IP_REG_CTRL && cmd == TLM_WRITE_COMMAND) {
		if (*trans.get_data_ptr() & 0x01) {
			done_flag = false;
			ev_start.notify(SC_ZERO_TIME);
		}
		trans.set_response_status(TLM_OK_RESPONSE);
		delay += sc_time(10, SC_NS);
		return;
	}
	if (offset == IP_REG_STATUS && cmd == TLM_READ_COMMAND) {
		*trans.get_data_ptr() = done_flag ? 1u : 0u;
		trans.set_response_status(TLM_OK_RESPONSE);
		delay += sc_time(10, SC_NS);
		return;
	}
	trans.set_response_status(TLM_ADDRESS_ERROR_RESPONSE);
}

void IP::write_stream(const float *src, uint32_t n) {
	for (uint32_t i = 0; i < n; i++)
		stream_out.write(src[i]);
}

bool IP::bram_write_word(uint64_t byte_off, float value) {
	tlm_generic_payload trans;
	sc_time delay = SC_ZERO_TIME;
	trans.set_command(TLM_WRITE_COMMAND);
	trans.set_address(byte_off);
	trans.set_data_ptr((unsigned char *)&value);
	trans.set_data_length(FLOAT_BYTES);
	trans.set_streaming_width(FLOAT_BYTES);
	trans.set_byte_enable_ptr(0);
	trans.set_response_status(TLM_INCOMPLETE_RESPONSE);
	bram_socket->b_transport(trans, delay);
	wait(delay);
	return trans.is_dmi_allowed();
}

void IP::acquire_dmi() {
	tlm_generic_payload trans;
	tlm_dmi dmi;
	trans.set_command(TLM_READ_COMMAND);
	trans.set_address(0);
	trans.set_data_length(FLOAT_BYTES);
	bool ok = bram_socket->get_direct_mem_ptr(trans, dmi);
	if (ok == false || dmi.is_read_allowed() == false ||
	    dmi.is_write_allowed() == false)
		SC_REPORT_FATAL("IP", "Nema DMI pointer");
	bram_base = dmi.get_dmi_ptr();
	dmi_write_latency = dmi.get_write_latency();
}

float *IP::bram_ptr(uint64_t byte_off) {
	return (float *)(bram_base + byte_off);
}

void IP::dmi_write_from_fifo(uint64_t byte_off, uint32_t n) {
	float *dst = bram_ptr(byte_off);
	for (uint32_t i = 0; i < n; i++)
		dst[i] = stream_in.read();
}

void IP::run() {
	const double IP_TOTAL_CYCLES = 677238749.0;
	const double CLK_NS = 10.0;
	sc_time T_IP(IP_TOTAL_CYCLES * CLK_NS, SC_NS);

	while (true) {
		wait(ev_start);
		done_flag = false;

		float first = stream_in.read();
		bool dmi_ok = bram_write_word(offset_bias, first);
		if (dmi_ok == false)
			SC_REPORT_FATAL("IP", "BRAM nije ponudio DMI");
		acquire_dmi();

		float *bias = bram_ptr(offset_bias);
		float *Q_tile = bram_ptr(offset_Q);
		float *W_row = bram_ptr(offset_W);
		float *K_tile = bram_ptr(offset_K);
		float *V_tile = bram_ptr(offset_V);
		float *O_acc = bram_ptr(offset_O);
		float *m_buf = bram_ptr(offset_m);
		float *l_buf = bram_ptr(offset_l);
		float *Y_tile = bram_ptr(offset_Y);

		for (int i = 1; i < COLS; i++)
			bias[i] = stream_in.read();

		for (int qi = 0; qi < ROWS; qi += B) {
			int br = std::min(B, ROWS - qi);

			for (int r = 0; r < br; r++)
				for (int c = 0; c < COLS; c++)
					Y_tile[r * COLS + c] = bias[c];

			for (int h = 0; h < NUM_HEADS; h++) {
				dmi_write_from_fifo(offset_Q, br * HEAD_DIM);

				flash_attn_init(m_buf, l_buf, O_acc, br, HEAD_DIM);

				for (int j = 0; j < ROWS; j += BC) {
					int bc = std::min(BC, ROWS - j);

					dmi_write_from_fifo(offset_K, bc * HEAD_DIM);
					dmi_write_from_fifo(offset_V, bc * HEAD_DIM);

					flash_attn_step(Q_tile, br, K_tile, V_tile, bc, m_buf, l_buf, O_acc, HEAD_DIM);
				}

				flash_attn_finalize(O_acc, l_buf, br, HEAD_DIM);

				for (int k = 0; k < HEAD_DIM; k++) {
					dmi_write_from_fifo(offset_W, COLS);
					for (int r = 0; r < br; r++)
						for (int c = 0; c < COLS; c++)
							Y_tile[r * COLS + c] +=
							    O_acc[r * HEAD_DIM + k] * W_row[c];
				}
			}

			write_stream(Y_tile, br * COLS);
		}

		wait(T_IP);
		cout << "[" << sc_time_stamp() << "] IP: gotovo" << endl;
		done_flag = true;
		ev_done.notify();
	}
}
