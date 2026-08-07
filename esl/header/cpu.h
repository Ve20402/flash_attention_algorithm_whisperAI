#ifndef CPU_H
#define CPU_H

#include "host_memory.h"
#include <string>
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <tlm_utils/tlm_quantumkeeper.h>

SC_MODULE(Cpu) {

	tlm_utils::simple_initiator_socket<Cpu> socket;

	HostMemory *host_ram;

	void run();

	void save_matrix(const std::string &filename, uint64_t addr, int rows, int cols);

	SC_HAS_PROCESS(Cpu);
	Cpu(sc_core::sc_module_name name, HostMemory * hm)
	    : sc_module(name), socket("socket"), host_ram(hm) {
		SC_THREAD(run);
	}
};

#endif
