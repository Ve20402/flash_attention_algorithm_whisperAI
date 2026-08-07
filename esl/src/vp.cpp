#include "header/vp.h"
#include <iostream>

using namespace sc_core;
using namespace tlm;
using namespace std;

vp::vp(sc_module_name name)
    : sc_module(name), host_ram(new HostMemory(512 * 1024 * 1024)),
      fifo_to_ip("fifo_to_ip", 1024), fifo_from_ip("fifo_from_ip", 1024),
      cpu("cpu", host_ram), bus("bus"), dma("dma", host_ram), ip("ip"),
      bram("bram", attn::bram_size_bytes) {

	cpu.socket.bind(bus.target_socket);
	bus.ip_socket.bind(ip.ctrl_socket);
	bus.dma_socket.bind(dma.cfg_socket);

	ip.bram_socket.bind(bram.socket);

	dma.stream_to_ip(fifo_to_ip);
	ip.stream_in(fifo_to_ip);
	ip.stream_out(fifo_from_ip);
	dma.stream_from_ip(fifo_from_ip);

	SC_REPORT_INFO("VP", "Virtual Platform initialized");
}

vp::~vp() {
	delete host_ram;
}
