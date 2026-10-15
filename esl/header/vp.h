#ifndef VP_H
#define VP_H

#include <string>
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
	vp(sc_core::sc_module_name name, const std::string &input_path,
	   const std::string &output_path,
	   const attn::AttentionConfig &attention_config);
	~vp();

  private:
	HostMemory *host_ram;

	sc_core::sc_fifo<fixed_word_t> fifo_to_ip;
	sc_core::sc_fifo<fixed_word_t> fifo_from_ip;

	Cpu cpu;
	Interconnect bus;
	Dma dma;
	IP ip;
	BramTLM bram;
};

#endif
