#include "header/dma.h"
#include "header/interconnect.h"
#include <cstring>
#include <iostream>

using namespace sc_core;
using namespace tlm;
using namespace std;

namespace {

fixed_word_t signed_q6_18(uint32_t word) {
	word &= 0x00ffffffu;
	return (word & 0x00800000u) ? static_cast<fixed_word_t>(word) - (1 << 24) : static_cast<fixed_word_t>(word);
}

}

Dma::Dma(sc_module_name name, HostMemory *hm)
    : sc_module(name), cfg_socket("cfg_socket"), stream_to_ip("stream_to_ip"),
      stream_from_ip("stream_from_ip"), host_ram(hm), reg_src_addr(0),
      reg_src_len(0), reg_dst_addr(0), reg_dst_len(0), h2d_done(true),
      d2h_done(true) {
	cfg_socket.register_b_transport(this, &Dma::cfg_b_transport);
	SC_THREAD(thread_h2d);
	SC_THREAD(thread_d2h);
}

void Dma::cfg_b_transport(tlm_generic_payload &trans, sc_time &delay) {
	uint64_t offset = trans.get_address();
	tlm_command cmd = trans.get_command();

	if (cmd == TLM_WRITE_COMMAND && trans.get_data_length() == 8) {
		uint64_t val;
		memcpy(&val, trans.get_data_ptr(), 8);
		switch (offset) {
		case DMA_REG_SRC_ADDR:
			reg_src_addr = val;
			break;
		case DMA_REG_SRC_LEN:
			reg_src_len = val;
			break;
		case DMA_REG_DST_ADDR:
			reg_dst_addr = val;
			break;
		case DMA_REG_DST_LEN:
			reg_dst_len = val;
			break;
		default:
			trans.set_response_status(TLM_ADDRESS_ERROR_RESPONSE);
			return;
		}
		trans.set_response_status(TLM_OK_RESPONSE);
		delay += sc_time(CYCLE_NS, SC_NS);
		return;
	}

	if (offset == DMA_REG_START && cmd == TLM_WRITE_COMMAND &&
	    trans.get_data_length() == 1) {
		unsigned char v = *trans.get_data_ptr();
		if (v & 0x01) {
			h2d_done = false;
			ev_start_h2d.notify(SC_ZERO_TIME);
		}
		if (v & 0x02) {
			d2h_done = false;
			ev_start_d2h.notify(SC_ZERO_TIME);
		}
		trans.set_response_status(TLM_OK_RESPONSE);
		delay += sc_time(CYCLE_NS, SC_NS);
		return;
	}

	if (offset == DMA_REG_STATUS && cmd == TLM_READ_COMMAND &&
	    trans.get_data_length() == 1) {
		*trans.get_data_ptr() = (h2d_done ? 0x01 : 0) | (d2h_done ? 0x02 : 0);
		trans.set_response_status(TLM_OK_RESPONSE);
		delay += sc_time(CYCLE_NS, SC_NS);
		return;
	}

	trans.set_response_status(TLM_ADDRESS_ERROR_RESPONSE);
}

void Dma::thread_h2d() {
	while (true) {
		wait(ev_start_h2d);

		uint64_t addr = reg_src_addr;
		uint64_t n = reg_src_len;
		uint64_t cycles = 0;

		uint64_t i = 0;
		while (i + 1 < n) {
			uint32_t raw_a = 0, raw_b = 0;
			host_ram->read(addr, reinterpret_cast<unsigned char *>(&raw_a),
			               sizeof(raw_a));
			host_ram->read(addr + sizeof(raw_a),
			               reinterpret_cast<unsigned char *>(&raw_b),
			               sizeof(raw_b));
			const fixed_word_t a = signed_q6_18(raw_a);
			const fixed_word_t b = signed_q6_18(raw_b);
			stream_to_ip.write(a);
			stream_to_ip.write(b);
			addr += sizeof(raw_a) + sizeof(raw_b);
			i += 2;
			cycles++;
		}
		if (i < n) {
			uint32_t raw = 0;
			host_ram->read(addr, reinterpret_cast<unsigned char *>(&raw),
			               sizeof(raw));
			const fixed_word_t a = signed_q6_18(raw);
			stream_to_ip.write(a);
			i++;
			cycles++;
		}

		wait(sc_time(cycles * CYCLE_NS, SC_NS));
		h2d_done = true;
	}
}

void Dma::thread_d2h() {
	while (true) {
		wait(ev_start_d2h);

		uint64_t addr = reg_dst_addr;
		uint64_t total = reg_dst_len;
		uint64_t cycles = 0;

		uint64_t i = 0;
		while (i + 1 < total) {
			fixed_word_t a = stream_from_ip.read();
			fixed_word_t b = stream_from_ip.read();
			host_ram->write(addr, reinterpret_cast<unsigned char *>(&a),
			                sizeof(a));
			host_ram->write(addr + sizeof(a),
			                reinterpret_cast<unsigned char *>(&b), sizeof(b));
			addr += 2 * sizeof(a);
			i += 2;
			cycles++;
		}
		if (i < total) {
			fixed_word_t a = stream_from_ip.read();
			host_ram->write(addr, reinterpret_cast<unsigned char *>(&a),
			                sizeof(a));
			i++;
			cycles++;
		}

		wait(sc_time(cycles * CYCLE_NS, SC_NS));
		d2h_done = true;
	}
}
