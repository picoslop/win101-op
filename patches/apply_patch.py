#!/usr/bin/env python3
"""Apply a w101patch1 file to a user-supplied Windows 1.01 binary.

The source file is checked against the SHA-256 recorded in the patch before
any byte is written.  The output is checked against the target SHA-256.

    python3 apply_patch.py --patch USER-release.json \
        --in /path/to/USER.EXE --out /path/to/USER.NEW

    python3 apply_patch.py --patch USER-release.json \
        --in /path/to/USER.EXE --check

No Microsoft binaries are included in this release; the input must come from
the user's own Windows 1.01 media.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

MAGIC = "w101patch1"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_patch(path: Path) -> dict:
    try:
        patch = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        raise SystemExit("error: cannot read %s: %s" % (path, exc))
    if patch.get("format") != MAGIC:
        raise SystemExit("error: %s is not a %s patch" % (path, MAGIC))
    for key in ("from", "to", "ops"):
        if key not in patch:
            raise SystemExit("error: %s is missing %r" % (path, key))
    if not isinstance(patch["ops"], list):
        raise SystemExit("error: %s has a bad op list" % path)
    return patch


def apply_ops(src: bytes, ops: list) -> bytes:
    out = bytearray()
    for i, op in enumerate(ops):
        if not isinstance(op, list) or not op:
            raise SystemExit("error: bad op %d" % i)
        if op[0] == "C":
            if len(op) != 3:
                raise SystemExit("error: bad copy op %d" % i)
            _, off, length = op
            if not isinstance(off, int) or not isinstance(length, int):
                raise SystemExit("error: bad copy op %d" % i)
            if off < 0 or length < 0 or off > len(src) - length:
                raise SystemExit("error: copy op %d out of range" % i)
            out += src[off:off + length]
        elif op[0] == "L":
            if len(op) != 2 or not isinstance(op[1], str):
                raise SystemExit("error: bad literal op %d" % i)
            try:
                out += base64.b64decode(op[1], validate=True)
            except Exception as exc:
                raise SystemExit("error: literal op %d: %s" % (i, exc))
        else:
            raise SystemExit("error: unknown op %d" % i)
    return bytes(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--patch", required=True)
    ap.add_argument("--in", dest="infile", required=True)
    ap.add_argument("--out", dest="outfile")
    ap.add_argument("--check", action="store_true",
                    help="verify only; do not write the output")
    args = ap.parse_args()

    patch = load_patch(Path(args.patch))
    src = Path(args.infile).read_bytes()

    want = patch["from"].get("sha256", "")
    got = sha256(src)
    if got != want:
        print("error: source is not the expected file", file=sys.stderr)
        print("  expected %s  %s bytes" % (want, patch["from"].get("size")),
              file=sys.stderr)
        print("  got      %s  %d bytes" % (got, len(src)), file=sys.stderr)
        return 1

    dst = apply_ops(src, patch["ops"])
    target = patch["to"].get("sha256", "")
    if sha256(dst) != target:
        print("error: patched output does not match the target hash",
              file=sys.stderr)
        return 1
    if patch["to"].get("size") not in (None, len(dst)):
        print("error: patched output has the wrong size", file=sys.stderr)
        return 1

    if args.check:
        print("%s: source OK; patch would produce %s (%s)" % (
            Path(args.patch).name, patch["to"].get("name", "output"),
            target))
        return 0
    if not args.outfile:
        ap.error("--out is required unless --check is used")

    out = Path(args.outfile)
    out.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=out.name + ".", dir=str(out.parent))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(dst)
        os.replace(tmp, out)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    print("%s -> %s (%d bytes, sha256 %s)" % (
        Path(args.infile).name, out, len(dst), target))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
