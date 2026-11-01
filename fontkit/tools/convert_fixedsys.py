#!/usr/bin/env python3
"""Convert Windows 3.0 VGAFIX.FON (Fixedsys) to Windows 1.00 resources.

Outputs:
  out/SYSTEM30_FIXEDSYS.FNT      8x15 fixed FNT 1.00
  out/FONTS_30_FIXEDSYS.FON      Fixedsys installed as System (fixed UI)
  out/FONTS_30_SYS_FIXEDSYS.FON  proportional System + Fixedsys Terminal

The combined library keeps the proportional System face for menus/titles and
uses Fixedsys as the OEM fixed stock font.  The Fixedsys FNT and its
FONTDIRENTRY carry the OEM charset (255); without that, GDI's stock-object
matching lets the fixed face win the System slot and the menu turns fixed.

The second library is intended for testing the Windows 1.01 old-app support
module (WINOLDAP) and for an MS-DOS Executive filename-font patch.
"""
from __future__ import annotations

import hashlib
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE / "tools"))
import fontlib


def replace_font(fon: fontlib.FonFile, rid: int, fnt: bytes) -> fontlib.Resource:
    r = fon.find(0x8008, rid)
    off = fon.append(fnt)
    fon.patch_resource(r, off, len(fnt))
    return r


def patch_dir_entry(fon: fontlib.FonFile, entry_off: int, fnt: bytes,
                    face: bytes | None = None) -> None:
    d = fon.data
    d[entry_off:entry_off + 0x69] = fnt[0:0x69]
    struct.pack_into("<I", d, entry_off + 0x69, 0)
    d[entry_off + 0x6D:entry_off + 0x72] = b"\0" * 5
    struct.pack_into("<I", d, entry_off + 2, len(fnt))
    if face is not None:
        old = bytes(d[entry_off + 0x72:entry_off + 0x92]).split(b"\0", 1)[0] + b"\0"
        d[entry_off + 0x72:entry_off + 0x72 + len(old)] = face.ljust(len(old), b"\0")


def main() -> int:
    src = fontlib.FonFile.open(HERE / "input" / "WIN30_VGAFIX.FON")
    font = src.font_resources()[0]
    fnt, info = fontlib.convert_30_to_10(
        src.data_of(font), "fixed", face=b"Fixedsys\0"
    )
    # Keep Fixedsys out of the ANSI System slot.  The OEM face and the
    # converted Terminal resource are both OEM-charset consumers.
    fnt = bytearray(fnt)
    fnt[0x55] = 255
    fnt = bytes(fnt)
    out = HERE / "out"
    out.mkdir(exist_ok=True)
    fnt_path = out / "SYSTEM30_FIXEDSYS.FNT"
    fnt_path.write_bytes(fnt)
    (out / "FIXEDSYS.FNT").write_bytes(fnt)   # 8.3 runtime alias

    # System = Fixedsys (fixed-UI experiment).  This artifact deliberately
    # keeps the ANSI charset so it can occupy the System slot; the OEM
    # charset copy below is the one used for the Terminal/OEM resource.
    fnt_sys = bytearray(fnt)
    fnt_sys[0x55] = 0
    fontlib.build_fonts_fon(HERE / "input" / "WIN101_FONTS.FON", bytes(fnt_sys),
                            out / "FONTS_30_FIXEDSYS.FON",
                            patch_dir=True,
                            dir_metrics={0x58: info["size"] and 15,
                                         0x5B: 8, 0x5D: 8})
    # Proportional System + Fixedsys Terminal.  patch_dir_entry copies the
    # FNT header, including dfCharSet=255, into the Terminal directory entry;
    # the face string stays "Terminal" for the fixed-pitch resource contract.
    base = fontlib.FonFile.open(out / "FONTS_30_PROPORTIONAL.FON")
    replace_font(base, 32798, fnt)
    patch_dir_entry(base, base.find(0x8007).off + 0x7F, fnt, b"Terminal\0")
    (out / "FONTS_30_SYS_FIXEDSYS.FON").write_bytes(base.data)
    (out / "SYSFIX.FON").write_bytes(base.data)   # 8.3 runtime alias

    for p in ("SYSTEM30_FIXEDSYS.FNT", "FIXEDSYS.FNT",
              "FONTS_30_FIXEDSYS.FON",
              "FONTS_30_SYS_FIXEDSYS.FON", "SYSFIX.FON"):
        data = (out / p).read_bytes()
        print("%-32s %6d bytes  sha256 %s" %
              (p, len(data), hashlib.sha256(data).hexdigest()))
    print("conversion", info)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
