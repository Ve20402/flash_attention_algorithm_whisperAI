# FlashAttention FPGA accelerator for Whisper encoder attention

This project implements a tiled, fixed-point FPGA accelerator for self-attention in the Whisper encoder. It covers the full development process, from a software reference and SystemC/TLM virtual platform to a hand-written VHDL design, UVM verification, and testing on a Zynq FPGA board.

The accelerator handles the attention operation within Whisper. Python and C/C++ code prepare the input tensors, check numerical accuracy, and connect the hardware to the transcription workflow.

## What the design does

For each attention head, the accelerator reads Q, K, and V in tiles, computes attention scores with an online softmax, and accumulates the weighted V output. Processing tiles lets it avoid storing the full attention matrix. The VHDL design uses fixed-point arithmetic, local memories, pipelined computation, and AXI4-Stream interfaces for input and output.

The design has been tested on a Zybo Z7-10 board, including the Linux drivers and the software used to control the accelerator. The board setup works as expected.

Different stages use different configurations. UVM regression uses small parameterized cases, the RTL test with real Whisper data uses one head with the full 1,500-row K/V context, and the board software targets a full eight-head encoder layer. Keep these differences in mind when comparing results.

## Development and validation flow

1. **Software and ESL:** `esl/final_app.py` loads Whisper Base and replaces encoder self-attention with the fixed-point virtual platform for comparison. The C++ reference and SystemC/TLM platform model the CPU, DMA, interconnect, memory, and accelerator. An HLS-style prototype in `esl/hls_deo/` was used to explore the algorithm and architecture. The final VHDL implementation was written separately.
2. **RTL:** `rtl/hdl/` contains the VHDL accelerator, including the stream wrapper, control logic, datapath, memories, and exponential and reciprocal lookup tables. VHDL testbenches are in `rtl/tb/`, and `rtl/script/build_project.tcl` builds and packages the IP in Vivado. A bare-metal Zynq test application and reference vectors are in `rtl/software/`.
3. **Verification:** `uvm/` contains the SystemVerilog/UVM testbench. Master and slave agents drive and monitor the AXI4-Stream interfaces, while a reference model and scoreboard check the results. Tests cover protocol behavior, randomized timing, input and output stalls, and reset during computation.
4. **Board software:** `driver/driver/` contains the tested Linux platform driver, which uses DMA, GPIO, and a `/dev/fa_axis` device. The C application in `driver/app/test/` prepares the input stream, starts the accelerator, and compares its output with a golden file. The board script and bitstream are in `driver/run_fa.sh` and `driver/bitstream/`. To use this setup on another system, match the FPGA image, device tree, and kernel to the target board.

## Repository map

| Path | Contents |
| --- | --- |
| `esl/` | Whisper integration, numerical preparation, C++ reference, SystemC/TLM virtual platform, HLS-style prototype |
| `rtl/hdl/`, `rtl/tb/`, `rtl/software/`, `rtl/script/` | VHDL IP, VHDL tests, Zynq application and vectors, Vivado build script |
| `uvm/` | Active UVM environment, test matrix, and reproducible Vivado/XSim launcher |
| `driver/` | Linux driver, C test application, board script, and bitstream |
| `data/` | Sample input and analysis files. Generated tensor data is omitted from Git |
| `docs/` | Detailed project, RTL, verification, and driver documentation |

## Reproducing the UVM regression

The UVM regression uses **Vivado 2025.2 and XSim**. Start Vivado without an open project and run:

```tcl
source <repository-path>/uvm/scripts/run_fresh.tcl
```

The launcher creates a local project using the sources in `rtl/hdl/` and `uvm/`. It runs three `extended` cases from `uvm/scripts/tests.tsv`, covering randomized input with partial tiles, randomized input and output stalls, and reset during computation. The separate `numeric_range` case is a diagnostic test and runs outside this regression. See [the UVM README](uvm/README.md) for the testbench layout and result files.

A fresh Vivado/XSim run passed all three regression tests:

- `random_input_combined`: 3,584 outputs checked.
- `random_stalls_combined`: 3,072 outputs checked.
- `reset_compute`: reset checks passed.

Functional coverage databases were also generated and merged. Build and result directories are ignored by Git, so run the launcher to generate them locally.

## Other entry points

- `esl/final_app.py` runs the Whisper software and virtual platform integration. It uses PyTorch, Transformers, NumPy, audio libraries, and the project's compiled C++/SystemC components. Settings near the top of the file control audio input, attention layer replacement, comparisons, and matrix exports.
- The root `Makefile` provides targets for the ESL model (`make app`) and a GHDL test with real Whisper data (`make head`). These targets predate the folder reorganization and have not been revalidated in this checkout. Check their source paths and data-export settings before running them.
- `rtl/script/build_project.tcl` runs synthesis, implementation, report generation, and IP packaging in Vivado for the Zybo Z7-10.
- `driver/driver/Makefile` and `driver/app/test/Makefile` build the Linux kernel module and C test application on a configured target system. Both the driver and application have been tested on the board.

## Documentation

The detailed documents are in `docs/`:

- [Project and ESL documentation](docs/project_documentation.pdf): algorithm, SystemC/TLM platform, and design flow.
- [RTL documentation](docs/FA_RTL_dokumentacija.pdf): VHDL architecture and implementation.
- [UVM verification documentation](docs/Verifikacija_dokumentacija.pdf): verification environment and tests.
- [Driver documentation](docs/Drajveri_dokumentacija.pdf): Zynq software and Linux driver.

The [documentation index](docs/README.md) links to the same files.
