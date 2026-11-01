#!/usr/bin/env python3
"""Extract the Windows 1.01 and Windows 3.0 files win1-op needs.

WinWorldPC distributes these products as ZIP archives of raw floppy images
(or as ZIPs of extracted files).  Point this script at the ZIPs; it reads
FAT12/FAT16 floppy images directly, so no 7-Zip, DOSBox or mount step is
needed.

    python3 tools/extract_winworld.py Windows101.zip Windows30.zip

It writes two separate destinations so the products never share a directory:

    originals/win101/   USER.EXE, GDI.EXE, MSDOS.EXE, FONTS.FON, KERNEL.EXE
    originals/win30/    VGASYS.FON, VGAFIX.FON

The Windows 1.01 setup disks carry ``HIFONTS.FON``; SETUP installs that file
as ``FONTS.FON``, so it is accepted under the same output name.  Images are
classified as Windows 1.01 or Windows 3.0 before any target is written, so a
Windows 3.0 disk's USER.EXE/GDI.EXE cannot land in the Windows 1.01 tree.

Use ``--fontkit-dir fontkit/input`` to also write the font kit's expected
names (``WIN101_FONTS.FON``, ``MSDOS.ORI``, ``WIN30_VGASYS.FON``,
``WIN30_VGAFIX.FON``).  That directory must be outside ``--out`` so the two
destinations cannot overlap.

Only ZIP archives are required.  A ``.7z`` member is accepted when a ``7z``
command is available, but the WinWorld ZIP downloads do not need it.

This script is dependency-free (Python 3.8+, standard library).
"""
from __future__ import annotations

import argparse
import hashlib
import io
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

SECTOR = 512
ATTR_VOLUME = 0x08
ATTR_DIR = 0x10
ATTR_LFN = 0x0F
IMG_EXTS = {".img", ".ima", ".dsk", ".raw", ".flp", ".vfd"}

# Stock retail Windows 1.01 hashes.  The patcher requires these exact files.
STOCK = {
    "USER.EXE": "bcdf488987cc4633bd3d246f6327df3239c03bec5bc9ffba478e23ab1f5eb237",
    "GDI.EXE": "8af20331a9290c43bd4a32419dbfc236a5df5e41e46ca20a6f2cdd881326a28f",
    "MSDOS.EXE": "108f4a5364f41e75846f8d8b69ad90f8e58d0a6d3dc62ded58e9988354df0e50",
    "FONTS.FON": "853385b91fe7f9460a09c164b9f0e459865057f73759f2503ae3cccd3379acda",
    "KERNEL.EXE": "36dc24686fc6f3c61d2521f3406bb2fdfd0438abdb220055899f2dd82f9e4375",
}

# source 8.3 name -> (product directory, output name)
TARGETS = {
    "USER.EXE": ("win101", "USER.EXE"),
    "GDI.EXE": ("win101", "GDI.EXE"),
    "MSDOS.EXE": ("win101", "MSDOS.EXE"),
    "FONTS.FON": ("win101", "FONTS.FON"),
    "HIFONTS.FON": ("win101", "FONTS.FON"),
    "KERNEL.EXE": ("win101", "KERNEL.EXE"),
    "VGASYS.FON": ("win30", "VGASYS.FON"),
    "VGAFIX.FON": ("win30", "VGAFIX.FON"),
}
REQUIRED = ["USER.EXE", "GDI.EXE", "MSDOS.EXE", "FONTS.FON",
            "VGASYS.FON", "VGAFIX.FON"]


def u16(d: bytes, off: int) -> int:
    return struct.unpack_from("<H", d, off)[0]


def u32(d: bytes, off: int) -> int:
    return struct.unpack_from("<I", d, off)[0]


SZDD_SIG = b"SZDD\x88\xf0\x27\x33"


