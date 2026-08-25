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
make app
```

This command:

1. creates `esl/.venv` and installs dependencies when needed,
2. builds and runs the C++/Pybind11 attention reference model,
3. builds and executes the SystemC/TLM virtual platform,
4. compares the virtual-platform output against the software reference.

`make app` stores the complete real Whisper tensors in `data/matrice/`:

- `multihead_ulaz_Q.txt`, `multihead_ulaz_K.txt`, `multihead_ulaz_V.txt`;
- `multihead_output_pre_wout.txt` for RTL comparison before `out_proj`;
- `output_main_app.txt` for virtual-platform comparison after `out_proj`.

To run the short GHDL regression with real Whisper data (head 3, one 32-row
Q block against all 1500 K/V rows):

```bash
make head
```

The regression compares 2,048 RTL values directly against the matching slice
of `multihead_output_pre_wout.txt`. Because all 1500 K/V rows are retained,
the softmax domain is identical to the original full-context Whisper run.
Progress is printed after every 8,192 transferred RTL input words.

To remove generated build files and short RTL vectors while retaining the
Python environment and complete ESL matrices:

```bash
make clean
```

The repository exposes only `make app`, `make head` and `make clean`.

## Current status

- C++/Python reference model: implemented.
- SystemC/TLM virtual platform: implemented and functionally validated.
- VHDL accelerator: implemented.
- Zybo Z7-10 integration and software driver: planned

## Documentation

Detailed architecture, implementation and verification information is available
in the [project_documentation](docs/project_documentation.pdf).

The RTL implementation section of the documentation is still in progress.
