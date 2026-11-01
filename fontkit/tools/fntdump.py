#!/usr/bin/env python3
"""Dump FON resources and FNT headers.

usage: python3 tools/fntdump.py FILE.FON [FONT_INDEX]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fontlib


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip())
        return 2
    idx = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    print(fontlib.dump(sys.argv[1], idx))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
