#include "header/interconnect.h"
#include <iostream>

using namespace std;
using namespace tlm;

void Interconnect::b_transport(int id, tlm_generic_payload &trans,
                               sc_time &delay) {

	uint64_t global_addr = trans.get_address();

	if (global_addr >= IP_BASE && global_addr < IP_BASE + IP_SIZE) {
		trans.set_address(global_addr - IP_BASE);
		ip_socket->b_transport(trans, delay);
		trans.set_address(global_addr);
		return;
	}

	if (global_addr >= DMA_BASE && global_addr < DMA_BASE + DMA_SIZE) {
		trans.set_address(global_addr - DMA_BASE);
		dma_socket->b_transport(trans, delay);
		trans.set_address(global_addr);
		return;
	}

	cerr << "Interconnect ERROR: unmapped address 0x" << hex << global_addr
	     << dec << endl;
	trans.set_response_status(TLM_ADDRESS_ERROR_RESPONSE);
}
