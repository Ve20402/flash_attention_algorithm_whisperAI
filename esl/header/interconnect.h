#ifndef INTERCONNECT_H
#define INTERCONNECT_H

#include "dma.h"
#include <systemc.h>
#include <tlm.h>
#include <tlm_utils/multi_passthrough_target_socket.h>
#include <tlm_utils/simple_initiator_socket.h>

using namespace tlm;
using namespace tlm_utils;

const uint64_t IP_BASE = 0x40000000ULL;
const uint64_t IP_SIZE = 0x100ULL;

const uint64_t DMA_BASE = 0x40001000ULL;
const uint64_t DMA_SIZE = 0x100ULL;

const uint64_t IP_REG_CTRL = 0x00ULL;
const uint64_t IP_REG_STATUS = 0x04ULL;

const uint64_t DMA_REG_SRC_ADDR = 0x00ULL;
const uint64_t DMA_REG_SRC_LEN = 0x08ULL;
const uint64_t DMA_REG_DST_ADDR = 0x10ULL;
const uint64_t DMA_REG_DST_LEN = 0x18ULL;
const uint64_t DMA_REG_START = 0x20ULL;
const uint64_t DMA_REG_STATUS = 0x24ULL;

const uint64_t ADDR_CTRL = IP_BASE + IP_REG_CTRL;
const uint64_t ADDR_STATUS = IP_BASE + IP_REG_STATUS;

const uint64_t ADDR_DMA_SRC_ADDR = DMA_BASE + DMA_REG_SRC_ADDR;
const uint64_t ADDR_DMA_SRC_LEN = DMA_BASE + DMA_REG_SRC_LEN;
const uint64_t ADDR_DMA_DST_ADDR = DMA_BASE + DMA_REG_DST_ADDR;
const uint64_t ADDR_DMA_DST_LEN = DMA_BASE + DMA_REG_DST_LEN;
const uint64_t ADDR_DMA_START = DMA_BASE + DMA_REG_START;
const uint64_t ADDR_DMA_STATUS = DMA_BASE + DMA_REG_STATUS;

SC_MODULE(Interconnect) {

	multi_passthrough_target_socket<Interconnect> target_socket;

	simple_initiator_socket<Interconnect> ip_socket;
	simple_initiator_socket<Interconnect> dma_socket;

	void b_transport(int id, tlm_generic_payload &trans, sc_time &delay);

	SC_CTOR(Interconnect)
	    : target_socket("target_socket"), ip_socket("ip_socket"),
	      dma_socket("dma_socket") {
		target_socket.register_b_transport(this, &Interconnect::b_transport);
	}
};

#endif
