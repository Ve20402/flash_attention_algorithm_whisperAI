#include "header/bram_tlm.h"
#include <cstring>
#include <iostream>

using namespace std;

BramTLM::BramTLM(sc_module_name name, uint64_t size_bytes)
    : sc_module(name), socket("socket"), size(size_bytes) {
	mem = new unsigned char[size];
	memset(mem, 0, size);
	socket.register_b_transport(this, &BramTLM::b_transport);
	socket.register_get_direct_mem_ptr(this, &BramTLM::get_direct_mem_ptr);
}

BramTLM::~BramTLM() {
	if (mem)
		delete[] mem;
}

void BramTLM::b_transport(tlm_generic_payload &trans, sc_time &delay) {
	tlm_command cmd = trans.get_command();
	uint64_t addr = trans.get_address();
	unsigned char *ptr = trans.get_data_ptr();
	unsigned int len = trans.get_data_length();

	if (addr + len > size) {
		trans.set_response_status(TLM_ADDRESS_ERROR_RESPONSE);
		SC_REPORT_ERROR("BRAM", "Address out of range!");
		return;
	}

	if (cmd == TLM_READ_COMMAND) {
		memcpy(ptr, &mem[addr], len);
		delay += sc_time(10, SC_NS);
	} else if (cmd == TLM_WRITE_COMMAND) {
		memcpy(&mem[addr], ptr, len);
		delay += sc_time(10, SC_NS);
	}

	trans.set_dmi_allowed(true);
	trans.set_response_status(TLM_OK_RESPONSE);
}

bool BramTLM::get_direct_mem_ptr(tlm_generic_payload &trans, tlm_dmi &dmi_data) {
	dmi_data.allow_read_write();
	dmi_data.set_dmi_ptr(mem);
	dmi_data.set_start_address(0);
	dmi_data.set_end_address(size - 1);
	dmi_data.set_read_latency(sc_time(10, SC_NS));
	dmi_data.set_write_latency(sc_time(10, SC_NS));
	return true;
}

void BramTLM::direct_write(uint64_t local_addr, unsigned char *data, int len) {
	if (local_addr + len <= size)
		memcpy(&mem[local_addr], data, len);
}

void BramTLM::direct_read(uint64_t local_addr, unsigned char *data, int len) {
	if (local_addr + len <= size)
		memcpy(data, &mem[local_addr], len);
}
