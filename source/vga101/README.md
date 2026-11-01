> **Release note:** this is the source-only copy. The built `drivers/`
> directory and the Microsoft `tools/` (MASM/LINK/RC) are not included.
> See `RELEASE.md` for the tools and SDK files you must supply.

# Windows 1.01 VGA display driver (640x480, 8 colours, no 386)

`drivers/VGAHIRES.DRV` is a Windows 1.01 display driver for the standard IBM
VGA 640x480 16-colour mode (BIOS mode 12h).  It presents the same 8-colour,
3-plane device to GDI as the stock Windows 1.01 EGA driver, so the Windows
desktop, fonts and applications look and behave like they do on EGA — only
with 480 instead of 350 scan lines.

It is **not** a VESA/VBE driver and does **not** need a 386.  There is no
protected-mode setup, no unreal mode, no 32-bit register, and no VBE bank
switching: the driver simply uses the VGA's planar A000:0000 window and the
VGA BIOS mode 12h.  The source is assembled as 8086 code (`BITBLT.ASM` had a
`.286p` directive in the DDK; this tree uses `.8086`), and the driver was
tested both on a 286 and with the emulated CPU restricted to 8086.

![Windows 1.01 at 640x480 on an IBM AT 286 with a VGA card](tests/win101-vga-86box-at286.png)

## What is here

| file | purpose |
|---|---|
| `drivers/VGAHIRES.DRV` | the driver (17,536 bytes) |
| `drivers/VGAHIRES.GRB` | SETUP grabber pointer, same as the stock EGA one |
| `drivers/VGAHIRES.LGO` | SETUP boot-logo pointer, same as the stock EGA one |
| `drivers/MKSETUP.COM` | makes a `SETUP.EXE` that installs this driver |
| `src/` | complete driver source (Windows 2.0 DDK EGA driver, adapted) |
| `build.py` | builds the driver with MASM 5.1 + LINK4 + RC 1.00 |
| `tests/` | screenshots and test notes |

The driver's exports are the Windows 1.01 display-driver set: BitBlt,
ColorInfo, Control, Disable, Enable, EnumDFonts, EnumObj, Output, Pixel,
RealizeObject, StrBlt, ScanLR, DeviceMode, Inquire, SetCursor, MoveCursor and
CheckCursor.

## How it is made

The drawing engine is Microsoft's Windows 2.0 DDK EGA high-resolution colour
driver (`EGAHIRES.ASM` and its modules).  The Windows 1.x version of that
source was reconstructed by John Elliott from the DDK sample and published at
<https://seasip.info/DOS/Win1/screendr.html>; this tree starts from that
reconstruction, with these VGA-specific changes:

* `vga.asm` replaces `egahires.asm`:
  * `SCREEN_HEIGHT` = 480 instead of 350;
  * `physical_enable` selects BIOS mode **12h** (640x480, 16-colour planar)
    instead of mode 10h (640x350);
  * the `GDIINFO` describes 640x480 and 240x180 mm; its metric, English and
    twips conversion fields were corrected for 480 lines (the reconstructed
    source still had the 350-line values there);
  * the driver title/description says `VGA 640x480 (8 colors)`.
* `cursor.inc`/`cursor.asm` are assembled with `-DVGA` (480-line cursor and
  save-area bounds; the cursor code itself is the same 80-bytes-per-row code
  as EGA, because mode 12h has the same 80-byte scanline).
* `bitblt.asm` and `cmacros.inc` use `.8086` instead of `.286p`/`.286c` for
  the 8086 build.  The generated code is byte-identical to the 286 build; only
  the `.DEF`/NE wrapper differs.
* `vga.def` exports the Windows 1.01 entry points and the driver name
  `VGAHIRES.DRV`.
* The `setmode.obj`/`_INIT` machinery and the Windows 2.x-only exports
  (`ExtTextOut`, `GetCharWidth`, `DeviceBitmap`, `FastBorder`, `SetAttribute`,
  `ScreenSwitchEnable`, SaveScreenBitmap) are not linked.

The result is a Windows 1 module in the same format as the stock
`EGAHIRES.DRV`: NE, linker version 4.0, two segments, one code segment, one
data segment, resources from `ega.rc`.  The loader patches each exported
function's `mov ax,ds / nop` prologue, as it does for the stock 1.01 drivers.

