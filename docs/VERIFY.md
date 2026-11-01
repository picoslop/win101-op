# Verification

## Expected outputs

| file | size | SHA-256 |
|---|---:|---|
| `USER.EXE` | 125,360 | `74ccf1196e1fd621a7ffcf1161afdfe0c8eb30906defd6de3f33651c1f8da3cd` |
| `GDI.EXE` | 95,758 | `47d780da2d5d7712ed5e4fa59c9f4efd7331a18858784e99fcf3a91503d117db` |
| `MSDOS.EXE` | 41,936 | `b26f5b26f94a5629ac044faa1cdc999e11d657f290e6b4aa926280f0b31e5ad6` |
| `FONTS.FON` | 14,704 | `e5c32237b777ac675dca5cff5dcd72b321523c6f47b3c2316d24e553c127bcd1` |
| `VGAHIRES.DRV` | 17,536 | `07df255c…` full driver; payload `4d244e87bfe4c350102718092cb88c6f34e8d864b5ab6d417d3193bf292b9077` |

Run:

```sh
python3 docs/verify.py --build build --fonts fontkit/out \
    --driver drivers/VGAHIRES.DRV --strict
```

`--stock originals/win101` additionally checks the four input files:

| file | size | SHA-256 |
|---|---:|---|
| `USER.EXE` | 122,400 | `bcdf488987cc4633bd3d246f6327df3239c03bec5bc9ffba478e23ab1f5eb237` |
| `GDI.EXE` | 94,254 | `8af20331a9290c43bd4a32419dbfc236a5df5e41e46ca20a6f2cdd881326a28f` |
| `MSDOS.EXE` | 41,904 | `108f4a5364f41e75846f8d8b69ad90f8e58d0a6d3dc62ded58e9988354df0e50` |
| `FONTS.FON` | 7,472 | `853385b91fe7f9460a09c164b9f0e459865057f73759f2503ae3cccd3379acda` |

## Patch files

| patch | SHA-256 |
|---|---|
| `patches/USER-release.json` | `ea212e8603769cc0c592d8ecd285e9071f371586e05c24b98ee7361fff168889` |
| `patches/GDI-release.json` | `344cb8570a04be004e1b23497753a0f958ab1eded492f59eb7854535f8c5f563` |
| `patches/MSDOS-release.json` | `4e3821c285a6e82a69b2afebf69e44be1af0ed4362e2549b462be668931c1f09` |

## Screenshot

`screenshot.png` — MS-DOS Executive, Write with `PRACTICE.DOC`, and Reversi
overlapping in Windows 1.01
(`41fb0e31634ee4a126f2b905b53405e9c5425b325776b61209a7de99bf00ce93`).

## Boot/behaviour checks

1. VGA mode 12h, 640x480, 8 colours; no 386.
2. MS-DOS Executive and apps overlap; not tiled.
3. Drag title bar to move, edge/grow box to resize.
4. System menu has no **Size**.
5. Menus/captions proportional; file names fixed 8 px.
6. `Alt+Space` opens the system menu (`Move / Icon / Zoom / Close /
   About…`).
7. Paint opens and its BitBlt toolbar draws.
8. On an XT (8086), the file list paints without a stack fault.

The VGA driver's LINK4/RC NE header CRC (4 bytes at `NE+0x08`) can differ
between builds. All code/data bytes are deterministic. `docs/verify.py`
checks the driver with that field zeroed; the normalized value is
`4d244e87…`. If `cmp -l` shows only bytes `NE+0x08..NE+0x0A` differing, the
build is good.
