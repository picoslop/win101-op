#!/usr/bin/env python3
"""Patch MSDOS.EXE so the file-list painter uses the OEM fixed font.

The Windows 3.x shell uses a separate fixed system font for filenames.  In
Windows 1.01 the equivalent fixed face is the OEM stock object (Fixedsys in
the combined ``SYSFIX.FON`` library).  The line painter at ``_TEXT:0A05``
receives the file-list HDC in ``[bp+0C]``; the patch selects the OEM font
there, once per line, after the function has set up its frame.

The three original pushes (SI, DI, ES) are reproduced by the stub so the
function's epilogue still pops the same frame.  The other caller registers
are saved around the GDI call.

The OEM handle is loaded with `mov bx,handle` + `push bx`, not
`push imm16`: `68` is an 80186 opcode and decodes as JS rel8 on an
8086/8088, corrupting the line painter's stack.

The stock OEM handle in the tested FONTS.FON is 0x045E.  If the font library
changes, run FINFO.EXE and pass the new handle with ``--oem-handle``.

Usage:
    python3 tools/patch_msdos_fixedsys.py
"""
from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
SRC = HERE / "input" / "MSDOS.ORI"
OUT = HERE / "out" / "MSDOS.EXE"

# _TEXT:0A0B is `push si; push di; push es` at the start of the line
# painter's body.  Replacing exactly those three bytes keeps all following
# offsets unchanged; the stub replays the pushes for the function epilogue.
CALL_SITE = 0x0A0B


def make_stub(oem_handle: int) -> bytes:
    return bytes.fromhex(
        "58"                       # pop ax: the call return address
        "56 57 06"                 # push si, di, es: epilogue frame
        "50"                       # push ax: return address back on top
        "53 51 52 56 57 06"        # save bx, cx, dx, si, di, es
        "FF 76 0C"                 # push word [bp+0C]   ; HDC
        # PUSH imm16 (68) is an 80186 instruction.  On an 8086/8088 it
        # decodes as JS rel8 and corrupts the stack, so use the 8086
        # mov bx / push bx pair instead.  BX is already saved above.
        "BB" + struct.pack("<H", oem_handle).hex() + "53" +
        "2E FF 1E 0B 1D"           # call far cs:[1D0B]  ; GDI SelectObject
        "07 5F 5E 5A 59 5B"        # restore es, di, si, dx, cx, bx
        "C3"                       # ret: leaves the si/di/es frame
    )


def patch(data: bytearray, oem_handle: int) -> bytearray:
    ne = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[ne:ne + 2] == b"NE"
    shift = struct.unpack_from("<H", data, ne + 0x32)[0]
    cseg = struct.unpack_from("<H", data, ne + 0x1C)[0]
    st = ne + struct.unpack_from("<H", data, ne + 0x22)[0]
    segs = []
    for i in range(cseg):
        off, ln, fl, mn = struct.unpack_from("<HHHH", data, st + i * 8)
        segs.append([off, ln, fl, mn])

    off, ln, fl, mn = segs[2]
    sector = 1 << shift
    fo = off * sector
    oldend = fo + ln
    rc = struct.unpack_from("<H", data, oldend)[0]
    old_next = oldend + 2 + 8 * rc

    stub = make_stub(oem_handle)
    stub_off = ln
    disp = (stub_off - (CALL_SITE + 3)) & 0xFFFF
    newcode = bytearray(data[fo:oldend])
    assert newcode[CALL_SITE:CALL_SITE + 3] == b"\x56\x57\x06"
    newcode[CALL_SITE:CALL_SITE + 3] = b"\xE8" + struct.pack("<H", disp)
    newcode += stub

    newrel = bytearray(data[oldend:old_next])
    insert_len = len(stub)
    pad = (-insert_len) % sector
    newrel += b"\0" * pad

    new = bytearray()
    new += data[:fo]
    new += newcode
    new += newrel
    new += data[old_next:]
    delta = len(new) - len(data)

    segs[2][1] = len(newcode)
    segs[2][3] = max(segs[2][3], len(newcode))
    for i in range(3, cseg):
        segs[i][0] = ((segs[i][0] << shift) + delta) // sector
    for i, (o, l, f, m) in enumerate(segs):
        struct.pack_into("<HHHH", new, st + i * 8, o, l, f, m)

    # Resource offsets after the inserted bytes.
    res = struct.unpack_from("<H", data, ne + 0x24)[0]
    rp = ne + res
    rshift = struct.unpack_from("<H", data, rp)[0]
    q = rp + 2
    while True:
        tid, cnt = struct.unpack_from("<HH", data, q)
        if tid == 0:
            break
        q += 8
        for _ in range(cnt):
            o2, ln2, fl2, rid, hh, uu = struct.unpack_from("<HHHHHH", data, q)
            if (o2 << rshift) >= old_next:
                struct.pack_into(
                    "<H", new, q, (((o2 << rshift) + delta) >> rshift)
                )
            q += 12
    return new


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=str(SRC))
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--oem-handle", type=lambda s: int(s, 0), default=0x045E)
    args = ap.parse_args()
    data = bytearray(Path(args.source).read_bytes())
    new = patch(data, args.oem_handle)
    Path(args.out).write_bytes(new)
    print("%s %d -> %s %d  sha256 %s" %
          (args.source, len(data), args.out, len(new),
           hashlib.sha256(new).hexdigest()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
