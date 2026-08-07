import os
import numpy as np

FRAC_IN  = 18
FRAC_OUT = 34
IN_MIN, IN_MAX = -(1 << 23), (1 << 23) - 1
IN_LIMIT = (1 << 23) / (1 << FRAC_IN)

HEAD_DIM = 64
B  = 32
BC = 64


def to_q6_18(x):
    q = np.rint(np.asarray(x, dtype=np.float64) * (1 << FRAC_IN))
    return np.clip(q, IN_MIN, IN_MAX).astype(np.int64)


def to_words(q):
    return (np.asarray(q, dtype=np.int64) & 0xFFFFFF).astype(np.uint32)


def from_q14_34(w):
    return np.asarray(w, dtype=np.int64).astype(np.float64) / (1 << FRAC_OUT)


def check_range(name, x):
    m = float(np.abs(x).max())
    ok = m < IN_LIMIT
    print(f"  {name:2s} |max| = {m:8.4f}   opseg +-{IN_LIMIT:.0f}   "
          f"{'OK' if ok else 'SATURACIJA'}")
    return m, ok


def qi_starts(rows, qi_blocks=None):
    starts = list(range(0, rows, B))
    if qi_blocks is None:
        return starts
    return [starts[i] for i in qi_blocks]


def stream_length(rows, heads, qi_blocks=None):
    kv = sum(2 * min(BC, rows - j) for j in range(0, rows, BC))
    n = 0
    for qi in qi_starts(rows, qi_blocks):
        br = min(B, rows - qi)
        n += heads * (br + kv) * HEAD_DIM
    return n


def output_length(rows, heads, qi_blocks=None):
    return sum(min(B, rows - qi) * HEAD_DIM * heads
               for qi in qi_starts(rows, qi_blocks))


def write_stream(path, Q, K, V, heads=8, qi_blocks=None):
    rows, cols = Q.shape
    assert cols >= heads * HEAD_DIM, f"cols={cols} < heads*64={heads * HEAD_DIM}"

    Qw = to_words(to_q6_18(Q))
    Kw = to_words(to_q6_18(K))
    Vw = to_words(to_q6_18(V))

    n = 0
    with open(path, "wb") as f:
        for qi in qi_starts(rows, qi_blocks):
            br = min(B, rows - qi)
            for h in range(heads):
                s = slice(h * HEAD_DIM, (h + 1) * HEAD_DIM)
                f.write(np.ascontiguousarray(Qw[qi:qi + br, s]).tobytes())
                n += br * HEAD_DIM
                for j in range(0, rows, BC):
                    bc = min(BC, rows - j)
                    f.write(np.ascontiguousarray(Kw[j:j + bc, s]).tobytes())
                    f.write(np.ascontiguousarray(Vw[j:j + bc, s]).tobytes())
                    n += 2 * bc * HEAD_DIM
    return n


def unpack_output(w, rows, cols, heads=8, qi_blocks=None):
    O = np.full((rows, cols), np.nan, dtype=np.float64)
    idx = 0
    for qi in qi_starts(rows, qi_blocks):
        br = min(B, rows - qi)
        for h in range(heads):
            blk = np.asarray(w[idx:idx + br * HEAD_DIM]).reshape(br, HEAD_DIM)
            idx += br * HEAD_DIM
            O[qi:qi + br, h * HEAD_DIM:(h + 1) * HEAD_DIM] = from_q14_34(blk)
    return O


def read_output(path, rows, cols, heads=8, qi_blocks=None):
    w = np.fromfile(path, dtype="<i8")
    need = output_length(rows, heads, qi_blocks)
    if w.size != need:
        raise ValueError(f"{path}: ocekivano {need} reci, procitano {w.size}")
    return unpack_output(w, rows, cols, heads, qi_blocks)


def reference_attention(Q, K, V, heads=8):
    rows, cols = Q.shape
    hd = cols // heads
    out = np.empty((rows, cols), dtype=np.float64)
    for h in range(heads):
        s = slice(h * hd, (h + 1) * hd)
        A = Q[:, s] @ K[:, s].T
        A -= A.max(axis=1, keepdims=True)
        P = np.exp(A)
        P /= P.sum(axis=1, keepdims=True)
        out[:, s] = P @ V[:, s]
    return out


def compare(got, ref, label="RTL"):
    g, r = np.asarray(got, float), np.asarray(ref, float)
    m = ~np.isnan(g)
    if not m.any():
        print(f"[{label}] nema poredjenih elemenata")
        return None
    d = np.abs(g[m] - r[m])
    print(f"[{label}] n={m.sum()}  max_abs={d.max():.3e}  "
          f"rms={np.sqrt((d ** 2).mean()):.3e}  rel={d.max() / np.abs(r[m]).max():.3e}")
    return d.max()


def _main():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--dir", default="matrice")
    p.add_argument("--heads", type=int, default=8)
    p.add_argument("--qi", type=int, nargs="*", default=None)
    p.add_argument("--out", default=None)
    p.add_argument("--ref", default=None)
    p.add_argument("--check", default=None)
    a = p.parse_args()

    Q = np.loadtxt(os.path.join(a.dir, "multihead_ulaz_Q.txt"))
    K = np.loadtxt(os.path.join(a.dir, "multihead_ulaz_K.txt"))
    V = np.loadtxt(os.path.join(a.dir, "multihead_ulaz_V.txt"))
    rows, cols = Q.shape
    print(f"oblik {Q.shape}, glava={a.heads}")
    for n, x in (("Q", Q), ("K", K), ("V", V)):
        check_range(n, x)

    ref = None
    if a.ref or a.check:
        ref = reference_attention(Q, K, V, a.heads)
    if a.ref:
        np.savetxt(a.ref, ref, fmt="%.8f")
        print(f"referenca -> {a.ref}")

    if a.out:
        n_in = stream_length(rows, a.heads, a.qi)
        n_out = output_length(rows, a.heads, a.qi)
        print(f"ulaz  {n_in:,} reci = {n_in * 4 / 2**20:.1f} MiB")
        print(f"izlaz {n_out:,} reci = {n_out * 8 / 2**20:.1f} MiB")
        assert write_stream(a.out, Q, K, V, a.heads, a.qi) == n_in
        print(f"stream -> {a.out}")

    if a.check:
        got = read_output(a.check, rows, cols, a.heads, a.qi)
        compare(got, ref, "FPGA")


if __name__ == "__main__":
    _main()
