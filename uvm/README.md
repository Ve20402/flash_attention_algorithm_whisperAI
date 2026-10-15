# FlashAttention UVM verification

This is the active UVM environment for the FlashAttention AXI4-Stream RTL. The package in `tb/fa_pkg.sv` includes the master and slave agents under `components/master/` and `components/slave/`. The environment also contains a reference model, scoreboard, functional coverage, a protocol checker, and reset checks.

## Run the regression

Use Vivado 2025.2 with XSim. In a new Vivado Tcl session with no open project, run:

```tcl
source <repository-path>/uvm/scripts/run_fresh.tcl
```

The script creates a local project in `uvm/build/` from `rtl/hdl/` and the UVM sources, then runs `uvm/scripts/run_all.tcl`. Results are written to `uvm/results/run_all_<timestamp>/`. Both directories are ignored by Git. To rerun with an already open project configured for `tb_fa_uvm`, source `uvm/scripts/run_all.tcl` directly.

`scripts/tests.tsv` defines the test configurations. The `extended` suite currently runs three tests:

- `random_input_combined`: eight heads, partial tiles, signed samples, and input gaps.
- `random_stalls_combined`: random input and output stalls, including a directed final-word stall.
- `reset_compute`: reset during computation, then checks that no stale output appears.

`numeric_range` is marked `diagnostic` and is not part of the regular three-test regression. See each run's `summary.txt`, `run_manifest.csv`, and per-test `status.csv` for results.

## Source layout

- `tb/`: interface, UVM package, test, and top-level testbench.
- `components/master/`: AXI input agent (Q/K/V stimulus and input monitor).
- `components/slave/`: AXI output agent (TREADY control and output monitor).
- `components/fa_*.svh`: environment, reference model, scoreboard, coverage, configuration, and protocol/reset checks.
- `scripts/`: regression launcher and test matrix.

The older standalone driver and monitor files are not part of `fa_pkg.sv`; the agent-based implementation is the active version.
