# FlashAttention Accelerator for the Whisper Encoder

SystemC/TLM and VHDL implementation of a tiled FlashAttention accelerator
targeting the Whisper encoder.

The project was developed at two abstraction levels:

- **ESL:** a loosely timed SystemC/TLM 2.0 virtual platform integrating a CPU,
  memory-mapped interconnect, bidirectional DMA controller, accelerator IP,
  local BRAM and host memory;
- **RTL:** a VHDL accelerator implementing tiled online softmax, eight parallel
  MAC units, banked BRAMs, double-buffered K/V tiles, pipelined computation and
  fixed-point arithmetic.

The hand-written RTL implementation was derived from the behavioral HLS model
defined in `ip_hls.cpp`, `ip_hls.h` and `exp_table.h`.

The accelerator processes Whisper encoder attention without storing the complete
attention matrix, reducing intermediate attention-storage complexity from
O(n²) to O(n).

## Repository structure

```text
esl/      SystemC/TLM virtual platform and software reference
rtl/      VHDL accelerator and testbenches
docs/     Detailed architecture and project documentation
data/     Test vectors and numerical results
```

## Requirements

The project was developed and tested on Ubuntu 24.04 LTS.

Required packages:

```bash
sudo apt install git build-essential python3 python3-pip python3-dev \
    python3-venv libsystemc-dev libportaudio2 make
```

## Running the ESL model

```bash
cd esl
make app
```

This command:

1. builds the C++/Pybind11 attention reference model,
2. runs the IP,
3. builds and executes the SystemC/TLM virtual platform,
4. compares the virtual-platform output against the software reference.

To build and run only the virtual platform:

```bash
cd esl
make vp
```

## Current status

- C++/Python reference model: implemented.
- SystemC/TLM virtual platform: implemented and functionally validated.
- VHDL accelerator: implemented.
- Zybo Z7-10 integration and software driver: planned

## Documentation

Detailed architecture, implementation and verification information is available
in the [project_documentation](docs/project_documentation.pdf).

The RTL implementation section of the documentation is still in progress.