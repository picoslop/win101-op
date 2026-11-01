# GDI.EXE patch source (ADDBORDER)

The binary patch `patches/GDI-release.json` changes the shipping Windows 1.01
release `GDI.EXE` into the ADDBORDER build.

## What is here

| file | purpose |
|---|---|
| `ADDBORDER.C` | the C source for the replacement `_POLYGON` body |
| `addborder.asm` | the MS C 5 assembly listing actually patched into `_POLYGON` |
| `POLYGON.diff` | assembly-level diff of stock `_POLYGON.asm` vs the ADDBORDER build |

The original `_POLYGON` body is a near Pascal function at `_TEXT:0C89..121E`
(1,436 bytes). ADDBORDER replaces it with the C body and redirects the entry;
the rest of GDI is unchanged.

## Provenance

The C body was compiled with MS C 5; `addborder.asm` is the compiler listing
that was written into the `_POLYGON` segment. The compiler and the
reconstruction/build toolchain are **not** part of this release. The C source,
listing and assembly diff are included for audit; the binary patch is the
supported route.

## Hashes

* input release GDI: 94,254 bytes,
  `8af20331a9290c43bd4a32419dbfc236a5df5e41e46ca20a6f2cdd881326a28f`
* output release GDI: 95,758 bytes,
  `47d780da2d5d7712ed5e4fa59c9f4efd7331a18858784e99fcf3a91503d117db`

Note: the final release GDI is 95,758 bytes; the debug-built GDI with
ADDBORDER is 97,822 bytes and is not the release input.

## Why ADDBORDER

Windows 1.01 GDI draws a border around the client area of a window. The
overlap build needs that border to remain outside the window's inner rect so
the hit test and the painted frame agree. ADDBORDER is the GDI side of that
change; `source/user` carries the USER side.
