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
    return (np.asarray(q, dtype=np.int64) & 0xFFFFFF).astype("<u4")


def from_q14_34(w):
    return np.asarray(w, dtype=np.int64).astype(np.float64) / (1 << FRAC_OUT)


def check_range(name, x):
    m = float(np.abs(x).max())
    ok = m < IN_LIMIT
    print(f"  {name:2s} |max| = {m:8.4f}   opseg +-{IN_LIMIT:.0f}   "
          f"{'OK' if ok else 'SATURACIJA'}")
    return m, ok


def qi_starts(rows):
    return range(0, rows, B)


def stream_length(query_rows, kv_rows, heads):
    kv = sum(2 * min(BC, kv_rows - j) for j in range(0, kv_rows, BC))
    n = 0
    for qi in qi_starts(query_rows):
        br = min(B, query_rows - qi)
        n += heads * (br + kv) * HEAD_DIM
    return n


def output_length(rows, heads):
    return sum(min(B, rows - qi) * HEAD_DIM * heads
               for qi in qi_starts(rows))


def write_stream(path, Q, K, V, heads=8):
    query_rows, cols = Q.shape
    kv_rows = K.shape[0]
    if K.shape != V.shape:
        raise ValueError(f"K i V moraju imati isti oblik: {K.shape} i {V.shape}")
    if K.shape[1] != cols:
        raise ValueError(f"Q i K/V moraju imati isti broj kolona: {cols} i {K.shape[1]}")
    assert cols >= heads * HEAD_DIM, f"cols={cols} < heads*64={heads * HEAD_DIM}"

    Qw = to_words(to_q6_18(Q))
    Kw = to_words(to_q6_18(K))
    Vw = to_words(to_q6_18(V))

    n = 0
    with open(path, "wb") as f:
        for qi in qi_starts(query_rows):
            br = min(B, query_rows - qi)
            for h in range(heads):
                s = slice(h * HEAD_DIM, (h + 1) * HEAD_DIM)
                f.write(np.ascontiguousarray(Qw[qi:qi + br, s]).tobytes())
                n += br * HEAD_DIM
                for j in range(0, kv_rows, BC):
                    bc = min(BC, kv_rows - j)
                    f.write(np.ascontiguousarray(Kw[j:j + bc, s]).tobytes())
                    f.write(np.ascontiguousarray(Vw[j:j + bc, s]).tobytes())
                    n += 2 * bc * HEAD_DIM
    return n


def write_output_stream_text(path, output, heads=8):
    rows, cols = output.shape
    assert cols >= heads * HEAD_DIM, f"cols={cols} < heads*64={heads * HEAD_DIM}"

    count = 0
    with open(path, "w", encoding="ascii") as stream_file:
        for qi in qi_starts(rows):
            br = min(B, rows - qi)
            for head in range(heads):
                start = head * HEAD_DIM
                stop = start + HEAD_DIM
                block = np.asarray(output[qi:qi + br, start:stop], dtype=np.float64)
                np.savetxt(stream_file, block.reshape(-1), fmt="%.10e")
                count += block.size
    return count


def unpack_output(w, rows, cols, heads=8):
    O = np.empty((rows, cols), dtype=np.float64)
    idx = 0
    for qi in qi_starts(rows):
        br = min(B, rows - qi)
        for h in range(heads):
            blk = np.asarray(w[idx:idx + br * HEAD_DIM]).reshape(br, HEAD_DIM)
            idx += br * HEAD_DIM
            O[qi:qi + br, h * HEAD_DIM:(h + 1) * HEAD_DIM] = from_q14_34(blk)
    return O


def read_output(path, rows, cols, heads=8):
    w = np.fromfile(path, dtype="<i8")
    need = output_length(rows, heads)
    if w.size != need:
        raise ValueError(f"{path}: ocekivano {need} reci, procitano {w.size}")
    return unpack_output(w, rows, cols, heads)