def decompress_szdd(data: bytes) -> bytes:
    """Microsoft COMPRESS.EXE SZDD (LZSS, 4K ring buffer)."""
    if len(data) < 14 or data[:8] != SZDD_SIG or data[8] != 0x41:
        raise ValueError("not an SZDD-compressed file")
    want = u32(data, 0x0A)
    src = memoryview(data)[14:]
    window = bytearray(b" " * 4096)
    pos = 4096 - 16
    out = bytearray()
    i = 0
    while len(out) < want:
        if i >= len(src):
            raise ValueError("truncated SZDD stream")
        control = src[i]
        i += 1
        for bit in range(8):
            if len(out) >= want:
                break
            if control & (1 << bit):
                if i >= len(src):
                    raise ValueError("truncated SZDD literal")
                value = src[i]
                i += 1
                window[pos] = value
                out.append(value)
                pos = (pos + 1) & 0xFFF
            else:
                if i + 1 >= len(src):
                    raise ValueError("truncated SZDD match")
                matchpos = src[i]
                matchlen = src[i + 1]
                i += 2
                matchpos |= (matchlen & 0xF0) << 4
                matchlen = (matchlen & 0x0F) + 3
                while matchlen:
                    value = window[matchpos]
                    window[pos] = value
                    out.append(value)
                    pos = (pos + 1) & 0xFFF
                    matchpos = (matchpos + 1) & 0xFFF
                    matchlen -= 1
                    if len(out) >= want:
                        break
    if len(out) != want:
        raise ValueError("SZDD length mismatch")
    return bytes(out)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Volume:
    """A bare FAT12/FAT16 floppy image, or the first FAT partition of one."""

    def __init__(self, data: bytes, base: int = 0):
        self.data = data
        self.base = base
        vbr = data[base:base + SECTOR]
        if len(vbr) < SECTOR or vbr[510:512] != b"\x55\xaa":
            raise ValueError("no 0x55AA boot signature")
        self.bps = u16(vbr, 11)
        self.spc = vbr[13]
        self.rsvd = u16(vbr, 14)
        self.nfats = vbr[16]
        self.root_entries = u16(vbr, 17)
        self.total = u16(vbr, 19) or u32(vbr, 32)
        self.fatsz = u16(vbr, 22)
        if self.bps != SECTOR or self.spc == 0 or self.fatsz == 0:
            raise ValueError("unsupported FAT BPB")
        self.root_secs = (self.root_entries * 32 + SECTOR - 1) // SECTOR
        self.fat_base = base + self.rsvd * SECTOR
        self.root_base = self.fat_base + self.nfats * self.fatsz * SECTOR
        self.data_base = self.root_base + self.root_secs * SECTOR
        self.cluster_size = self.spc * SECTOR
        data_secs = (self.total - self.rsvd - self.nfats * self.fatsz -
                     self.root_secs)
        self.nclusters = data_secs // self.spc
        if self.nclusters <= 0:
            raise ValueError("empty FAT volume")
        self.fat12 = self.nclusters < 4085

    def _next(self, cluster: int) -> int:
        if self.fat12:
            off = self.fat_base + (cluster * 3) // 2
            value = u16(self.data, off)
            return (value >> 4) if (cluster & 1) else (value & 0x0FFF)
        return u16(self.data, self.fat_base + cluster * 2)

    def _eoc(self, value: int) -> bool:
        return value >= (0x0FF8 if self.fat12 else 0xFFF8)

    def _cluster(self, cluster: int) -> bytes:
        off = self.data_base + (cluster - 2) * self.cluster_size
        return self.data[off:off + self.cluster_size]

    def read_chain(self, start: int, size: int | None = None) -> bytes:
        out = bytearray()
        cluster = start
        seen = set()
        while 2 <= cluster < 0xFFF0:
            if cluster in seen:
                raise ValueError("FAT loop")
            seen.add(cluster)
            out += self._cluster(cluster)
            if size is not None and len(out) >= size:
                break
            nxt = self._next(cluster)
            if self._eoc(nxt):
                break
            if nxt == 0:
                raise ValueError("free cluster in file chain")
            cluster = nxt
        return bytes(out[:size]) if size is not None else bytes(out)

    def _entries(self, raw: bytes):
        for pos in range(0, len(raw), 32):
            e = raw[pos:pos + 32]
            if len(e) < 32 or e[0] == 0:
                break
            if e[0] == 0xE5:
                continue
            attr = e[11]
            if attr == ATTR_LFN or (attr & ATTR_VOLUME):
                continue
            name = e[0:8].rstrip(b" ").decode("cp437", "replace")
            ext = e[8:11].rstrip(b" ").decode("cp437", "replace")
            if not name or name in (".", ".."):
                continue
            yield (name + ("." + ext if ext else "")), attr, u16(e, 26), u32(e, 28)

    def _walk(self, raw: bytes, prefix: str):
        for name, attr, cluster, size in self._entries(raw):
            path = prefix + name
            if attr & ATTR_DIR:
                if cluster < 2:
                    continue
                yield from self._walk(self.read_chain(cluster), path + "/")
            else:
                yield path, self.read_chain(cluster, size) if size else b""

    def files(self):
        root = self.data[self.root_base:
                         self.root_base + self.root_secs * SECTOR]
        yield from self._walk(root, "")


