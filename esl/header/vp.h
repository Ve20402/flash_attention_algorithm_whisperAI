#ifndef VP_H
#define VP_H

#include <systemc>

#include "bram_tlm.h"
#include "cpu.h"
#include "datatypes.h"
#include "dma.h"
#include "host_memory.h"
#include "interconnect.h"
#include "ip.h"

class vp : public sc_core::sc_module {
  public:
	vp(sc_core::sc_module_name name);
	~vp();

  private:
	HostMemory *host_ram;

	sc_core::sc_fifo<float> fifo_to_ip;
	sc_core::sc_fifo<float> fifo_from_ip;

	Cpu cpu;
	Interconnect bus;
	Dma dma;
	IP ip;
	BramTLM bram;
};

#endif
