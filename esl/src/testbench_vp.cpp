#include "header/vp.h"
#include <iostream>
#include <systemc.h>

int sc_main(int argc, char *argv[]) {
	if (argc != 3 && argc != 6) {
		std::cerr << "Usage: " << argv[0]
		          << " <fixed_input.bin> <vp_output.{hex|bin}> "
		             "[query_rows kv_rows heads]\n";
		return 2;
	}
	attn::AttentionConfig config;
	if (argc == 6) {
		try {
			config.query_rows = std::stoi(argv[3]);
			config.kv_rows = std::stoi(argv[4]);
			config.heads = std::stoi(argv[5]);
		} catch (const std::exception &) {
			std::cerr << "Invalid numeric attention configuration\n";
			return 2;
		}
	}

	tlm::tlm_global_quantum::instance().set(
	    sc_core::sc_time(10, sc_core::SC_NS));

	vp platform("Virtual_Platform", argv[1], argv[2], config);

	std::cout << "\n Starting TLM 2.0 LT simulation...\n" << std::endl;
	sc_start();

	std::cout << "\nTotal simulation time: " << sc_core::sc_time_stamp()
	          << std::endl;
	return 0;
}
