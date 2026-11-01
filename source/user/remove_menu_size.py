#!/usr/bin/env python3
"""Remove the Size item from USER's system-menu resource.

The resource (type 4, id 1) is a top-level popup whose submenu is:

    90 20 00 | [00 00 f0 "Size\0"] [00 10 f0 "Move\0"] ...

The top-level popup starts at byte 0 and its submenu at byte 3.  Remove the
eight-byte Size item (one flags byte, word id, NUL-terminated text) and shift
the remaining items left inside the existing 48-byte resource slot.  The trailing padding is ignored because Close carries MF_END (0x80).
No resource-table or NE offset changes are needed.
"""
from pathlib import Path
import sys

SIZE_ITEM_LEN = 8
RESOURCE_LEN = 48


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: remove_menu_size.py USER.EXE", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    data = bytearray(path.read_bytes())
    needle = b"Size\x00"
    pos = data.find(needle)
    if pos < 0:
        print("remove_menu_size: system-menu pattern not found", file=sys.stderr)
        return 1
    start = pos - 6                  # 90 20 00 00 00 f0 before "Size"
    if bytes(data[start + 3:start + 11]) != b"\x00\x00\xf0Size\x00":
        print("remove_menu_size: unexpected item header", file=sys.stderr)
        return 1
    block = bytes(data[start:start + RESOURCE_LEN])
    new = block[:3] + block[11:] + b"\x00" * SIZE_ITEM_LEN
    if len(new) != RESOURCE_LEN or b"Size\x00" in new:
        print("remove_menu_size: patch failed", file=sys.stderr)
        return 1
    data[start:start + RESOURCE_LEN] = new
    path.write_bytes(data)
    print(f"removed system-menu Size at 0x{start:X} ({path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
