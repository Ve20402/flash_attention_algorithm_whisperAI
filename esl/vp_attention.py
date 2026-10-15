import os
import subprocess
import tempfile
import time
from pathlib import Path

import numpy as np

from fixed_point import (
    FRAC_IN,
    HEAD_DIM,
    IN_MAX,
    IN_MIN,
    read_output,
    write_compact_qkv,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class FixedPointVPRunner:

    def __init__(
        self,
        executable=None,
        artifact_dir=None,
        keep_artifacts=False,
    ):
        configured_executable = executable or os.environ.get("FA_VP_EXE")
        self.executable = Path(
            configured_executable or PROJECT_ROOT / "esl" / "simulation_tlm").resolve()
        self.artifact_dir = Path(
            artifact_dir or PROJECT_ROOT / "data" / "vp_runs").resolve()
        self.keep_artifacts = keep_artifacts

    def _run_in_directory(self, directory, q, k, v, heads, layer_index):
        rows, cols = q.shape
        kv_rows = k.shape[0]
        input_path = directory / f"layer_{layer_index}_input.bin"
        output_path = directory / f"layer_{layer_index}_output.bin"

        input_words = q.size + k.size + v.size
        print(
            f"[VP layer {layer_index}] quantization: "
            f"Q={q.shape}, K/V={k.shape}, heads={heads}, "
            f"compact input={input_words * 4 / 2**20:.1f} MiB",
            flush=True,
        )
        started = time.perf_counter()
        write_compact_qkv(input_path, q, k, v)

        command = [
            str(self.executable),
            str(input_path),
            str(output_path),
            str(rows),
            str(kv_rows),
            str(heads),
        ]
        subprocess.run(command, cwd=PROJECT_ROOT, check=True)
        output = read_output(output_path, rows, cols, heads)
        elapsed = time.perf_counter() - started
        print(
            f"[VP layer {layer_index}] complete in {elapsed:.1f}s; "
            f"pre-out_proj={output.shape} Q14.34",
            flush=True,
        )
        return output

    def run(self, q, k, v, heads, layer_index):
        if not self.executable.is_file():
            raise FileNotFoundError(
                f"Fixed-point VP executable not found: {self.executable}. "
                "Pokreni 'make run'."
            )

        q = np.asarray(q, dtype=np.float64)
        k = np.asarray(k, dtype=np.float64)
        v = np.asarray(v, dtype=np.float64)
        if q.ndim != 2 or k.ndim != 2 or v.ndim != 2:
            raise ValueError("VP expects two-dimensional Q, K and V matrices")
        if k.shape != v.shape or q.shape[1] != k.shape[1]:
            raise ValueError(f"Incompatible Q/K/V shapes: {q.shape}, {k.shape}, {v.shape}")
        if q.shape[1] != heads * HEAD_DIM:
            raise ValueError(
                f"embed_dim={q.shape[1]} does not match heads*64={heads * HEAD_DIM}"
            )

        for name, values in (("Q", q), ("K", k), ("V", v)):
            scaled = np.rint(values * (1 << FRAC_IN))
            saturated = np.count_nonzero((scaled < IN_MIN) | (scaled > IN_MAX))
            if saturated:
                raise OverflowError(
                    f"VP layer {layer_index}: {name} has {saturated} values "
                    "outside the RTL Q6.18 range"
                )

        self.artifact_dir.mkdir(parents=True, exist_ok=True)
        if self.keep_artifacts:
            layer_directory = self.artifact_dir / f"layer_{layer_index}"
            layer_directory.mkdir(parents=True, exist_ok=True)
            return self._run_in_directory(
                layer_directory, q, k, v, heads, layer_index
            )

        with tempfile.TemporaryDirectory(
            prefix=f"layer_{layer_index}_", dir=self.artifact_dir
        ) as temporary_directory:
            return self._run_in_directory(
                Path(temporary_directory), q, k, v, heads, layer_index
            )
