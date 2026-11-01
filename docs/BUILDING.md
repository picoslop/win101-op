# Building and preparing Windows 1.01 from original files

There are two supported levels of work:

1. **Patch the shipped binaries** — Python 3 only.
2. **Build the fonts and the VGA driver** — Python 3 plus the original
   Microsoft tools/libraries for the driver.

## External software summary

| software | version | used for | included? |
|---|---|---|---|
| Python | 3.8+ | patch tool, font converters, build scripts | no (stdlib only) |
| Windows 1.01 retail | 1.01 | `USER.EXE`, `GDI.EXE`, `MSDOS.EXE`, `FONTS.FON` | **no** |
| Windows 3.0 | 3.0 | `VGASYS.FON`, `VGAFIX.FON` | **no** |
| MASM | 5.1 | rebuilding the VGA driver (optional) | **no** |
| LINK4 | 4.00 | rebuilding the VGA driver (optional) | **no** |
| RC + RCPP | 1.00 | rebuilding the VGA driver (optional) | **no** |
| Windows 1.01 SDK | 1.01 | `swinlibc.lib`, `winstub.exe` (optional driver rebuild) | **no** |
| `dosrun`/emu2 | workspace tool | run DOS tools on Linux | **no** |
| NASM | 2.x | build `MKSETUP.COM` (optional) | **no** |
| DOSBox-X | recent | mount/copy into a FAT image; test | **no** |
| 86Box | 6.x | run the VGA/XT images | **no** |
| 7-Zip | 16+ | extract files from FAT12/FAT16 disk images | **no** |

No Python packages are needed. The scripts use `argparse`, `hashlib`,
`json`, `base64`, `struct`, `pathlib` and `subprocess` only.

## 1. Extract the original files

WinWorld ZIPs of the 1.01 and 3.0 floppy sets can be unpacked directly:

```sh
python3 tools/extract_winworld.py Windows101.zip Windows30.zip \
    --fontkit-dir fontkit/input
```

The script reads FAT12/FAT16 images itself and writes two separate trees:

```
originals/win101/   USER.EXE GDI.EXE MSDOS.EXE FONTS.FON KERNEL.EXE
originals/win30/    VGASYS.FON VGAFIX.FON
```

It classifies each image first, so a Windows 3.0 disk's USER.EXE/GDI.EXE
cannot be written into the Windows 1.01 tree. `FONTS.FON` is taken from the
1.01 setup disk's `HIFONTS.FON` (SETUP installs that as `FONTS.FON`).
Windows 3.0 stores `VGASYS.FON`/`VGAFIX.FON` SZDD-compressed on the retail
disk; the extractor decompresses them itself. `--fontkit-dir` must be
outside `--out`; overlapping destinations are rejected.

If you prefer to extract by hand, 7-Zip or DOSBox-X can also read the images.
The patches need the **retail release** binaries:

| file | size | SHA-256 |
|---|---:|---|
| `USER.EXE` | 122,400 | `bcdf4889…` |
| `GDI.EXE` | 94,254 | `8af20331…` |
| `MSDOS.EXE` | 41,904 | `108f4a53…` |
| `FONTS.FON` | 7,472 | `853385b9…` |

If your `USER.EXE` is 123,792 bytes or 125,472 bytes, it is a different
release/debug build and the patch will refuse it. See `source/README.md`.

Windows 3.0 `VGASYS.FON`/`VGAFIX.FON` come from the Windows 3.0 VGA driver
disk. They are FNT 2.00 containers; `fontkit` reads them directly. If you
have the compressed `EGASYS.FON`/`EGAFIX.FON` names from an OEM set, they are
not the same fonts; use the VGA set.

## 2. Patch the binaries

```sh
mkdir -p build
for n in USER GDI MSDOS; do
    python3 patches/apply_patch.py \
        --patch patches/$n-release.json \
        --in  originals/win101/$n.EXE \
        --out build/$n.EXE
done
```

See `patches/README.md`.

## 3. Build the proportional fonts

```sh
cd fontkit
# input/WIN101_FONTS.FON, WIN30_VGASYS.FON, WIN30_VGAFIX.FON, MSDOS.ORI
python3 build.py
```

The build runs `convert.py --mode proportional`, `convert_fixedsys.py` and
`patch_msdos_fixedsys.py`. It verifies the stock `WIN101_FONTS.FON` and
`MSDOS.ORI` hashes; the Windows 3.0 fonts are not hash-pinned because
several 3.0 releases carry the same faces.

Outputs: `out/FONTS_30_SYS_FIXEDSYS.FON`, `out/MSDOS.EXE`.

## 4. VGA driver

`drivers/VGAHIRES.DRV` is included, so most users can skip this section.
Copy it over `C:\WINDOWS\DISPLAY.DRV` (slow-boot) or use it with
`MKSETUP.COM`/SETUP (fast-boot). See `drivers/README.md`.

To rebuild it, supply MASM 5.1, LINK4 4.00, RC 1.00 + RCPP, Windows 1.01 SDK
`swinlibc.lib`/`winstub.exe`, and a `dosrun` wrapper:

```sh
cd source/vga101
# copy swinlibc.lib and winstub.exe into src/
VGA101_TOOLS=/path/to/masm-tools \
DOSRUN=/path/to/dosrun \
python3 build.py
```

Output: `drivers/VGAHIRES.DRV` (17,536 bytes,
`07df255c…`), plus `.GRB`, `.LGO` and `MKSETUP.COM` if NASM is available.
See `source/vga101/RELEASE.md`.

## 5. Install into a disk image or a DOS tree

For an existing slow-boot tree, copy the files as in `docs/INSTALL.md`.

For an 86Box hard-disk image, DOSBox-X can mount the image and copy files
with DOS commands:

```sh
Xvfb :99 &
DISPLAY=:99 dosbox-x -fastlaunch -exit \
  -c "imgmount c /path/to/windows101.raw -t hdd -fs fat -size 512,63,16,64" \
  -c "mount d /path/to/build" \
  -c "copy /y d:\\USER.EXE c:\\WINDOWS\\USER.EXE" \
  -c "copy /y d:\\GDI.EXE c:\\WINDOWS\\GDI.EXE" \
  -c "copy /y d:\\MSDOS.EXE c:\\WINDOWS\\MSDOS.EXE" \
  -c "copy /y d:\\FONTS.FON c:\\WINDOWS\\FONTS.FON" \
  -c "copy /y d:\\VGAHIRES.DRV c:\\WINDOWS\\DISPLAY.DRV" \
  -c "exit"
```

The `-size` geometry must match the image; use `fdisk -l image.raw` to read
the CHS values. A 32 MB image is typically `512,63,16,64`.

## 6. Testing

Use 86Box (IBM XT 5160/AT 5170 + VGA, 640K) or DOSBox-X (`svga_s3`, 286/8086
CPU). Expected hashes are in `docs/VERIFY.md`; the repository screenshot is
`screenshot.png`.

## DOSBox-X changes

The development fork's patch is in `docs/DOSBOX-X-FORK.md`. It adds the MCP
break/headless entry, `LOGSEGLOAD`, the binary CPU trace and VNC mouse
injection. It is not required to build or install this release; stock
DOSBox-X can mount and copy disk images.
