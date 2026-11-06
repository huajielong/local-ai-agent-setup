#!/usr/bin/env python3
"""Estimate a GGUF model's KV-cache cost per token and suggest a context size.

Reads only the GGUF metadata block (no weights), prints the KV table for the
usual context ladder, and — when given the free VRAM measured with the model
loaded — suggests the largest rung that still leaves headroom.

Standard library only. Read-only; it never writes to the model file.

    python gguf-kv-budget.py model.gguf
    python gguf-kv-budget.py model.gguf --kv q8_0 --free-gb 2.2 --baseline 32768
"""

import argparse
import struct
import sys

# bytes per element for the KV cache dtypes llama.cpp accepts
DTYPE_BYTES = {"f32": 4.0, "f16": 2.0, "bf16": 2.0, "q8_0": 1.0625, "q4_0": 0.5625}

_SCALAR = {0: "B", 1: "b", 2: "H", 3: "h", 4: "I", 5: "i", 6: "f", 7: "?", 10: "Q", 11: "q", 12: "d"}
_LADDER = [2048, 4096, 8192, 16384, 32768, 65536, 98304, 131072, 196608, 262144]


class Reader:
    def __init__(self, fh):
        self.fh = fh

    def read(self, fmt):
        size = struct.calcsize("<" + fmt)
        data = self.fh.read(size)
        if len(data) != size:
            raise ValueError("truncated GGUF header")
        return struct.unpack("<" + fmt, data)[0]

    def string(self):
        n = self.read("Q")
        return self.fh.read(n).decode("utf-8", "replace")

    def value(self, vtype):
        if vtype == 8:
            return self.string()
        if vtype == 9:
            etype = self.read("I")
            count = self.read("Q")
            return [self.value(etype) for _ in range(count)]
        if vtype not in _SCALAR:
            raise ValueError("unknown GGUF value type %d" % vtype)
        return self.read(_SCALAR[vtype])


def read_metadata(path):
    with open(path, "rb") as fh:
        if fh.read(4) != b"GGUF":
            raise ValueError("not a GGUF file: %s" % path)
        version = struct.unpack("<I", fh.read(4))[0]
        if version < 2:
            raise ValueError("GGUF v%d is not supported; re-export the model" % version)
        r = Reader(fh)
        r.read("Q")  # tensor count
        n_kv = r.read("Q")
        meta = {}
        for _ in range(n_kv):
            key = r.string()
            vtype = r.read("I")
            value = r.value(vtype)
            if not isinstance(value, list):
                meta[key] = value
        return meta


def pick(meta, suffix):
    for key, value in meta.items():
        if key.endswith(suffix):
            return value
    return None


def fmt_gb(nbytes):
    return nbytes / 1e9


def main():
    ap = argparse.ArgumentParser(description="Estimate GGUF KV-cache cost and suggest a context size")
    ap.add_argument("model", help="path to the .gguf file")
    ap.add_argument("--kv", default="q8_0", choices=sorted(DTYPE_BYTES), help="KV cache dtype (default q8_0)")
    ap.add_argument("--kv-v", default=None, choices=sorted(DTYPE_BYTES), help="V cache dtype if it differs from K")
    ap.add_argument("--free-gb", type=float, default=None, help="free VRAM in GB with the model loaded at --baseline")
    ap.add_argument("--baseline", type=int, default=32768, help="context used when free VRAM was measured (default 32768)")
    ap.add_argument("--headroom", type=float, default=0.2, help="fraction of free VRAM to keep unused (default 0.2)")
    args = ap.parse_args()

    try:
        meta = read_metadata(args.model)
    except (OSError, ValueError) as exc:
        sys.exit("error: %s" % exc)

    layers = pick(meta, ".block_count")
    kv_heads = pick(meta, ".attention.head_count_kv")
    key_len = pick(meta, ".attention.key_length")
    val_len = pick(meta, ".attention.value_length")
    native = pick(meta, ".context_length")
    embed = pick(meta, ".embedding_length")
    heads = pick(meta, ".attention.head_count")

    if not layers or not kv_heads:
        sys.exit("error: this GGUF does not expose block_count / head_count_kv; compute by hand (see §2)")

    if not key_len:
        if not (embed and heads):
            sys.exit("error: no key_length and no embedding_length/head_count; compute by hand (see §2)")
        key_len = embed // heads
    if not val_len:
        val_len = key_len

    b_k = DTYPE_BYTES[args.kv]
    b_v = DTYPE_BYTES[args.kv_v or args.kv]
    per_token = layers * kv_heads * key_len * (b_k + b_v)

    print("model:        %s" % args.model)
    print("native ctx:   %s" % (native if native else "unknown"))
    print("layers:       %s" % layers)
    print("kv heads:     %s" % kv_heads)
    print("key/value:    %d / %d" % (key_len, val_len))
    print("kv dtype:     K=%s V=%s" % (args.kv, args.kv_v or args.kv))
    print("kv per token: %.1f KB" % (per_token / 1024.0))
    print()
    print("%-10s %10s" % ("context", "kv cache"))
    for rung in _LADDER:
        if native and rung > native:
            break
        print("%-10d %8.2f GB" % (rung, fmt_gb(rung * per_token)))

    if args.free_gb is None:
        print()
        print("Pass --free-gb (measured at --baseline, e.g. %d) to get a suggested context." % args.baseline)
        return

    usable = args.free_gb * 1e9 * (1.0 - args.headroom)
    extra = int(usable // per_token)
    ceiling = native if native else max(_LADDER)
    suggestion = min(args.baseline + extra, ceiling)
    rung = max([r for r in _LADDER if r <= suggestion] or [_LADDER[0]])

    print()
    print("free VRAM:    %.2f GB (keeping %.0f%% unused)" % (args.free_gb, args.headroom * 100))
    print("can add:      ~%d tokens beyond %d" % (extra, args.baseline))
    print("suggested:    %d" % rung)
    if extra < 4096:
        print("note:         too little room to grow; raise --n-cpu-moe instead -")
        print("              each extra MoE layer on CPU frees roughly main_size / block_count (0.3-0.8GB).")
    if rung < 131072:
        print("warning:      below 128K Claude Code still clamps auto-compact to 100000,")
        print("              so plan on manual /compact at ~50-60% of the context.")


if __name__ == "__main__":
    main()
