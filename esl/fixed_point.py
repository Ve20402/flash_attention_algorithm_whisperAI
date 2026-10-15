import numpy as np


FRAC_IN = 18
FRAC_OUT = 34
IN_MIN = -(1 << 23)
IN_MAX = (1 << 23) - 1
HEAD_DIM = 64
B = 32


def quantize(values):
    scaled = np.asarray(values, dtype=np.float64) * (1 << FRAC_IN)
    rounded = np.where(scaled >= 0, np.floor(scaled + 0.5), np.ceil(scaled - 0.5))
    return np.clip(rounded, IN_MIN, IN_MAX).astype(np.int64)


def axi_words(values):
    return (quantize(values) & 0xFFFFFF).astype("<u4")


def write_compact_qkv(path, q, k, v):
    with open(path, "wb") as output:
        for matrix in (q, k, v):
            output.write(np.ascontiguousarray(axi_words(matrix)).tobytes())


def read_output(path, rows, columns, heads=8):
    raw = np.fromfile(path, dtype="<i8")
    if raw.size != rows * heads * HEAD_DIM:
        raise ValueError("Wrong number of output words")

    output = np.empty((rows, columns), dtype=np.float64)
    position = 0
    for q_start in range(0, rows, B):
        q_rows = min(B, rows - q_start)
        for head in range(heads):
            count = q_rows * HEAD_DIM
            tile = raw[position:position + count].reshape(q_rows, HEAD_DIM)
            start = head * HEAD_DIM
            output[q_start:q_start + q_rows, start:start + HEAD_DIM] = (
                tile.astype(np.float64) / (1 << FRAC_OUT)
            )
            position += count
    return output
