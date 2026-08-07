#include "header/vp.h"
#include <iostream>
#include <systemc.h>

int sc_main(int argc, char *argv[]) {
	tlm::tlm_global_quantum::instance().set(
	    sc_core::sc_time(10, sc_core::SC_NS));

	vp platform("Virtual_Platform");

	std::cout << "\n Starting TLM 2.0 LT simulation...\n" << std::endl;
	sc_start();

	std::cout << "\nTotal simulation time: " << sc_core::sc_time_stamp() << std::endl;
	return 0;
}