## Building

```sh
cd source/vga101
python3 build.py
```

`build.py` uses the bundled DOS tools in `tools/` (MASM 5.1, LINK4 4.00,
RC 1.00, RCPP) through this workspace's `tools/dosrun`/emu2.  The output is
`drivers/VGAHIRES.DRV`.  Only Python 3 and the workspace's `tools/dosrun` are
needed; no DOS machine is involved.

The build is deterministic in its code and data.  LINK4/RC write a small
NE-header checksum byte that can differ between runs; that is the only byte
that changes when the tree is rebuilt.

## Installing

### Existing slow-boot installation

A Windows 1.01 "slow-boot" install (the one with `KERNEL.EXE`, `GDI.EXE`,
`USER.EXE` and a separate `DISPLAY.DRV`) can use the driver by copying it over
the display driver:

```dos
copy a:\VGAHIRES.DRV c:\windows\DISPLAY.DRV
```

Keep a copy of the old `DISPLAY.DRV` in case you want to go back.  This is the
configuration used by the test tree in this workspace.

### Normal (fast-boot) installation, or a new install

A normal Windows 1.01 installation links the display driver into
`WIN100.BIN`/`WIN100.OVL`, so simply replacing `DISPLAY.DRV` is not enough.
Use Windows 1.01 SETUP with the supplied patcher:

1. Copy all Windows 1.01 setup files into one directory, e.g. `C:\WINSETUP`,
   and copy `VGAHIRES.DRV`, `VGAHIRES.GRB`, `VGAHIRES.LGO` and `MKSETUP.COM`
   there too.
2. Run:

   ```dos
   MKSETUP VGAHIRES
   ```

   This writes `VGASETUP.EXE`, a copy of `SETUP.EXE` whose
   "EGA (more than 64K)" entry installs `VGAHIRES.DRV` instead of
   `EGAHIRES.DRV`.  The entry keeps the EGA font set (133, 96, 72 dpi).
3. Either run `VGASETUP` and choose **VGA 640x480 (8 colors)**, or update an
   existing installation non-interactively:

   ```dos
   VGASETUP /Q C:\WINDOWS USA.DRV MOUSE.DRV VGAHIRES.DRV
   ```

   (use your own keyboard and mouse driver names).

The `.GRB` and `.LGO` files are one-line pointers to the stock
`egalores.grb`/`cga.lgo`, exactly like the stock `EGAHIRES.GRB`/`.LGO`.

## Test results

The driver in `drivers/` was tested with:

* **86Box**, IBM AT 286 (8 MHz), IBM VGA, MS-DOS 3.3, Windows 1.01 slow-boot.
  The MS-DOS Executive desktop is shown in
  `tests/win101-vga-86box-at286.png`.
* **DOSBox-X**, `machine=svga_s3`, `cputype=286` and `cputype=8086`, with the
  same Windows tree.  The two screenshots are byte-identical, and Paint opens
  and draws (`tests/win101-vga-paint-dosboxx-286.png`).  This is the check
  that no 386 instruction is required.
* The desktop, menus, the mouse cursor and Paint's BitBlt/pattern toolbar
  and text all render correctly at 640x480.

The test images use the 8-colour Windows 1.01 palette.  VGA mode 12h has 16
palette entries, but this driver — like the DDK EGA/VGA colour driver — tells
GDI it has 3 planes and 8 colours; the high bit of the VGA colour index is
ignored by the Color-Don't-Care register.  This keeps exact compatibility with
the stock EGA desktop and fonts.  A 16-colour variant would need the 4-plane
changes in the colour tables and `GDIINFO`, which are not part of this
adaptation.

## Source provenance

The engine and most files are Microsoft's Windows 2.0 DDK EGA display driver,
adapted to Windows 1.x.  The Windows 1.x reconstruction used as the starting
point is John Elliott's `ega.zip` from
<https://seasip.info/DOS/Win1/screendr.html> ("Windows 1: Screen Driver
Source", based on the Windows 2 DDK).  The VGA variant, the GDIINFO fixes and
the 8086 assembly changes are in this tree.  `mksetup.asm` is adapted from
`win1vbe`'s SETUP patcher, but no `win1vbe` display-driver source is used.
The files retain the original Microsoft copyright headers; see
`PROVENANCE.md` for the exact changes.
