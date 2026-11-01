# Changelog

## 0.1.0 — 2026-11-01

First public source/patch release.

### Added

* `VGAHIRES.DRV` source: Windows 2.0 DDK EGA colour engine adapted to
  Windows 1.01 and VGA BIOS mode 12h (640x480, 8 colours, 8086/286 only).
* t_ovS23 overlap USER patch: class-preserving free placement, z-order,
  raise, move, edge/corner drag resize, centred captions, no system-menu
  **Size**.
* GDI ADDBORDER patch: border drawn outside the window's inner rect.
* Proportional System font backport: Windows 3.0 VGASYS → FNT 1.00,
  18 px FONTDIRENTRY, menu/caption proportional.
* Fixedsys file list: Windows 3.0 VGAFIX → OEM fixed face plus the
  MS-DOS Executive line-painter patch.
* Binary patch format and tools for release `USER.EXE`, `GDI.EXE`,
  `MSDOS.EXE`.
* Font build kit for `FONTS.FON` + `MSDOS.EXE`.
* Prebuilt `VGAHIRES.DRV` (plus `.GRB`/`.LGO`/`MKSETUP.COM`).
* `tools/extract_winworld.py`: extract the required files from WinWorld ZIPs
  into separate `originals/win101/` and `originals/win30/` trees.
* Install, build, verify, development-history and DOSBox-X fork documentation.
* DOSBox-X debug harness integrated at upstream `66480b4a8` as the
  `win1-op-debug` branch (MCP, `LOGSEGLOAD`, `LOGB`, memory/NEDUMP commands,
  mouse injection, savestate/loadstate).

### Known limitations

* Slow-boot trees only; fast-boot `WIN100.BIN`/`WIN100.OVL` needs
  SETUP/relink integration, not included.
* VGA driver is 8-colour; 16-colour needs 4-plane tables/GDIINFO changes.
* AT&T PC 6300 is a separate project, not included.
* No Microsoft OS binaries, FON/FNT fonts, DOS or emulator are included; the one DDK-derived binary is `drivers/VGAHIRES.DRV`.
