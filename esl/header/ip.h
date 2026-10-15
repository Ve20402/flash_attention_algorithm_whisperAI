#ifndef IP_H
#define IP_H

#include "datatypes.h"
#include <cstdint>
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <tlm_utils/simple_target_socket.h>
#include <vector>

using namespace tlm;
using namespace tlm_utils;

SC_MODULE(IP) {

	simple_target_socket<IP> ctrl_socket;
	simple_initiator_socket<IP> bram_socket;

	sc_fifo_in<fixed_word_t> stream_in;
	sc_fifo_out<fixed_word_t> stream_out;

	unsigned char *bram_base;
	sc_core::sc_time dmi_write_latency;

	sc_event ev_start;
	sc_event ev_done;
	volatile bool done_flag;
	attn::AttentionConfig config;

	void run();
	void ctrl_b_transport(tlm_generic_payload & trans,
	                      sc_core::sc_time & delay);

	bool bram_write_word(uint64_t byte_off, fixed_word_t value);
	void acquire_dmi();
	fixed_word_t *bram_ptr(uint64_t byte_off);
	void dmi_write_from_fifo(uint64_t byte_off, uint32_t n);
	void write_stream(const fixed_word_t *src, uint32_t n);

	SC_HAS_PROCESS(IP);
	IP(sc_module_name name, const attn::AttentionConfig &attention_config);
};

#endif
