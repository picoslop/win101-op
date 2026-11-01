# NOTICE — provenance and third-party material

This release contains **no Microsoft operating-system binaries, install
media or FON/FNT font files**. It contains patch data, source code, scripts,
documentation, the small resource blobs (icons, cursors, bitmaps,
`fonts.bin`, `config.bin`) that are part of the VGA driver source tree, and
one DDK-derived binary: `drivers/VGAHIRES.DRV` (with its `.GRB`/`.LGO` and
`MKSETUP.COM`). To use it you must supply your own original Windows 1.01 and
Windows 3.0 files.

## What is MIT-licensed

The original Python tools, the patch format, the documentation and the
original assembly/C changes are offered under the MIT license in `LICENSE`.
That license does **not** cover any Microsoft-derived material listed below.

## Windows 1.01

* `USER.EXE`, `GDI.EXE`, `MSDOS.EXE`, `FONTS.FON` and the rest of Windows
  1.01 are Microsoft Corporation copyrights.
* `patches/USER-release.json`, `patches/GDI-release.json` and
  `patches/MSDOS-release.json` are diff data that modify those binaries.
  They are provided so owners of original Windows 1.01 media can reproduce
  the tested build. They are not a license to Windows 1.01 and do not
  include the original files.
* `source/user/`, `source/gdi/` and `source/msdos/` contain the new code and
  the reconstructed context needed to audit those changes. The surrounding
  Windows 1.01 code remains Microsoft's.

## Windows 1.01 SDK and Windows 2.0 DDK

* `source/vga101/src/` is the Microsoft Windows 2.0 DDK EGA high-resolution
  colour driver, adapted to Windows 1.x and VGA mode 12h. The files retain
  Microsoft's 1984–1987 copyright headers.
* The Windows 1.x adaptation started from John Elliott's "Windows 1: Screen
  Driver Source" reconstruction (`ega.zip`, <https://seasip.info/DOS/Win1/screendr.html>).
  John Elliott's work retains its own copyright.
* `source/vga101/mksetup.asm` is adapted from the `win1vbe` project's MKSETUP
  utility.
* The VGA-specific changes (mode 12h, 480-line GDIINFO, 8086 assembly
  changes) are the work of this project, but the resulting driver is a
  derivative of the Microsoft/John Elliott source. It is a
  research/reconstruction artifact, not a Microsoft product, and comes with
  no warranty. Do not redistribute it as a Microsoft driver.
* `drivers/VGAHIRES.DRV` is the built result of that source and is included
  for convenience. The MIT license does not cover it; it remains subject to
  the Microsoft/John Elliott terms above. The `.GRB`/`.LGO` files are
  one-line pointers, and `MKSETUP.COM` is built from this project's
  `mksetup.asm`.

## Windows 3.0 fonts

* `fontkit/` converts Windows 3.0 `VGASYS.FON` and `VGAFIX.FON` to Windows
  1.00 FNT resources. The input fonts are Microsoft copyrights and are not
  included. The converted output contains Microsoft glyph data; it is
  generated locally from the user's own Windows 3.0 files and is not
  included in this release.

## Emulators and tools

* **86Box** is a separate GPL project. This release does not include it.
* **DOSBox-X** is a separate GPL project. The development workspace uses a
  fork for its MCP/headless debug harness; the patch is documented in
  `docs/DOSBOX-X-FORK.md`. Stock DOSBox-X is sufficient for the install
  steps in this release.
* **MASM 5.1, LINK4 4.00, RC 1.00, RCPP, `swinlibc.lib`, `winstub.exe`** are
  Microsoft tools/libraries and are not included. Supply them from your own
  licensed SDK/toolchain.

## No affiliation

This project is not affiliated with or endorsed by Microsoft Corporation,
AT&T, Olivetti, the 86Box project, or the DOSBox-X project.

## Trademarks

Windows, MS-DOS and Microsoft are trademarks of Microsoft Corporation. AT&T
and Olivetti are trademarks of their respective owners. All trademarks are
used descriptively only.
