# Installing into Windows 1.01

## Slow-boot vs fast-boot

Windows 1.01 can be installed in two forms:

* **slow-boot**: `C:\WINDOWS` contains `KERNEL.EXE`, `USER.EXE`, `GDI.EXE`
  and a separate `DISPLAY.DRV`. The display driver is loaded as a file, and
  the three modules are ordinary NE executables.
* **fast-boot**: SETUP links the display driver, USER and GDI into
  `WIN100.BIN`/`WIN100.OVL` (and `WIN100.OVL` is the overlay). Replacing
  `USER.EXE` or `DISPLAY.DRV` on disk does **not** change a fast-boot
  installation.

This release targets **slow-boot**. The tested 86Box images are slow-boot.
If you have a fast-boot installation, either:

1. use a slow-boot installation (the Windows 1.01 SDK/debug setup produces
   one), or
2. rebuild the fast-boot image with SETUP and the new modules; that
   integration is not provided here.

## 0. Get the original files

Use `tools/extract_winworld.py` (see `docs/BUILDING.md`) or supply the files
yourself. It writes `originals/win101/` and `originals/win30/`; the commands
below use those paths.

## 1. Back up

Copy the current `C:\WINDOWS\USER.EXE`, `GDI.EXE`, `MSDOS.EXE`, `FONTS.FON`
and `DISPLAY.DRV` somewhere safe. `examples/INSTALL.BAT` creates `*.STK`
backups if they do not already exist.

## 2. Patch the binaries

On the host:

```sh
mkdir -p build
python3 patches/apply_patch.py --patch patches/USER-release.json \
    --in  originals/win101/USER.EXE  --out build/USER.EXE
python3 patches/apply_patch.py --patch patches/GDI-release.json \
    --in  originals/win101/GDI.EXE   --out build/GDI.EXE
python3 patches/apply_patch.py --patch patches/MSDOS-release.json \
    --in  originals/win101/MSDOS.EXE --out build/MSDOS.EXE
```

Each command verifies the input hash and prints the output hash. If the input
hash is rejected, you have a different 1.01 release; stop and check
`source/README.md`.

## 3. Build the fonts and shell

```sh
cd fontkit
# The extractor already populated input/ with WIN101_FONTS.FON,
# WIN30_VGASYS.FON, WIN30_VGAFIX.FON and MSDOS.ORI.  If you supplied the
# originals by hand, copy them in (see fontkit/input/README.md).
python3 build.py
```

This produces `out/FONTS_30_SYS_FIXEDSYS.FON` (install as `FONTS.FON`) and
`out/MSDOS.EXE`. The `MSDOS.EXE` here is the same binary as the patched one;
use either.

## 4. VGA driver

Use the included `drivers/VGAHIRES.DRV` (plus `.GRB`/`.LGO`/`MKSETUP.COM`
for SETUP). No build step is needed.

To rebuild it, follow `source/vga101/RELEASE.md`.

For a slow-boot install only `VGAHIRES.DRV` is needed; copy it over
`C:\WINDOWS\DISPLAY.DRV`.

## 5. Copy into the Windows tree

From DOS, with the files on `A:`:

```dos
copy /y A:\USER.EXE    C:\WINDOWS\USER.EXE
copy /y A:\GDI.EXE     C:\WINDOWS\GDI.EXE
copy /y A:\MSDOS.EXE   C:\WINDOWS\MSDOS.EXE
copy /y A:\FONTS.FON   C:\WINDOWS\FONTS.FON
copy /y A:\VGAHIRES.DRV C:\WINDOWS\DISPLAY.DRV
```

`examples/INSTALL.BAT` assumes the four install files (USER/GDI/FONTS/MSDOS)
and `VGAHIRES.DRV` are on `A:`.

`examples/INSTALL.BAT` does this with backups and a slow-boot check.

The VGA driver's `.GRB`/`.LGO` are only needed for SETUP; they are one-line
pointers to the stock EGA grabber and CGA logo.

## 6. Mouse

The tested VGA images use the stock Microsoft serial mouse driver:

```dos
C:\WINDOWS\MOUSE.COM /C1 /R1
```

`/C1` forces COM1 and `/R1` selects 30 Hz polling, avoiding the driver's
Inport/PS2 probe. If you use a PS/2 or bus mouse, use the matching
`MOUSE.COM` options or another DOS mouse driver.

In 86Box, click once inside the guest to capture the mouse; the status bar
changes to `Press Ctrl+End or middle button to release mouse`. Press
`Ctrl+End` to release it.

## 7. Boot and check

* Desktop: 640x480, 8 colours, VGA mode 12h.
* The shell and apps should overlap, not tile.
* Drag a window by its title bar; drag an edge or the bottom-right grow box
  to resize. The system menu no longer has **Size**.
* Menus/captions use the proportional System face; the MS-DOS Executive file
  list uses the fixed 8-pixel face.
* If the desktop is blank or the splash hangs, the driver or USER patch did
  not load; restore the `.STK` backups.

## Restoring

```dos
copy /y C:\WINDOWS\USER.STK  C:\WINDOWS\USER.EXE
copy /y C:\WINDOWS\GDI.STK   C:\WINDOWS\GDI.EXE
copy /y C:\WINDOWS\MSDOS.STK C:\WINDOWS\MSDOS.EXE
copy /y C:\WINDOWS\FONTS.STK C:\WINDOWS\FONTS.FON
```

and copy your old `DISPLAY.DRV` back.
