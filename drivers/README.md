# Prebuilt VGA driver

| file | size | SHA-256 |
|---|---:|---|
| `VGAHIRES.DRV` | 17,536 | `07df255c2680e6d215c007970a32c1a4b5ce047eefc05aa0ba9ce872abc13653` |
| `VGAHIRES.GRB` | 15 | `221d5a3202bae1c67739b0426883b1df77a919c1d801e5d068f4fffff3da5b86` |
| `VGAHIRES.LGO` | 9 | `606f666883deeadfd4351ba7b979473308d19c37a4f09026beaafa27fcc567e6` |
| `MKSETUP.COM` | 1,162 | `7a7b13d208601f9856cc794bdc0cf8086047db4d255fa52c91dbbaf496c668f9` |

`VGAHIRES.DRV` is the Windows 1.01 VGA 640x480, 8-colour driver built from
`source/vga101/` (Windows 2.0 DDK EGA engine, Windows 1.x adaptation, VGA
mode 12h). It is strict 8086/286 code.

## Slow-boot install

Copy `VGAHIRES.DRV` over `C:\WINDOWS\DISPLAY.DRV`; reboot Windows. The
`.GRB`/`.LGO` files are not needed.

## Fast-boot / SETUP install

`VGAHIRES.GRB` and `VGAHIRES.LGO` are one-line pointers to the stock EGA
grabber and CGA boot logo, as used by the stock `EGAHIRES.GRB`/`.LGO`.
`MKSETUP.COM` is the SETUP patcher (source: `source/vga101/mksetup.asm`).

Put all four files plus your Windows 1.01 setup files in one directory and
run:

```dos
MKSETUP VGAHIRES
VGASETUP
```

Choose the EGA high-resolution entry; `VGASETUP.EXE` installs `VGAHIRES.DRV`
instead of `EGAHIRES.DRV`. For a non-interactive update:

```dos
VGASETUP /Q C:\WINDOWS USA.DRV MOUSE.DRV VGAHIRES.DRV
```

(Use your own keyboard/mouse driver names.)

## Rebuilding

`source/vga101/RELEASE.md` documents the Microsoft tools and SDK files needed
to rebuild the driver. The included binary is the tested development build;
a rebuild may differ only in the LINK4/RC NE header CRC. The deterministic
payload hash is `4d244e87bfe4c350102718092cb88c6f34e8d864b5ab6d417d3193bf292b9077`
and `docs/verify.py` checks that.

## Licensing

The driver source is Microsoft Windows 2.0 DDK code adapted to Windows 1.x
(John Elliott's reconstruction); the VGA changes are this project's. The
binary is a research/reconstruction artifact, not a Microsoft product, and
comes with no warranty. See `NOTICE.md`.
