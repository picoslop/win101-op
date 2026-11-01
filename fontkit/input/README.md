# Required font inputs

These files are not included. Copy them from your own media:

| filename | source | size | SHA-256 |
|---|---|---:|---|
| `WIN101_FONTS.FON` | Windows 1.01 `FONTS.FON` | 7,472 | `853385b91fe7f9460a09c164b9f0e459865057f73759f2503ae3cccd3379acda` |
| `WIN30_VGASYS.FON` | Windows 3.0 `VGASYS.FON` | — | — |
| `WIN30_VGAFIX.FON` | Windows 3.0 `VGAFIX.FON` | — | — |
| `MSDOS.ORI` | Windows 1.01 `MSDOS.EXE` | 41,904 | `108f4a5364f41e75846f8d8b69ad90f8e58d0a6d3dc62ded58e9988354df0e50` |

`WIN30_VGASYS.FON`/`WIN30_VGAFIX.FON` are FNT 2.00 resources; the converter
reads them directly. If your Windows 3.0 files are compressed or named
`EGASYS.FON`/`EGAFIX.FON`, decompress them first. The AT&T `EGASYS` file used
by the separate AT&T project is **not** the VGA System font; use the VGA font
for this build.

The `MSDOS.ORI` name is historical; it is simply the stock 1.01 shell. The
patcher accepts any stock copy with the hash above.
