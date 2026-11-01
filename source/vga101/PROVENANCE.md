# Provenance and exact changes

## Starting point

* **Engine**: Microsoft Windows 2.0 DDK EGA high-resolution colour display
  driver (`EGAHIRES.ASM`, `BITBLT.ASM`, `CURSOR.ASM`, `CURSORS.ASM`,
  `OUTPUT.ASM`, `PIXEL.ASM`, `SCANLR.ASM`, `POLYLINE.ASM`, `STRBLT.ASM`,
  `ROBJECT.ASM`, `ENUM.ASM`, `COLORINF.ASM`, `CONTROL.ASM`, `DITHER.ASM`,
  `CHKSTK.ASM` and the `.BLT` include files).  The DDK's VGA driver is the
  same engine with a different `VGA.ASM`, so the EGA colour path is the
  correct parent.
* **Windows 1.x adaptation**: John Elliott, "Windows 1: Screen Driver
  Source", <https://seasip.info/DOS/Win1/screendr.html>.  The `ega.zip` tree
  there is a reconstruction of the Windows 1.x EGA driver built from the
  Windows 2 DDK, and it already contains the Windows 1.x `prelude.asm`,
  module-definition files, resources and `WIN1`-specific changes.  This
  project starts from that tree so that the Windows 1.01 interface
  (GDIINFO 1.00, prologue patching, 1.00 fonts, no DLL initialisation entry)
  is the already-proven one.

No **driver** source from `win1vbe` is used; the driver is the DDK EGA
engine.  `mksetup.asm` (the SETUP patcher) is adapted from `win1vbe`'s
MKSETUP utility, which in turn is a small DOS program that rewrites the
driver name in `SETUP.EXE`.

## Differences from the reconstructed Windows 1.x EGA source

### `vga.asm` (new file; copied from `egahires.asm`)

* `SCREEN_HEIGHT` = 480.
* `physical_enable` sets BIOS mode **12h**, and checks for mode 12h.
* `physical_disable` restores the previous mode.
* `dpVertSize` = 180 mm and the GDIINFO 640x480 vertical fields.
* GDIINFO metric/English/twips conversion fields corrected for 480 lines:
  * `dpMLoWin`: 2400, 1800, 640, -480
  * `dpMHiWin`: 24000, 18000, 640, -480
  * `dpELoWin`: 375, 375, 254, -254
  * `dpEHiWin`: 3750, 3750, 254, -254
  * `dpTwpWin`: 5400, 5400, 254, -254
  The source it was adapted from still had the 350-line values in these
  fields, which made the GDIINFO internally inconsistent for 640x480.
* Driver description: `DISPLAY : 133, 96, 72 : VGA 640x480 (8 colors)`.
* No SaveScreenBitmap (`RC_SAVEBITMAP`) capability, matching the Windows 1.x
  restriction to `RC_BITBLT`.

### `cursor.asm` / `cursor.inc`

* Assembled with `-DVGA`, so `SCREEN_HEIGHT` is 480 and the save-area bounds
  are for 480 lines.  `SCAN_BYTES` remains 80 because mode 12h has the same
  80-byte scanline as EGA 640x350.
* The cursor code is the DDK EGA/VGA code, unchanged.

### `bitblt.asm`, `cmacros.inc`, `sswitch.asm`

* `.286p` / `.286c` changed to `.8086` for a strict 8086 build.  MASM 5.1
  assembles the whole driver without using any 186/286-only instruction.
* `sswitch.asm` is not linked by `vga.lnk`; the change is for consistency.

### `vga.def`, `vga.lnk`

* Windows 1.x exports only: BitBlt, ColorInfo, Control, Disable, Enable,
  EnumDFonts, EnumObj, Output, Pixel, RealizeObject, StrBlt, ScanLR,
  DeviceMode, Inquire, SetCursor, MoveCursor, CheckCursor.
* `DeviceMode` is `NODATA` (no mode dialog).
* No `ScreenSwitchEnable` import, no `ExtTextOut`/`GetCharWidth`/
  `DeviceBitmap`/`FastBorder`/`SetAttribute` exports.
* Output: `VGAHIRES.DRV`, map `VGAHIRES.MAP`, library `swinlibc/NOD`.

### `ega.rc` and `res/`

* Unchanged from the Windows 1.x reconstruction; the cursors, icons, OEM
  bitmap fonts and system bitmaps are the stock ones.  The resources are
  bound into the driver by RC 1.00.

## Build tools

* MASM 5.1 (the DOS `MASM.EXE` from the MASM 5.1 disk 1).
* LINK4 4.00 (Windows 1.01 SDK).
* RC 1.00 / RCPP (Windows 1.01 SDK).
* `tools/dosrun` + emu2 from this workspace.

The build command options mirror the original Makefile:

    MASM -z-t-Ml-b63 -I..\src ..\src\<module>;
    MASM -DVGA -z-t-Ml-b63 -I..\src ..\src\vga;
    MASM -DVGA -z-t-Ml-b63 -I..\src ..\src\cursor,vgacursr;
    LINK4 @vga.lnk
    RC -r ega.rc ega.res
    RC ega.res vgahires.drv

## Licensing

The driver sources retain Microsoft's 1984-1987 copyright headers.  The
Windows 1.x reconstruction and the `ega.zip` packaging are John Elliott's
work.  The VGA changes in this directory are provided for use with the
workspace's Windows 1.01 experiments.  No warranty is given; the source and
binary are a research/reconstruction artifact, not a Microsoft product.
