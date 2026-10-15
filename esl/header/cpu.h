#ifndef CPU_H
#define CPU_H

#include "datatypes.h"
#include "host_memory.h"
#include <string>
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <tlm_utils/tlm_quantumkeeper.h>

SC_MODULE(Cpu) {

	tlm_utils::simple_initiator_socket<Cpu> socket;

	HostMemory *host_ram;
	std::string input_path;
	std::string output_path;
	attn::AttentionConfig config;

	void run();

	void save_matrix(const std::string &filename, uint64_t addr, int rows,
	                 int cols);

	SC_HAS_PROCESS(Cpu);
	Cpu(sc_core::sc_module_name name, HostMemory * hm, const std::string &input,
	    const std::string &output,
	    const attn::AttentionConfig &attention_config)
	    : sc_module(name), socket("socket"), host_ram(hm), input_path(input),
	      output_path(output), config(attention_config) {
		SC_THREAD(run);
	}
};

#endif
