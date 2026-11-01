# fontkit — proportional System + Fixedsys for Windows 1.01

This builds the combined Windows 1.01 font library and the matching MS-DOS
Executive shell:

* **System / menus / captions**: Windows 3.0 `VGASYS.FON` converted from FNT
  2.00 to FNT 1.00, true proportional 16 px, with a 18 px FONTDIRENTRY
  (ascent 13, average width 10, max width 16).
* **File list / OEM fixed**: Windows 3.0 `VGAFIX.FON` converted to an 8x15
  FNT 1.00, OEM charset 255, installed as the OEM fixed stock font.
* **Shell**: `MSDOS.EXE` line painter selects the OEM fixed handle for file
  names, so menus stay proportional and the list stays 8-pixel fixed.

## Inputs

Put the four files listed in `input/README.md` in `input/`. They are not
included in this release.

## Build

```sh
cd fontkit
python3 build.py
```

Outputs in `out/`:

| file | use |
|---|---|
| `FONTS_30_SYS_FIXEDSYS.FON` | copy to `C:\WINDOWS\FONTS.FON` |
| `MSDOS.EXE` | copy to `C:\WINDOWS\MSDOS.EXE` |

Expected hashes:

* `FONTS_30_SYS_FIXEDSYS.FON` — 14,704 bytes,
  `e5c32237b777ac675dca5cff5dcd72b321523c6f47b3c2316d24e553c127bcd1`
* `MSDOS.EXE` — 41,936 bytes,
  `b26f5b26f94a5629ac044faa1cdc999e11d657f290e6b4aa926280f0b31e5ad6`

The same `MSDOS.EXE` can also be produced by the binary patch
`patches/MSDOS-release.json`; the font library must be built from your own
Windows 3.0 fonts because it contains converted glyph data.

## Notes

* The converter fixes the FONTDIRENTRY metrics, not just the glyphs. The
  18-pixel entry gives USER's menu bar and the shell's drive-button row the
  full cell height; the average/max widths keep the file-name columns clear.
* `dfAveCharWidth` is raised from the Win3 value of 7 to 10 (and max width to
  16) for Windows 1.01's UI layout. This is a FONTDIRENTRY change; it does not
  change the glyphs.
* `WINOLDAP`/WINOLDAP fixed-font requests use the OEM face, which is why the
  Fixedsys resource is installed with charset 255.
* The `MSDOS.EXE` OEM handle `045Eh` is specific to this library. If you
  change the library, run `FINFO.EXE` and pass the new handle to
  `tools/patch_msdos_fixedsys.py --oem-handle`.