def reference_attention(Q, K, V, heads=8):
    query_rows, cols = Q.shape
    if K.shape != V.shape:
        raise ValueError(f"K i V moraju imati isti oblik: {K.shape} i {V.shape}")
    if K.shape[1] != cols:
        raise ValueError(f"Q i K/V moraju imati isti broj kolona: {cols} i {K.shape[1]}")
    hd = cols // heads
    out = np.empty((query_rows, cols), dtype=np.float64)
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
    p.add_argument("--out", default=None)
    p.add_argument("--ref", default=None)
    p.add_argument("--check", default=None)
    p.add_argument("--golden-in", default=None)
    p.add_argument("--golden-out", default=None)
    p.add_argument("--query-rows", type=int, default=None)
    p.add_argument("--head-index", type=int, default=None)
    a = p.parse_args()

    Q = np.loadtxt(os.path.join(a.dir, "multihead_ulaz_Q.txt"))
    K = np.loadtxt(os.path.join(a.dir, "multihead_ulaz_K.txt"))
    V = np.loadtxt(os.path.join(a.dir, "multihead_ulaz_V.txt"))

    if Q.shape != K.shape or K.shape != V.shape:
        raise ValueError(f"Q/K/V oblici se razlikuju: {Q.shape}, {K.shape}, {V.shape}")

    source_rows, source_cols = Q.shape
    query_rows = source_rows if a.query_rows is None else a.query_rows
    if query_rows <= 0 or query_rows > source_rows:
        p.error(f"--query-rows mora biti izmedju 1 i {source_rows}")

    # Ogranicavamo samo broj Q redova. K i V ostaju kompletni, tako da
    # softmax koristi isti domen kao originalni Whisper attention.
    Q = Q[:query_rows]

    if a.head_index is not None:
        if a.head_index < 0 or a.head_index >= a.heads:
            p.error(f"--head-index mora biti izmedju 0 i {a.heads - 1}")
        start = a.head_index * HEAD_DIM
        stop = start + HEAD_DIM
        Q = Q[:, start:stop]
        K = K[:, start:stop]
        V = V[:, start:stop]
        print(f"koristi se stvarna Whisper glava {a.head_index}")
        a.heads = 1

    rows, cols = Q.shape
    kv_rows = K.shape[0]
    print(f"Q oblik {Q.shape}, K/V oblik {K.shape}, glava={a.heads}")
    for n, x in (("Q", Q), ("K", K), ("V", V)):
        check_range(n, x)

    ref = None
    if a.ref or a.check:
        ref = reference_attention(Q, K, V, a.heads)
    if a.ref:
        np.savetxt(a.ref, ref, fmt="%.8f")
        print(f"referenca -> {a.ref}")

    if a.out:
        n_in = stream_length(rows, kv_rows, a.heads)
        n_out = output_length(rows, a.heads)
        print(f"ulaz  {n_in:,} reci = {n_in * 4 / 2**20:.1f} MiB")
        print(f"izlaz {n_out:,} reci = {n_out * 8 / 2**20:.1f} MiB")
        assert write_stream(a.out, Q, K, V, a.heads) == n_in
        print(f"stream -> {a.out}")

    if a.golden_in and not a.golden_out:
        p.error("--golden-in zahteva i --golden-out")
    if a.golden_out:
        if a.golden_in:
            golden = np.loadtxt(a.golden_in)
            if golden.shape != (source_rows, source_cols):
                raise ValueError(
                    f"golden: ocekivan puni oblik {(source_rows, source_cols)}, "
                    f"procitan {golden.shape}"
                )
            golden = golden[:query_rows]
            if a.head_index is not None:
                start = a.head_index * HEAD_DIM
                stop = start + HEAD_DIM
                golden = golden[:, start:stop]
            else:
                golden = golden[:, :a.heads * HEAD_DIM]

            calculated = reference_attention(Q, K, V, a.heads)
            difference = np.abs(calculated - golden)
            max_abs = float(difference.max())
            rms = float(np.sqrt(np.mean(difference ** 2)))
            print(f"provera izabranog full-context goldena: "
                  f"max_abs={max_abs:.3e}, rms={rms:.3e}")
            if not np.allclose(calculated, golden, atol=1e-4, rtol=1e-4):
                raise ValueError(
                    "izabrani golden se ne poklapa sa full-context Python attention-om"
                )
        else:
            golden = reference_attention(Q, K, V, a.heads)
        if golden.shape != (rows, cols):
            raise ValueError(
                f"golden: ocekivan oblik {(rows, cols)}, procitan {golden.shape}"
            )
        count = write_output_stream_text(a.golden_out, golden, a.heads)
        assert count == output_length(rows, a.heads)
        print(f"golden stream {count:,} reci -> {a.golden_out}")

    if a.check:
        got = read_output(a.check, rows, cols, a.heads)
        compare(got, ref, "FPGA")


if __name__ == "__main__":
    _main()
