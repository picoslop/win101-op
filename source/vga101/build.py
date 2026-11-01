#!/usr/bin/env python3
"""Build the Windows 1.01 VGA (640x480, 8-colour) display driver.

The driver is the Windows 2.0 DDK EGA colour driver adapted to Windows 1.x
and to the VGA's mode 12h.  It uses only 8086/286 instructions: the source is
assembled with .8086 in BITBLT.ASM (the one module the DDK marks .286p).

This release does not ship the Microsoft tools or SDK libraries.  Supply
MASM.EXE, LINK4.EXE, RC.EXE and RCPP.EXE in a directory and point
VGA101_TOOLS at it; put dosrun (emu2 wrapper) on the path or set DOSRUN.
The build also needs swinlibc.lib and winstub.exe from a Windows 1.01 SDK,
which are not included.  Run from this directory:

    VGA101_TOOLS=/path/to/masm-tools DOSRUN=/path/to/dosrun python3 build.py

It leaves object files in build/ and writes drivers/VGAHIRES.DRV.
"""
from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]                  # release root (source/vga101/..)
SRC = HERE / "src"
BUILD = HERE / "build"
OUT = HERE / "drivers"
TOOLS = Path(os.environ.get("VGA101_TOOLS", HERE / "tools"))
DOSRUN = Path(os.environ.get("DOSRUN", ROOT / "tools" / "dosrun"))

# Modules linked into the display driver.  cursor.asm is assembled twice in
# the DDK (EGA and VGA); here only the VGA instance is needed.
MODULES = [
    "prelude", "drawmod2", "chkstk", "cursors", "control", "dither",
    "robject", "enum", "colorinf", "pixel", "output", "scanlr",
    "polyline", "strblt", "bitblt",
]
VGA_MODULES = [
    ("vga", "vga.obj"),
    ("cursor", "vgacursr.obj"),
]


def run(args: list[str], cwd: Path) -> None:
    print("+", " ".join(str(a) for a in args))
    subprocess.run(args, cwd=cwd, check=True)


def main() -> int:
    if not DOSRUN.exists():
        sys.exit("build.py: %s not found (set DOSRUN=/path/to/tools/dosrun)" % DOSRUN)
    if TOOLS != HERE / "tools":
        local = HERE / "tools"
        local.mkdir(exist_ok=True)
        for tool in ("MASM.EXE", "LINK4.EXE", "RC.EXE", "RCPP.EXE"):
            shutil.copy2(TOOLS / tool, local / tool)
    tools = HERE / "tools"
    for tool in ("MASM.EXE", "LINK4.EXE", "RC.EXE", "RCPP.EXE"):
        if not (tools / tool).exists():
            sys.exit("build.py: missing %s" % (tools / tool))
    for lib in ("swinlibc.lib", "winstub.exe"):
        if not (SRC / lib).exists():
            sys.exit("build.py: missing src/%s (copy it from a Windows 1.01 SDK)"
                     % lib)

    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir()
    # LINK4 and RC need these next to the objects.
    for name in ("vga.def", "vga.lnk", "swinlibc.lib", "winstub.exe",
                 "ega.rc"):
        shutil.copy2(SRC / name, BUILD / name)
    # RC launches RCPP by name; keep it in the build directory so the build
    # does not depend on the caller's DOS PATH.
    shutil.copy2(tools / "RCPP.EXE", BUILD / "RCPP.EXE")
    shutil.copytree(SRC / "res", BUILD / "res")

    # Assemble.  MASM 5.1 gets a DOS path relative to the build directory;
    # the source tree is on the same drive, so no drive letter is needed.
    for mod in MODULES:
        run([str(DOSRUN), "../tools/MASM.EXE", "-z-t-Ml-b63",
             "-I../src", "../src/%s;" % mod], BUILD)

    for mod, obj in VGA_MODULES:
        if mod == "vga":
            run([str(DOSRUN), "../tools/MASM.EXE", "-DVGA", "-z-t-Ml-b63",
                 "-I../src", "../src/vga;"], BUILD)
        else:
            run([str(DOSRUN), "../tools/MASM.EXE", "-DVGA", "-z-t-Ml-b63",
                 "-I../src", "../src/cursor,%s;" % obj], BUILD)

    run([str(DOSRUN), "../tools/LINK4.EXE", "@vga.lnk"], BUILD)

    # Resources: cursors, icons, the OEM bitmap fonts and the system bitmaps.
    run([str(DOSRUN), "../tools/RC.EXE", "-r", "ega.rc", "ega.res"], BUILD)
    run([str(DOSRUN), "../tools/RC.EXE", "ega.res", "vgahires.drv"], BUILD)

    OUT.mkdir(exist_ok=True)
    drv = OUT / "VGAHIRES.DRV"
    shutil.copy2(BUILD / "vgahires.drv", drv)
    # Windows 1 SETUP copies <driver>.GRB/.LGO.  They are one-line pointers
    # to the stock EGA grabber and CGA boot logo, exactly as the stock EGA
    # driver's files are.
    (OUT / "VGAHIRES.GRB").write_bytes(b"egalores.grb\r\n\x1a")
    (OUT / "VGAHIRES.LGO").write_bytes(b"cga.lgo\r\n")

    # MKSETUP.COM is a normal NASM binary; keep it in sync when NASM is
    # available, otherwise leave the prebuilt copy in place.
    nasm = shutil.which("nasm")
    if nasm:
        run([nasm, "-f", "bin", "-o", str(OUT / "MKSETUP.COM"),
             "mksetup.asm"], HERE)
    else:
        print("note: nasm not found; using the prebuilt drivers/MKSETUP.COM")

    data = drv.read_bytes()
    print("\n%s: %d bytes  sha256 %s" % (drv, len(data),
                                         hashlib.sha256(data).hexdigest()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
