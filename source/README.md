# Patch source map

Each binary in `patches/` was produced from the source in the corresponding
directory. The patch files are the supported route for users; the source is
included so the change can be reviewed, audited and rebuilt.

| patched binary | patch | source | notes |
|---|---|---|---|
| `USER.EXE` | `patches/USER-release.json` | `source/user/` | `build_overlap_stock.py` + `remove_menu_size.py`; `USER_OVERLAY.ASM` is the appended assembly |
| `GDI.EXE` | `patches/GDI-release.json` | `source/gdi/` | `ADDBORDER.C`, compiled to `addborder.asm` |
| `MSDOS.EXE` | `patches/MSDOS-release.json` | `source/msdos/` | stub at `_TEXT:0A0B` |
| `FONTS.FON` | built, not patched | `fontkit/` | Windows 3.0 System + Fixedsys → Windows 1.00 FON |
| `VGAHIRES.DRV` | built, not patched | `source/vga101/` | Windows 2.0 DDK EGA engine adapted to VGA mode 12h |

The patches target the **shipping release** Windows 1.01 binaries, not the SDK
DEBUG modules. The release files are:

| file | size | SHA-256 |
|---|---:|---|
| `USER.EXE` | 122,400 | `bcdf488987cc4633bd3d246f6327df3239c03bec5bc9ffba478e23ab1f5eb237` |
| `GDI.EXE` | 94,254 | `8af20331a9290c43bd4a32419dbfc236a5df5e41e46ca20a6f2cdd881326a28f` |
| `MSDOS.EXE` | 41,904 | `108f4a5364f41e75846f8d8b69ad90f8e58d0a6d3dc62ded58e9988354df0e50` |
| `FONTS.FON` | 7,472 | `853385b91fe7f9460a09c164b9f0e459865057f73759f2503ae3cccd3379acda` |

If your `USER.EXE`/`GDI.EXE` hash differs, you have a different Windows 1.01
release (or the SDK DEBUG build); the patch will refuse to apply.
