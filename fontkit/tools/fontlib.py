"""Minimal Windows 1.x/3.x FON + FNT reader and Windows 1.00 builder.

The on-disk facts encoded here were checked against:
  * Windows 1.01 FONTS.FON: two FNT 1.00 fonts, System and Terminal;
  * Windows 1.01 HELVA.FON: a proportional FNT 1.00 font;
  * Windows 3.0 VGASYS.FON: one FNT 2.00 proportional System font.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

# FNT 1.00 layout (Windows 1.x)
FNT10_HDR = 0x42
FNT10_FIELDS = 0x75          # char table begins here
FNT10_TABLE_ENTRY = 2

# FNT 2.00 layout (Windows 3.0).  The classic fields are the same; the
# 3.x-only tail is absent, so the 4-byte char table begins at 0x76.
FNT20_TABLE = 0x76
FNT20_TABLE_ENTRY = 4

FIELDS = [
    ("type", 0x42, "H"), ("points", 0x44, "H"), ("vertres", 0x46, "H"),
    ("horizres", 0x48, "H"), ("ascent", 0x4A, "H"),
    ("intlead", 0x4C, "H"), ("extlead", 0x4E, "H"), ("italic", 0x50, "B"),
    ("underline", 0x51, "B"), ("strikeout", 0x52, "B"), ("weight", 0x53, "H"),
    ("charset", 0x55, "B"), ("pixwidth", 0x56, "H"), ("pixheight", 0x58, "H"),
    ("pitchfamily", 0x5A, "B"), ("avgwidth", 0x5B, "H"),
    ("maxwidth", 0x5D, "H"), ("first", 0x5F, "B"), ("last", 0x60, "B"),
    ("default", 0x61, "B"), ("break", 0x62, "B"), ("widthbytes", 0x63, "H"),
    ("device", 0x65, "I"), ("face", 0x69, "I"), ("bitsptr", 0x6D, "I"),
    ("bits", 0x71, "I"),
]


class FonError(RuntimeError):
    pass


@dataclass
class FontHeader:
    version: int
    size: int
    copyright: bytes
    fields: dict[int, int]
    data: bytes

    def __getattr__(self, name: str):
        for field_name, off, _ in FIELDS:
            if field_name == name:
                return self.fields[off]
        raise AttributeError(name)


@dataclass
class Resource:
    type: int
    id: int
    off: int
    length: int
    flags: int
    entry_off: int


@dataclass
class FonFile:
    data: bytearray
    ne: int
    shift: int
    resources: list[Resource] = field(default_factory=list)

    @classmethod
    def open(cls, path: str | Path) -> "FonFile":
        data = bytearray(Path(path).read_bytes())
        if data[:2] != b"MZ":
            raise FonError(f"{path}: not an MZ/NE font library")
        ne = struct.unpack_from("<H", data, 0x3C)[0]
        if data[ne:ne + 2] != b"NE":
            raise FonError(f"{path}: no NE header at 0x{ne:x}")
        nseg, nmod, nresnamelen, segoff, rsrcoff, resnamoff, modoff, impoff = \
            struct.unpack_from("<HHHHHHHH", data, ne + 0x1C)
        rsrc = ne + rsrcoff
        shift = struct.unpack_from("<H", data, rsrc)[0]
        res = []
        o = rsrc + 2
        while True:
            tid, count = struct.unpack_from("<HH", data, o)
            if tid == 0:
                break
            o += 8
            for _ in range(count):
                off, ln, fl, rid, handle, usage = struct.unpack_from(
                    "<HHHHHH", data, o)
                res.append(Resource(tid, rid, off << shift, ln << shift,
                                    fl, o))
                o += 12
        return cls(data, ne, shift, res)

    def find(self, rtype: int, rid: int | None = None) -> Resource:
        for r in self.resources:
            if r.type == rtype and (rid is None or r.id == rid):
                return r
        raise FonError(f"resource type 0x{rtype:x} id {rid} not found")

    def font_resources(self) -> list[Resource]:
        return [r for r in self.resources if r.type == 0x8008]

    def data_of(self, r: Resource) -> bytes:
        return bytes(self.data[r.off:r.off + r.length])

    def patch_resource(self, r: Resource, off: int, length: int) -> None:
        struct.pack_into("<HH", self.data, r.entry_off,
                         off >> self.shift,
                         (length + (1 << self.shift) - 1) >> self.shift)
        r.off, r.length = off, length

    def append(self, payload: bytes) -> int:
        align = 1 << self.shift
        off = (len(self.data) + align - 1) & ~(align - 1)
        self.data += b"\0" * (off - len(self.data))
        self.data += payload
        pad = (-len(self.data)) & (align - 1)
        self.data += b"\0" * pad
        return off


def parse_header(data: bytes) -> FontHeader:
    if len(data) < FNT10_HDR:
        raise FonError("short FNT")
    version = struct.unpack_from("<H", data, 0)[0]
    size = struct.unpack_from("<I", data, 2)[0]
    fields = {}
    for _, off, kind in FIELDS:
        fields[off] = (data[off] if kind == "B"
                       else struct.unpack_from("<" + kind, data, off)[0])
    return FontHeader(version, size, data[6:66], fields, data)


def rle_table_10(data: bytes) -> tuple[list[int], int]:
    """Return (starts, table_end) for a 1.00 proportional font."""
    h = parse_header(data)
    n = h.last - h.first + 1
    starts = [struct.unpack_from("<H", data, FNT10_FIELDS + 2 * i)[0]
              for i in range(n + 1)]
    return starts, FNT10_FIELDS + 2 * (n + 1)


def table_20(data: bytes) -> tuple[list[int], list[int]]:
    h = parse_header(data)
    n = h.last - h.first + 1
    widths, offs = [], []
    for i in range(n):
        w, o = struct.unpack_from("<HH", data, FNT20_TABLE + 4 * i)
        widths.append(w)
        offs.append(o)
    return widths, offs


def convert_30_to_10(data: bytes, mode: str = "fixed",
                     face: bytes = b"System\0", height: int | None = None,
                     points: int | None = None,
                     ascent: int | None = None,
                     intlead: int | None = None,
                     extlead: int | None = None) -> tuple[bytes, dict]:
    """Convert a Windows 3.0 FNT 2.00 font to Windows 1.00.

    mode='fixed'       every glyph gets an 8-pixel cell, dfPixWidth=8
                       (known to render correctly in Windows 1.01)
    mode='proportional' variable cell widths and a 1.00 char table
                       (working 16px System conversion; see FEASIBILITY.md)
                       The resource keeps the real 16px metrics; UI-specific
                       FONTDIRENTRY metrics are applied by convert.py.
    """
    h = parse_header(data)
    if h.version != 0x0200:
        raise FonError("expected FNT 2.00, got 0x%04x" % h.version)
    first, last = h.first, h.last
    n = last - first + 1
    widths, offs = table_20(data)
    src_height = h.pixheight
    height = height or src_height
    row0 = max(0, (src_height - height) // 2)

    if mode == "fixed":
        cell = 8
        strip_w = cell * n
        widthbytes = ((strip_w + 15) // 16) * 2
        bits_off = 0x76
        table = None
    elif mode == "proportional":
        # Windows 1.00's proportional StrBlt computes the glyph bit address
        # as ((offset + 8) >> 3) - 1, with (offset + 8) & 7 as the bit
        # offset.  The +8 and -1 cancel, so the table value is the actual
        # bit offset of the glyph.  Do not insert an 8-bit guard: native
        # 1.00 proportional fonts (e.g. HELVA) put the first glyph at bit 0
        # and the table starts at zero.
        total = sum(widths)
        strip_w = total
        widthbytes = ((strip_w + 15) // 16) * 2
        table = []
        col = 0
        for w in widths:
            table.append(col)
            col += w
        table.append(col)
        bits_off = FNT10_FIELDS + 2 * (n + 1)
        if bits_off & 1:
            bits_off += 1
    else:
        raise ValueError(mode)

    bits = bytearray(widthbytes * height)
    for i, (w, o) in enumerate(zip(widths, offs)):
        span = (w + 7) // 8
        cellx = i * 8 if mode == "fixed" else table[i]
        for row in range(height):
            for p in range(span):
                byte = data[o + p * src_height + row0 + row]
                for bit in range(8):
                    x = p * 8 + bit
                    if x >= w:
                        break
                    if mode == "fixed" and x >= 8:
                        continue
                    if (byte >> (7 - bit)) & 1:
                        X = cellx + x
                        if X < widthbytes * 8:
                            bits[row * widthbytes + (X >> 3)] |= 0x80 >> (X & 7)

    face_off = bits_off + len(bits)
    size = face_off + len(face)
    out = bytearray(size)
    out[:0x75] = data[:0x75]
    struct.pack_into("<H", out, 0, 0x100)
    struct.pack_into("<I", out, 2, size)
    # Classic metrics from the 3.0 font, with 1.00-specific fields.
    if points is not None:
        struct.pack_into("<H", out, 0x44, points)
    if ascent is not None:
        struct.pack_into("<H", out, 0x4A, ascent)
    if intlead is not None:
        struct.pack_into("<H", out, 0x4C, intlead)
    if extlead is not None:
        struct.pack_into("<H", out, 0x4E, extlead)
    struct.pack_into("<H", out, 0x46, 96)
    struct.pack_into("<H", out, 0x56, 8 if mode == "fixed" else 0)
    struct.pack_into("<H", out, 0x58, height)
    if mode == "fixed":
        struct.pack_into("<H", out, 0x5B, 8)   # dfAvgWidth
        struct.pack_into("<H", out, 0x5D, 8)   # dfMaxWidth
    struct.pack_into("<H", out, 0x63, widthbytes)
    struct.pack_into("<I", out, 0x69, face_off)
    struct.pack_into("<I", out, 0x71, bits_off)
    if mode == "proportional":
        for i, v in enumerate(table):
            struct.pack_into("<H", out, FNT10_FIELDS + 2 * i, v)
    out[bits_off:bits_off + len(bits)] = bits
    out[face_off:face_off + len(face)] = face
    info = dict(mode=mode, widthbytes=widthbytes, bits_off=bits_off,
                size=size, total=strip_w, n=n)
    return bytes(out), info


def build_fonts_fon(template_path: str | Path, fnt: bytes,
                    out_path: str | Path, patch_dir: bool = False,
                    dir_metrics: dict[int, int] | None = None) -> None:
    """Put a Windows 1.00 FNT into a 1.01 FONTS.FON-style library.

    The System font is resource 32796.  The stock directory entry is left
    alone by default.  patch_dir=True rebuilds the FONTDIRENTRY correctly
    (dfFace=0, face name at +0x72); dir_metrics overrides individual word
    fields in the entry, e.g. {0x58: 14} for a 14px UI height.
    """
    fon = FonFile.open(template_path)
    src = fon.find(0x8007)
    font = fon.find(0x8008, 32796)
    off = fon.append(fnt)
    fon.patch_resource(font, off, len(fnt))
    if patch_dir:
        # FONTDIRENTRY layout: 0x72-byte metrics header, then the face
        # name.  dfFace is an offset inside a standalone FNT; in the
        # directory it is zero and the name follows at entry+0x72.  Copying
        # the FNT's dfFace offset here makes GDI read a bogus face name and
        # corrupts font selection.
        e = src.off + 4
        fon.data[e:e + 0x69] = fnt[0:0x69]
        struct.pack_into("<I", fon.data, e + 0x69, 0)
        fon.data[e + 0x6D:e + 0x72] = b"\0" * 5
        face = fnt[struct.unpack_from("<I", fnt, 0x69)[0]:]
        face = face.split(b"\0", 1)[0] + b"\0"
        # Keep the existing face slot ("System"); only replace its text if
        # the new face is no longer than the stock one.
        old_face = bytes(fon.data[e + 0x72:e + 0x72 + 0x20]).split(b"\0", 1)[0] + b"\0"
        if len(face) <= len(old_face):
            fon.data[e + 0x72:e + 0x72 + len(old_face)] = face.ljust(len(old_face), b"\0")
        struct.pack_into("<I", fon.data, e + 2, len(fnt))
        if dir_metrics:
            for off, value in dir_metrics.items():
                struct.pack_into("<H", fon.data, e + off, value)
    Path(out_path).write_bytes(fon.data)


def dump(path: str | Path, font_index: int = 0) -> str:
    fon = FonFile.open(path)
    lines = [f"{path}: {len(fon.data)} bytes, {len(fon.resources)} resources"]
    for r in fon.resources:
        lines.append(f"  type 0x{r.type:04x} id {r.id:5d} off 0x{r.off:04x} len {r.length}")
    fonts = fon.font_resources()
    if not fonts:
        return "\n".join(lines)
    data = fon.data_of(fonts[font_index])
    h = parse_header(data)
    lines.append(f"font[{font_index}] version=0x{h.version:04x} size={h.size} "
                 f"face={struct.unpack_from('<I', data, 0x69)[0]}")
    for name, off, kind in FIELDS:
        if name in ("device", "face", "bitsptr", "bits"):
            continue
        lines.append(f"  {name:10s} {h.fields[off]}")
    if h.version == 0x100 and h.pixwidth == 0:
        starts, end = rle_table_10(data)
        lines.append(f"  proportional table starts={starts[:8]}... "
                     f"last={starts[-1]} end=0x{end:x}")
    elif h.version == 0x200:
        w, o = table_20(data)
        lines.append(f"  FNT2.0 char table: {len(w)} chars, first widths={w[:8]}")
    return "\n".join(lines)
