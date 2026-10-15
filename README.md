# FlashAttention FPGA accelerator for Whisper encoder attention

This academic project explores a tiled, fixed-point accelerator for the self-attention operation in the Whisper encoder. It follows the design from a software reference and SystemC/TLM virtual platform through a hand-written VHDL implementation, UVM verification, and software that prepares data for a Zynq FPGA system.

The FPGA implements the attention operation, not the entire Whisper model. The surrounding Python and C/C++ code supplies tensors, evaluates numerical behavior, and connects the accelerator to a larger transcription workflow.

## What the design does

For each attention head, the accelerator consumes Q, K, and V values in tiles, computes attention scores and an online softmax, and accumulates the weighted V output. Tiling avoids materializing the full quadratic attention matrix. The RTL uses fixed-point arithmetic, local memories, pipelined computation, and AXI4-Stream input and output interfaces. The integration target is a Zynq-based Zybo Z7-10 system.

The main configurations used by different parts of the project are intentional: small parameterized cases are used in UVM regression, a single head with the full 1,500-row K/V context is used in the RTL real-data test, and the board software targets the full eight-head encoder layer. Results from these configurations should not be treated as interchangeable performance measurements.

## Development and validation flow

1. **Software and ESL:** `esl/final_app.py` loads Whisper Base and replaces encoder self-attention with the fixed-point virtual-platform path for comparison. The C++ reference and SystemC/TLM platform model the CPU, DMA, interconnect, memory, and accelerator behavior. `esl/hls_deo/` contains a behavioral HLS-style prototype used during algorithm and architecture exploration; the VHDL was written separately.
2. **RTL:** `rtl/hdl/` contains the VHDL accelerator, including the stream wrapper, control and datapath, memories, and exponential/reciprocal lookup tables. `rtl/tb/` contains VHDL testbenches; `rtl/script/build_project.tcl` builds and packages the IP in Vivado. `rtl/software/` contains a bare-metal Zynq test application and its reference vectors.
3. **Verification:** `uvm/` contains the active SystemVerilog/UVM testbench. Master and slave agents drive and observe the AXI4-Stream interfaces. A reference model and scoreboard compare results; protocol checks, functional coverage, randomized timing, and a reset-during-computation test exercise the interface and control behavior.
4. **Board software:** `driver/driver/` contains a Linux platform driver using DMA, GPIO, and a `/dev/fa_axis` device. `driver/app/test/` contains a C program that builds the input stream, starts the accelerator, and compares output with a golden file. `driver/run_fa.sh` and `driver/bitstream/` are board-specific integration artifacts. They require a matching FPGA image, device tree, kernel, and target setup.

## Repository map

| Path | Contents |
| --- | --- |
| `esl/` | Whisper integration, numerical preparation, C++ reference, SystemC/TLM virtual platform, HLS-style prototype |
| `rtl/hdl/`, `rtl/tb/`, `rtl/software/`, `rtl/script/` | VHDL IP, VHDL tests, Zynq application and vectors, Vivado build script |
| `uvm/` | Active UVM environment, test matrix, and reproducible Vivado/XSim launcher |
| `driver/` | Linux driver, C test application, board script, and bitstream |
| `data/` | Sample input and analysis files; generated tensor data is omitted from Git |
| `docs/` | Detailed project, RTL, verification, and driver documentation |

## Reproducing the UVM regression

The verified path uses **Vivado 2025.2 and XSim**. Start Vivado without an open project and run:

```tcl
source <repository-path>/uvm/scripts/run_fresh.tcl
```

The launcher creates a local project from the current `rtl/hdl/` and `uvm/` sources. It runs the three `extended` cases in `uvm/scripts/tests.tsv`: randomized input with partial tiles, randomized input/output stalls, and reset during computation. The separate `numeric_range` row is diagnostic and is not part of that regression. See [the UVM README](uvm/README.md) for the testbench layout and result files.

On **15 October 2026**, a fresh Vivado/XSim run from this repository passed all three regular tests: 3,584 checked outputs in `random_input_combined`, 3,072 in `random_stalls_combined`, and the reset checks in `reset_compute`. Functional coverage databases were generated and merged. Local build and result directories are ignored by Git; rerun the launcher to produce your own evidence.

## Other entry points

- `esl/final_app.py` is the Whisper software/virtual-platform entry point. It uses Python dependencies including PyTorch, Transformers, NumPy, and audio libraries, plus the project's compiled C++/SystemC components. Its configuration switches near the top control audio input, replacement layers, comparisons, and matrix exports.
- The root `Makefile` contains convenience targets for the ESL model (`make app`) and a GHDL test using real Whisper data (`make head`). These targets predate the current folder reorganization and have not been revalidated in this checkout; inspect the source paths and data-export settings before using them.
- `rtl/script/build_project.tcl` targets the Zybo Z7-10 part and performs synthesis, implementation, reporting, and IP packaging in Vivado. It was not rerun as part of the UVM regression above.
- `driver/driver/Makefile` and `driver/app/test/Makefile` build the Linux kernel module and C test application on a configured target system. The board path was not rerun as part of the UVM regression above.

## Documentation and scope

The detailed documents are in `docs/`:

- [Project and ESL documentation](docs/project_documentation.pdf): algorithm, SystemC/TLM platform, and design flow.
- [RTL documentation](docs/FA_RTL_dokumentacija.pdf): VHDL architecture and implementation.
- [UVM verification documentation](docs/Verifikacija_dokumentacija.pdf): verification environment and tests.
- [Driver documentation](docs/Drajveri_dokumentacija.pdf): Zynq software and Linux driver.

The [documentation index](docs/README.md) links to the same files. This is academic engineering work. The test result stated above is for RTL simulation; it is not a claim that the full Whisper model runs on the FPGA or that the Linux board flow has been reproduced on every system.
