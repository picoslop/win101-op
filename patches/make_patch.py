#!/usr/bin/env python3
"""Create a w101patch1 file from two Windows 1.01 binaries.

The patch is a block-copy/literal stream: it finds 32-byte blocks of the
source inside the target, copies long runs, and stores the remaining bytes
as literals.  It is deliberately simple and dependency-free so a release
user only needs Python 3.

    python3 make_patch.py --from USER.EXE --to USER.NEW --out user.json

The tool verifies the reconstruction before writing the patch.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import sys
from pathlib import Path

BLOCK = 32
MAX_CANDIDATES = 32
MAGIC = "w101patch1"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _block_key(data: bytes, off: int) -> bytes:
    return hashlib.blake2b(data[off:off + BLOCK], digest_size=8).digest()


def make_ops(src: bytes, dst: bytes) -> list[list]:
    """Return [ ['C', source_off, length] | ['L', base64] ]."""
    index: dict[bytes, list[int]] = {}
    for off in range(0, len(src) - BLOCK + 1):
        index.setdefault(_block_key(src, off), []).append(off)

    ops: list[list] = []
    literal = bytearray()

    def flush() -> None:
        if literal:
            ops.append(["L", base64.b64encode(bytes(literal)).decode("ascii")])
            literal.clear()

    pos = 0
    while pos < len(dst):
        best = None  # (source offset, length)
        if pos + BLOCK <= len(dst):
            key = _block_key(dst, pos)
            for cand in index.get(key, [])[:MAX_CANDIDATES]:
                length = BLOCK
                while (pos + length < len(dst) and
                       cand + length < len(src) and
                       dst[pos + length] == src[cand + length]):
                    length += 1
                if best is None or length > best[1]:
                    best = (cand, length)

        if best is not None and best[1] >= BLOCK:
            cand, length = best
            # Extend backwards over bytes that were waiting in the literal.
            back = 0
            while (back < len(literal) and cand > back and
                   dst[pos - back - 1] == src[cand - back - 1]):
                back += 1
            if back:
                del literal[-back:]
                cand -= back
                length += back
                pos -= back
            flush()
            ops.append(["C", cand, length])
            pos += length
        else:
            literal.append(dst[pos])
            pos += 1

    flush()
    return ops


def apply_ops(src: bytes, ops: list[list]) -> bytes:
    out = bytearray()
    for op in ops:
        if op[0] == "C":
            _, off, length = op
            if not (0 <= off <= len(src) - length):
                raise ValueError("copy out of range: %r" % (op,))
            out += src[off:off + length]
        elif op[0] == "L":
            out += base64.b64decode(op[1])
        else:
            raise ValueError("unknown op: %r" % (op,))
    return bytes(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="src", required=True)
    ap.add_argument("--to", dest="dst", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--label", default="")
    args = ap.parse_args()

    src = Path(args.src).read_bytes()
    dst = Path(args.dst).read_bytes()
    ops = make_ops(src, dst)

    rebuilt = apply_ops(src, ops)
    if rebuilt != dst:
        print("error: internal diff verification failed", file=sys.stderr)
        return 1

    patch = {
        "format": MAGIC,
        "label": args.label,
        "block": BLOCK,
        "from": {"name": Path(args.src).name, "size": len(src),
                 "sha256": sha256(src)},
        "to": {"name": Path(args.dst).name, "size": len(dst),
               "sha256": sha256(dst)},
        "ops": ops,
    }
    Path(args.out).write_text(json.dumps(patch, indent=1) + "\n")
    copied = sum(op[2] for op in ops if op[0] == "C")
    literals = sum(len(base64.b64decode(op[1])) for op in ops
                   if op[0] == "L")
    print("%s: %d ops, %d copied, %d literal bytes, %d patch bytes" % (
        Path(args.out).name, len(ops), copied, literals,
        Path(args.out).stat().st_size))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
