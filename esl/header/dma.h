#ifndef DMA_H
#define DMA_H

#include "datatypes.h"
#include "host_memory.h"
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_target_socket.h>

using namespace tlm;
using namespace tlm_utils;

SC_MODULE(Dma) {

	simple_target_socket<Dma> cfg_socket;
	sc_fifo_out<fixed_word_t> stream_to_ip;
	sc_fifo_in<fixed_word_t> stream_from_ip;
	HostMemory *host_ram;

	uint64_t reg_src_addr;
	uint64_t reg_src_len;

	uint64_t reg_dst_addr;
	uint64_t reg_dst_len;

	sc_event ev_start_h2d;
	sc_event ev_start_d2h;
	volatile bool h2d_done;
	volatile bool d2h_done;

	int CYCLE_NS = 10;

	void cfg_b_transport(tlm_generic_payload & trans, sc_core::sc_time & delay);
	void thread_h2d();
	void thread_d2h();

	SC_HAS_PROCESS(Dma);
	Dma(sc_module_name name, HostMemory * hm);
};

#endif
