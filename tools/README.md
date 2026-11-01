# tools

## extract_winworld.py

Extracts the files win1-op needs from the WinWorldPC ZIP downloads, without
7-Zip, DOSBox or a mount step. It reads FAT12/FAT16 floppy images in pure
Python.

```sh
python3 tools/extract_winworld.py Windows101.zip Windows30.zip \
    --fontkit-dir fontkit/input
```

Output is split by product, so the Windows 3.0 disk's USER.EXE/GDI.EXE can
never overwrite the Windows 1.01 files:

```
originals/win101/   USER.EXE GDI.EXE MSDOS.EXE FONTS.FON KERNEL.EXE
originals/win30/    VGASYS.FON VGAFIX.FON
```

`FONTS.FON` is taken from the 1.01 setup disk's `HIFONTS.FON`; SETUP installs
that file as `FONTS.FON`. `--fontkit-dir` must be outside `--out`; overlapping
destinations are rejected instead of merged.

The script verifies the retail 1.01 hashes and ignores any same-named file
from another product/release. Use `--strict` to fail on a missing or wrong
required file. Windows 3.0's `VGASYS.FON`/`VGAFIX.FON` are stored
SZDD-compressed on the retail disk; the script decompresses them in pure
Python.

Only ZIP input is required. A `.7z` member is supported when a `7z` command
is installed.
