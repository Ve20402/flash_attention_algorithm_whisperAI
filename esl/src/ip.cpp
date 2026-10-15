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

IP::IP(sc_module_name name, const AttentionConfig &attention_config)
    : sc_module(name), ctrl_socket("ctrl_socket"), bram_socket("bram_socket"),
      stream_in("stream_in"), stream_out("stream_out"), bram_base(nullptr),
      dmi_write_latency(SC_ZERO_TIME), done_flag(false),
      config(attention_config) {
	if (config.query_rows <= 0 || config.kv_rows <= 0 || config.heads <= 0 ||
	    config.head_dim != HEAD_DIM)
		SC_REPORT_FATAL("IP", "wrong configuration");
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

void IP::write_stream(const fixed_word_t *src, uint32_t n) {
	for (uint32_t i = 0; i < n; i++)
		stream_out.write(src[i]);
}

bool IP::bram_write_word(uint64_t byte_off, fixed_word_t value) {
	tlm_generic_payload trans;
	sc_time delay = SC_ZERO_TIME;
	trans.set_command(TLM_WRITE_COMMAND);
	trans.set_address(byte_off);
	trans.set_data_ptr((unsigned char *)&value);
	trans.set_data_length(WORD_BYTES);
	trans.set_streaming_width(WORD_BYTES);
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
	trans.set_data_length(WORD_BYTES);
	bool ok = bram_socket->get_direct_mem_ptr(trans, dmi);
	if (ok == false || dmi.is_read_allowed() == false ||
	    dmi.is_write_allowed() == false)
		SC_REPORT_FATAL("IP", "Nema DMI pointer");
	bram_base = dmi.get_dmi_ptr();
	dmi_write_latency = dmi.get_write_latency();
}

fixed_word_t *IP::bram_ptr(uint64_t byte_off) {
	return reinterpret_cast<fixed_word_t *>(bram_base + byte_off);
}

void IP::dmi_write_from_fifo(uint64_t byte_off, uint32_t n) {
	fixed_word_t *dst = bram_ptr(byte_off);
	for (uint32_t i = 0; i < n; i++)
		dst[i] = stream_in.read();
}

void IP::run() {
	const double IP_TOTAL_CYCLES = 1500000.0;
	const double CLK_NS = 10.0;
	sc_time T_IP(IP_TOTAL_CYCLES * CLK_NS, SC_NS);

	while (true) {
		wait(ev_start);
		done_flag = false;

		acquire_dmi();

		fixed_word_t *Q_tile = bram_ptr(offset_Q);
		fixed_word_t *K_tile = bram_ptr(offset_K);
		fixed_word_t *V_tile = bram_ptr(offset_V);
		fixed_word_t *O_acc = bram_ptr(offset_O);
		fixed_word_t *m_buf = bram_ptr(offset_m);
		fixed_word_t *l_buf = bram_ptr(offset_l);

		for (int query_start = 0; query_start < config.query_rows;
		     query_start += B) {
			const int query_tile_rows =
			    std::min(B, config.query_rows - query_start);
			for (int head = 0; head < config.heads; ++head) {
				dmi_write_from_fifo(offset_Q,
				                    query_tile_rows * config.head_dim);
				flash_attn_init(m_buf, l_buf, O_acc, query_tile_rows,
				                config.head_dim);

				for (int kv_start = 0; kv_start < config.kv_rows;
				     kv_start += BC) {
					const int kv_tile_rows =
					    std::min(BC, config.kv_rows - kv_start);
					dmi_write_from_fifo(offset_K,
					                    kv_tile_rows * config.head_dim);
					dmi_write_from_fifo(offset_V,
					                    kv_tile_rows * config.head_dim);
					flash_attn_step(Q_tile, query_tile_rows, K_tile, V_tile,
					                kv_tile_rows, m_buf, l_buf, O_acc,
					                config.head_dim);
				}

				flash_attn_finalize(O_acc, l_buf, query_tile_rows,
				                    config.head_dim);
				write_stream(O_acc, query_tile_rows * config.head_dim);
			}
			cout << "IP: Q rows " << query_start << ".."
			     << query_start + query_tile_rows - 1 << " / "
			     << config.query_rows << endl;
		}

		wait(T_IP);
		cout << "[" << sc_time_stamp() << "] IP: gotovo" << endl;
		done_flag = true;
		ev_done.notify();
	}
}
