# MSDOS.EXE patch source (Fixedsys file list)

The binary patch `patches/MSDOS-release.json` changes the shipping Windows 1.01
`MSDOS.EXE` into the Fixedsys file-list build. The same output is produced by
`fontkit/tools/patch_msdos_fixedsys.py` when you build the fonts yourself.

## What is here

| file | purpose |
|---|---|
| `MSDOS_FIXEDSYS_STUB.ASM` | readable stub inserted at `_TEXT:0A0B` |
| `fontkit/tools/patch_msdos_fixedsys.py` | the runnable patcher (not duplicated here) |

The patch source and target are:

* input: 41,904 bytes,
  `108f4a5364f41e75846f8d8b69ad90f8e58d0a6d3dc62ded58e9988354df0e50`
* output: 41,936 bytes,
  `b26f5b26f94a5629ac044faa1cdc999e11d657f290e6b4aa926280f0b31e5ad6`

## What it does

The MS-DOS Executive file-list line painter at `_TEXT:0A05` also paints the
file names with the System font. To get the proportional System face in the
menus while keeping an 8-pixel fixed pitch for the file list, the painter must
select the OEM fixed font (`OEM_FIXED_FONT`, handle `045Eh` in the combined
`FONTS_30_SYS_FIXEDSYS.FON`) for the file-list HDC.

The stub preserves the original `push si / push di / push es` frame and the
near-call return address, selects the font through the GDI `SelectObject`
thunk, restores the caller registers, and returns to the original body.

`PUSH 045Eh` is not used: `68h` is an 80186 `PUSH imm16` and decodes as `JS
rel8` on an 8086/8088, corrupting the line painter's stack. The stub uses
`mov bx,045Eh` + `push bx`. This is why the XT file list now works.

If the font library changes, run `FINFO.EXE` (not included) to read the new
OEM handle and pass it to the patcher with `--oem-handle`.
