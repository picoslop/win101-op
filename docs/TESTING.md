# Testing win1-op

## 86Box

Use an IBM XT 5160/AT 5170 with 640K, a VGA card, XTIDE/IDE storage and a
DOS 3.3/6.22 boot image containing the installed Windows tree.

1. Boot to DOS, run `WIN`.
2. Click once inside the guest to capture the mouse (status bar:
   `Press Ctrl+End or middle button to release mouse`).
3. Check:
   * 640x480 desktop, 8 colours;
   * MS-DOS Executive and apps overlap;
   * drag title bar, edges and the bottom-right grow box;
   * system menu has no **Size**;
   * proportional menus/captions, fixed 8 px file names;
   * `Alt+Space` opens Move / Icon / Zoom / Close / About…;
   * open **Paint** and draw; its BitBlt toolbar should render.
4. Save a screenshot with `Ctrl+F11`; the file is in the VM's `screenshots/`
   directory.

For the byte-identical XT check, set the 86Box CPU to 8086/8088 at 4.77–8 MHz;
there must be no 386-only path. The driver source is `.8086` throughout.

## DOSBox-X

```ini
[machine]
machine = svga_s3
[cpu]
cputype = 8086_prefetch   ; or 286
cycles = fixed 4772       ; XT-class
[autoexec]
mount c /path/to/win101-run
c:
win
```

DOSBox-X is also the simplest way to edit a FAT image:

```sh
dosbox-x -fastlaunch -exit \
  -c "imgmount c image.raw -t hdd -fs fat -size 512,63,16,64" \
  -c "mount d /path/to/build" \
  -c "copy /y d:\\USER.EXE c:\\WINDOWS\\USER.EXE" \
  -c "exit"
```

## Hash checks

```sh
python3 docs/verify.py --build build --fonts fontkit/out \
    --driver drivers/VGAHIRES.DRV --strict
sha256sum docs/screenshots/*.png
```

See `docs/VERIFY.md` for the expected values.

## Regression symptoms

| symptom | likely cause |
|---|---|
| 1.01 splash hangs | USER patch not applied / wrong input release |
| green screen or "Abort, Break or Ignore?" | USER/GDI patch mix, or a GDI/USER version mismatch |
| tiled windows | USER patch not loaded, or a fast-boot `WIN100.BIN` still in use |
| no file list on XT | MSDOS.EXE patch not applied, or the `push imm16` regression returned |
| fixed menus | `FONTS.FON` is the stock library, or the MSDOS handle is wrong |
| missing/blank desktop | `DISPLAY.DRV` is not `VGAHIRES.DRV`, or mode 12h is unavailable |
| mouse dead | click to capture; check `MOUSE.COM /C1 /R1` and COM1 |
