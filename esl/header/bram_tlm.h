#ifndef BRAM_TLM_H
#define BRAM_TLM_H

#include "datatypes.h"
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/simple_target_socket.h>

using namespace tlm;
using namespace tlm_utils;

namespace attn {
const int WORD_BYTES = sizeof(fixed_word_t);
const int offset_Q = 0;
const int offset_K = offset_Q + B * HEAD_DIM * WORD_BYTES;
const int offset_V = offset_K + BC * HEAD_DIM * WORD_BYTES;
const int offset_O = offset_V + BC * HEAD_DIM * WORD_BYTES;
const int offset_m = offset_O + B * HEAD_DIM * WORD_BYTES;
const int offset_l = offset_m + B * WORD_BYTES;
const int bram_size_bytes = offset_l + B * WORD_BYTES;
} // namespace attn

SC_MODULE(BramTLM) {
	simple_target_socket<BramTLM> socket;
	unsigned char *mem;
	uint64_t size;

	void b_transport(tlm_generic_payload & trans, sc_time & delay);
	bool get_direct_mem_ptr(tlm_generic_payload & trans, tlm_dmi & dmi_data);

	void direct_write(uint64_t local_addr, unsigned char *data, int len);
	void direct_read(uint64_t local_addr, unsigned char *data, int len);

	BramTLM(sc_module_name name, uint64_t size_bytes = 1024);

	~BramTLM();
};

#endif
