#!/usr/bin/env python3
"""Build the proportional System + Fixedsys FONTS.FON and MSDOS.EXE.

Inputs (not included; supply your own originals in fontkit/input/):
    WIN101_FONTS.FON   stock Windows 1.01 FONTS.FON
    WIN30_VGASYS.FON   Windows 3.0 VGA System font (FNT 2.00)
    WIN30_VGAFIX.FON   Windows 3.0 VGA Fixedsys font (FNT 2.00)
    MSDOS.ORI          stock Windows 1.01 MSDOS.EXE

Outputs (fontkit/out/):
    FONTS_30_SYS_FIXEDSYS.FON   replace C:\\WINDOWS\\FONTS.FON
    MSDOS.EXE                   replace C:\\WINDOWS\\MSDOS.EXE

Run from this directory or anywhere; the scripts use paths relative to
fontkit/.
"""
from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE / "tools"
INPUT = HERE / "input"
OUT = HERE / "out"

REQUIRED = {
    "WIN101_FONTS.FON": "853385b91fe7f9460a09c164b9f0e459865057f73759f2503ae3cccd3379acda",
    "WIN30_VGASYS.FON": None,
    "WIN30_VGAFIX.FON": None,
    "MSDOS.ORI": "108f4a5364f41e75846f8d8b69ad90f8e58d0a6d3dc62ded58e9988354df0e50",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args: list[str]) -> None:
    print("+", " ".join(args))
    subprocess.run(args, cwd=HERE, check=True)


def main() -> int:
    missing = [name for name in REQUIRED if not (INPUT / name).exists()]
    if missing:
        print("error: missing input(s): %s" % ", ".join(missing), file=sys.stderr)
        print("       see fontkit/input/README.md", file=sys.stderr)
        return 1
    for name, want in REQUIRED.items():
        if want and sha256(INPUT / name) != want:
            print("error: %s is not the expected stock file" % name,
                  file=sys.stderr)
            return 1
    OUT.mkdir(exist_ok=True)
    run([sys.executable, str(TOOLS / "convert.py"), "--mode", "proportional"])
    run([sys.executable, str(TOOLS / "convert_fixedsys.py")])
    run([sys.executable, str(TOOLS / "patch_msdos_fixedsys.py")])
    print("\nfontkit outputs in", OUT)
    for p in ("FONTS_30_SYS_FIXEDSYS.FON", "MSDOS.EXE"):
        print("  %-32s %s" % (p, sha256(OUT / p)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