def open_volume(data: bytes) -> Volume:
    """Try a bare floppy, then the first FAT partition of a hard-disk image."""
    try:
        return Volume(data)
    except ValueError:
        pass
    if len(data) < SECTOR or data[510:512] != b"\x55\xaa":
        raise ValueError("not a FAT image")
    for i in range(4):
        entry = 0x1BE + 16 * i
        ptype = data[entry + 4]
        lba = u32(data, entry + 8)
        size = u32(data, entry + 12)
        if ptype in (0x01, 0x04, 0x06, 0x0E) and lba and size:
            return Volume(data, lba * SECTOR)
    raise ValueError("no FAT partition")


class Collector:
    def __init__(self, out: Path):
        self.out = out
        self.found: dict[tuple[str, str], tuple[str, bytes]] = {}

    def add(self, name: str, data: bytes, source: str) -> None:
        target = TARGETS.get(name.upper())
        if target is None:
            return
        product, out_name = target
        if data[:8] == SZDD_SIG:
            try:
                data = decompress_szdd(data)
            except ValueError as exc:
                print("  ignored compressed %s from %s (%s)" % (
                    name, source, exc), file=sys.stderr)
                return
        if out_name in STOCK and sha256(data) != STOCK[out_name]:
            print("  ignored %s from %s (not the stock 1.01 file)" % (
                name, source), file=sys.stderr)
            return
        key = (product, out_name)
        if key in self.found:
            old_source, old_data = self.found[key]
            if old_data != data:
                print("warning: %s/%s also found in %s (keeping %s)" % (
                    product, out_name, source, old_source), file=sys.stderr)
            return
        self.found[key] = (source, data)
        dest = self.out / product / out_name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)

    @staticmethod
    def classify(names: set[str], entries: list[tuple[str, bytes]]) -> str | None:
        if names & {"VGASYS.FON", "VGAFIX.FON"}:
            return "win30"
        if names & {"HIFONTS.FON", "LOFONTS.FON", "FONTS.FON"}:
            return "win101"
        for path, payload in entries:
            base = path.rsplit("/", 1)[-1].upper()
            if base in ("USER.EXE", "GDI.EXE", "MSDOS.EXE") and \
                    sha256(payload) == STOCK[base]:
                return "win101"
        if "KERNEL.EXE" in names:
            return "win101"
        return None

    def scan_image(self, label: str, data: bytes) -> None:
        try:
            entries = list(open_volume(data).files())
        except (ValueError, struct.error) as exc:
            print("note: %s is not a readable FAT image (%s); skipped"
                  % (label, exc), file=sys.stderr)
            return
        names = {path.rsplit("/", 1)[-1].upper() for path, _ in entries}
        product = self.classify(names, entries)
        if product is None:
            print("  %-44s %4d files  (no win1-op targets)" % (label, len(entries)))
            return

        count = 0
        for path, payload in entries:
            base = path.rsplit("/", 1)[-1].upper()
            target = TARGETS.get(base)
            if target is None or target[0] != product:
                continue
            self.add(base, payload, "%s:%s" % (label, path))
            count += 1
        print("  %-44s %4d files  %s (%d target%s)" % (
            label, len(entries), product, count, "" if count == 1 else "s"))

    def scan_zip_bytes(self, label: str, data: bytes, depth: int = 0) -> None:
        if depth > 3:
            print("warning: nested ZIP too deep: %s" % label, file=sys.stderr)
            return
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                for info in zf.infolist():
                    if info.is_dir():
                        continue
                    member = info.filename
                    lower = member.lower()
                    ext = os.path.splitext(lower)[1]
                    base = member.rsplit("/", 1)[-1].upper()
                    if ext not in (".zip", ".7z") and ext not in IMG_EXTS \
                            and base not in TARGETS:
                        continue
                    payload = zf.read(info)
                    sub = "%s!%s" % (label, member)
                    if ext == ".zip":
                        self.scan_zip_bytes(sub, payload, depth + 1)
                    elif ext == ".7z":
                        self.scan_7z(sub, payload, depth + 1)
                    elif ext in IMG_EXTS:
                        self.scan_image(sub, payload)
                    else:
                        self.add(base, payload, sub)
        except zipfile.BadZipFile:
            print("note: %s is not a ZIP; skipped" % label, file=sys.stderr)

    def scan_7z(self, label: str, data: bytes, depth: int) -> None:
        seven = shutil.which("7z") or shutil.which("7zz")
        if not seven:
            print("note: %s is a 7z archive; install 7z or unzip it first"
                  % label, file=sys.stderr)
            return
        with tempfile.TemporaryDirectory(prefix="win1op-7z-") as tmp:
            archive = Path(tmp) / "in.7z"
            archive.write_bytes(data)
            dest = Path(tmp) / "out"
            subprocess.run([seven, "x", "-y", "-o" + str(dest), str(archive)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           check=False)
            for path in dest.rglob("*"):
                if not path.is_file():
                    continue
                member = path.relative_to(dest).as_posix()
                payload = path.read_bytes()
                ext = path.suffix.lower()
                base = path.name.upper()
                sub = "%s!%s" % (label, member)
                if ext == ".zip":
                    self.scan_zip_bytes(sub, payload, depth + 1)
                elif ext in IMG_EXTS:
                    self.scan_image(sub, payload)
                elif base in TARGETS:
                    self.add(base, payload, sub)


def overlapping(a: Path, b: Path) -> bool:
    a = a.resolve()
    b = b.resolve()
    return a == b or a in b.parents or b in a.parents


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("archives", nargs="+", help="WinWorld ZIP file(s)")
    ap.add_argument("--out", default="originals",
                    help="output root (default: originals)")
    ap.add_argument("--fontkit-dir",
                    help="also write fontkit/input names here (outside --out)")
    ap.add_argument("--strict", action="store_true",
                    help="fail if a required file is missing or has the wrong hash")
    args = ap.parse_args()

    out = Path(args.out)
    if args.fontkit_dir and overlapping(out, Path(args.fontkit_dir)):
        print("error: --fontkit-dir and --out must not overlap", file=sys.stderr)
        return 2

    collector = Collector(out)
    for archive in args.archives:
        path = Path(archive)
        if not path.exists():
            print("error: missing %s" % path, file=sys.stderr)
            continue
        print("== %s" % path)
        if path.suffix.lower() == ".zip":
            collector.scan_zip_bytes(path.name, path.read_bytes())
        elif path.suffix.lower() == ".7z":
            collector.scan_7z(path.name, path.read_bytes(), 0)
        elif path.suffix.lower() in IMG_EXTS:
            collector.scan_image(path.name, path.read_bytes())
        else:
            print("note: unsupported file type: %s" % path, file=sys.stderr)

    print("\n== extracted ==")
    missing = []
    reported = set()
    for source, (product, out_name) in TARGETS.items():
        key = (product, out_name)
        if key in reported or key not in collector.found:
            continue
        reported.add(key)
        src, data = collector.found[key]
        digest = sha256(data)
        note = ""
        if out_name in STOCK:
            if digest == STOCK[out_name]:
                note = "  stock 1.01 OK"
            else:
                note = "  WARNING: not the expected retail 1.01 hash"
                if args.strict:
                    missing.append("%s/%s" % (product, out_name))
        print("%-16s %-24s %7d  %s%s" % (
            product + "/", out_name, len(data), digest, note))
        print("  from %s" % src)
    for name in REQUIRED:
        product, out_name = TARGETS[name]
        if (product, out_name) not in collector.found:
            print("MISSING %-28s (needed: %s)" % (
                product + "/" + out_name, name))
            if args.strict:
                missing.append("%s/%s" % (product, out_name))

    if args.fontkit_dir and not missing:
        fk = Path(args.fontkit_dir)
        fk.mkdir(parents=True, exist_ok=True)
        copies = [
            ("win101", "FONTS.FON", "WIN101_FONTS.FON"),
            ("win101", "MSDOS.EXE", "MSDOS.ORI"),
            ("win30", "VGASYS.FON", "WIN30_VGASYS.FON"),
            ("win30", "VGAFIX.FON", "WIN30_VGAFIX.FON"),
        ]
        for product, name, dst in copies:
            src = out / product / name
            if src.exists():
                shutil.copy2(src, fk / dst)
        print("\nfontkit inputs written to %s" % fk)

    if missing:
        print("\nmissing/wrong files; check that you supplied both the "
              "Windows 1.01 retail and Windows 3.0 (VGA) WinWorld archives",
              file=sys.stderr)
        return 1

    print("\nnext:")
    print("  python3 patches/apply_patch.py --patch patches/USER-release.json \\")
    print("      --in %s/win101/USER.EXE --out build/USER.EXE" % args.out)
    print("  python3 patches/apply_patch.py --patch patches/GDI-release.json \\")
    print("      --in %s/win101/GDI.EXE --out build/GDI.EXE" % args.out)
    print("  python3 patches/apply_patch.py --patch patches/MSDOS-release.json \\")
    print("      --in %s/win101/MSDOS.EXE --out build/MSDOS.EXE" % args.out)
    print("  # fontkit: run with --fontkit-dir fontkit/input")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
