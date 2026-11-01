#!/usr/bin/env python3
"""Convert the Windows 3.0 VGA System font to a Windows 1.00 font library.

Examples:
    python3 tools/convert.py --mode fixed
    python3 tools/convert.py --mode fixed --height 12 --points 8 --ascent 10 --intlead 2
    python3 tools/convert.py --mode proportional --patch-dir

Inputs default to input/WIN30_VGASYS.FON and input/WIN101_FONTS.FON.
Outputs go to out/.
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE / "tools"))
import fontlib


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=("fixed", "proportional"), default="fixed")
    ap.add_argument("--height", type=int, default=None,
                    help="crop/scale target height (default: source 16)")
    ap.add_argument("--points", type=int, default=None)
    ap.add_argument("--ascent", type=int, default=None)
    ap.add_argument("--intlead", type=int, default=None)
    ap.add_argument("--extlead", type=int, default=None,
                    help="override resource dfExternalLeading")
    ap.add_argument("--source", default=str(HERE / "input" / "WIN30_VGASYS.FON"))
    ap.add_argument("--template", default=str(HERE / "input" / "WIN101_FONTS.FON"))
    ap.add_argument("--out-dir", default=str(HERE / "out"))
    ap.add_argument("--patch-dir", action="store_true",
                    help="patch the FONTDIRENTRY metrics (proportional does this by default)")
    args = ap.parse_args()

    src = fontlib.FonFile.open(args.source)
    font = src.font_resources()[0]
    fnt, info = fontlib.convert_30_to_10(
        src.data_of(font), args.mode, height=args.height,
        points=args.points, ascent=args.ascent, intlead=args.intlead,
        extlead=args.extlead)
    height = info["size"] and args.height or 16
    tag = args.mode.upper() + ("" if not args.height or args.height == 16
                               else str(args.height))
    outdir = Path(args.out_dir)
    outdir.mkdir(exist_ok=True)
    fnt_path = outdir / ("SYSTEM30_%s.FNT" % tag)
    fon_path = outdir / ("FONTS_30_%s.FON" % tag)
    fnt_path.write_bytes(fnt)
    patch_dir = args.patch_dir or args.mode == "proportional"
    dir_metrics = None
    if args.mode == "proportional":
        # The resource is a real 16px font.  The stock FONTDIRENTRY still
        # describes an 8x12 System face, and USER/MSDOS Executive take their
        # UI metrics from that entry.  These are the smallest metrics that
        # make SM_CYMENU and the MS-DOS toolbar two rows taller; avg/max
        # width keep the file-list columns from overlapping.
        dir_metrics = {0x4A: 13, 0x4C: 3, 0x4E: 0,
                       0x58: 18, 0x5B: 10, 0x5D: 16}
    fontlib.build_fonts_fon(args.template, fnt, fon_path, patch_dir,
                             dir_metrics=dir_metrics)
    print("mode=%s %s" % (args.mode, info))
    for p in (fnt_path, fon_path):
        data = p.read_bytes()
        print("%-32s %6d bytes  sha256 %s" %
              (p.name, len(data), hashlib.sha256(data).hexdigest()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
