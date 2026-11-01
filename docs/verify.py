#!/usr/bin/env python3
"""Verify a locally built win1-op 0.1.0 tree against the release hashes.

    python3 docs/verify.py --build build --fonts fontkit/out \
        --driver drivers/VGAHIRES.DRV

Missing files are reported; use --strict to exit non-zero on a mismatch or a
missing expected file.
"""
from __future__ import annotations

import argparse
import hashlib
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

TARGETS = [
    ("USER.EXE", "125360", "74ccf1196e1fd621a7ffcf1161afdfe0c8eb30906defd6de3f33651c1f8da3cd"),
    ("GDI.EXE", "95758", "47d780da2d5d7712ed5e4fa59c9f4efd7331a18858784e99fcf3a91503d117db"),
    ("MSDOS.EXE", "41936", "b26f5b26f94a5629ac044faa1cdc999e11d657f290e6b4aa926280f0b31e5ad6"),
    ("FONTS.FON", "14704", "e5c32237b777ac675dca5cff5dcd72b321523c6f47b3c2316d24e553c127bcd1"),
    ("VGAHIRES.DRV", "17536", "07df255c2680e6d215c007970a32c1a4b5ce047eefc05aa0ba9ce872abc13653"),
]

STOCK = [
    ("USER.EXE", "122400", "bcdf488987cc4633bd3d246f6327df3239c03bec5bc9ffba478e23ab1f5eb237"),
    ("GDI.EXE", "94254", "8af20331a9290c43bd4a32419dbfc236a5df5e41e46ca20a6f2cdd881326a28f"),
    ("MSDOS.EXE", "41904", "108f4a5364f41e75846f8d8b69ad90f8e58d0a6d3dc62ded58e9988354df0e50"),
    ("FONTS.FON", "7472", "853385b91fe7f9460a09c164b9f0e459865057f73759f2503ae3cccd3379acda"),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def driver_payload_sha256(path: Path) -> str:
    """Hash a VGA NE driver ignoring the linker-written NE header CRC."""
    data = bytearray(path.read_bytes())
    if len(data) >= 0x40:
        ne = struct.unpack_from("<I", data, 0x3C)[0]
        if 0 <= ne <= len(data) - 0x0C and data[ne:ne + 2] == b"NE":
            data[ne + 0x08:ne + 0x0C] = b"\0" * 4
    return hashlib.sha256(data).hexdigest()


VGA_PAYLOAD_SHA256 = "4d244e87bfe4c350102718092cb88c6f34e8d864b5ab6d417d3193bf292b9077"


def check(label: str, path: Path, size: str, digest: str) -> bool:
    if not path.exists():
        print("MISSING  %-14s %s" % (label, path))
        return False
    data = path.read_bytes()
    got = sha256(path)
    if label == "VGAHIRES.DRV":
        # LINK4/RC write the NE header CRC; it differs between builds even
        # when every code/data byte is identical.
        ok = (driver_payload_sha256(path) == VGA_PAYLOAD_SHA256 and
              len(data) == int(size))
        print("%s  %-14s %6d bytes  %s (NE CRC ignored)" % (
            "OK      " if ok else "MISMATCH", label, len(data), got))
    else:
        ok = (got == digest and (size == "-" or len(data) == int(size)))
        print("%s  %-14s %6d bytes  %s" % (
            "OK      " if ok else "MISMATCH", label, len(data), got))
    if not ok:
        print("         expected %s bytes  %s" % (size, digest))
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=str(ROOT / "build"),
                    help="directory with patched USER/GDI/MSDOS.EXE")
    ap.add_argument("--fonts", default=str(ROOT / "fontkit" / "out"),
                    help="fontkit output directory")
    ap.add_argument("--driver", default=str(ROOT / "drivers" / "VGAHIRES.DRV"))
    ap.add_argument("--stock", help="optional directory with the original files")
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()

    build = Path(args.build)
    fonts = Path(args.fonts)
    print("== release outputs ==")
    results = [
        check("USER.EXE", build / "USER.EXE", *TARGETS[0][1:]),
        check("GDI.EXE", build / "GDI.EXE", *TARGETS[1][1:]),
        check("MSDOS.EXE", build / "MSDOS.EXE", *TARGETS[2][1:]),
        check("FONTS.FON", fonts / "FONTS_30_SYS_FIXEDSYS.FON", *TARGETS[3][1:]),
        check("VGAHIRES.DRV", Path(args.driver), *TARGETS[4][1:]),
    ]

    if args.stock:
        print("\n== original inputs ==")
        stock = Path(args.stock)
        for name, size, digest in STOCK:
            results.append(check(name, stock / name, size, digest))

    if args.strict and not all(results):
        print("\nFAILED: one or more files are missing or differ", file=sys.stderr)
        return 1
    print("\nall checks passed" if all(results) else
          "\nnote: missing files are expected before building")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
