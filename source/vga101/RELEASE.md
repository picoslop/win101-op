> **Prebuilt:** `drivers/VGAHIRES.DRV` is included in the release. This
> document is only for rebuilding it from source.

# VGAHIRES.DRV source (release kit)

This directory is the complete source for the Windows 1.01 VGA 640x480,
8-colour display driver. It is the Windows 2.0 DDK EGA colour engine adapted
to Windows 1.x and VGA BIOS mode 12h; it needs only an 8086/286 and uses no
386 instructions, unreal mode or VBE bank switching.

The release is source-only. `drivers/VGAHIRES.DRV` is not included.

## What you must supply

The build uses the original Microsoft tools and SDK pieces, which are not
redistributed here:

| item | where it goes |
|---|---|
| `MASM.EXE` 5.1 | `VGA101_TOOLS` directory |
| `LINK4.EXE` 4.00 | `VGA101_TOOLS` directory |
| `RC.EXE` 1.00 and `RCPP.EXE` | `VGA101_TOOLS` directory |
| `swinlibc.lib` | `src/swinlibc.lib` |
| `winstub.exe` | `src/winstub.exe` |
| `dosrun` (emu2 wrapper) | `DOSRUN` |

`swinlibc.lib` and `winstub.exe` are in the Windows 1.01 SDK. `dosrun` is the
small DOS-emulation wrapper used by the development workspace; any equivalent
that can run the DOS tools with the same relative paths works.

## Build

```sh
cd source/vga101
VGA101_TOOLS=/path/to/masm-tools \
DOSRUN=/path/to/dosrun \
python3 build.py
```

The build copies the tools into a local `tools/` directory and writes
`drivers/VGAHIRES.DRV`, `VGAHIRES.GRB`, `VGAHIRES.LGO` and (if `nasm` is
available) `MKSETUP.COM`. `MKSETUP.COM` patches a Windows 1.01 `SETUP.EXE` so
the EGA high-resolution entry installs this driver; see `INSTALL.TXT`.

Expected output: 17,536 bytes. The development build's full SHA-256 is
`07df255c2680e6d215c007970a32c1a4b5ce047eefc05aa0ba9ce872abc13653`; LINK4/RC
write the NE header CRC at `NE+0x08`, so the full hash can differ between
runs. The deterministic payload hash (NE CRC zeroed) is
`4d244e87bfe4c350102718092cb88c6f34e8d864b5ab6d417d3193bf292b9077`.
`docs/verify.py` checks the payload hash. See `docs/VERIFY.md`.

## Files

* `src/` — all assembly, includes, resources, `.DEF`, `.LNK`, `.RC` and the
  Windows 1.x prelude.
* `build.py` — the build driver.
* `mksetup.asm` — SETUP patcher source (NASM syntax).
* `README.md` — the original project README (what the driver is, test results).
* `PROVENANCE.md` — exact changes from the Microsoft DDK/John Elliott tree.
* `INSTALL.TXT` — end-user install instructions.

## Licensing

The driver sources retain Microsoft's 1984–1987 copyright headers; the
Windows 1.x reconstruction is John Elliott's work. The VGA-specific changes
are provided for use with Windows 1.01 experiments. See `NOTICE.md` at the
release root. This is not a Microsoft product and comes with no warranty.
