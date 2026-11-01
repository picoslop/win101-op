# Patches

These are block-copy/literal patches against the **shipping release** Windows
1.01 files. They contain no complete Microsoft binary; the source file is
verified by SHA-256 before a byte is written.

| patch | input | input SHA-256 | output SHA-256 |
|---|---|---|---|
| `USER-release.json` | `USER.EXE` 122,400 | `bcdf4889…` | `74ccf119…` |
| `GDI-release.json` | `GDI.EXE` 94,254 | `8af20331…` | `47d780da…` |
| `MSDOS-release.json` | `MSDOS.EXE` 41,904 | `108f4a53…` | `b26f5b26…` |

## Apply

```sh
python3 apply_patch.py --patch USER-release.json \
    --in /path/to/stock/USER.EXE --out /path/to/USER.NEW
```

`--check` verifies the source and patch without writing:

```sh
python3 apply_patch.py --patch USER-release.json \
    --in /path/to/stock/USER.EXE --check
```

The output has the target hash printed. Copy the three outputs over the
matching files in a **slow-boot** `C:\WINDOWS` tree; see `docs/INSTALL.md`.
Fast-boot installs link these modules into `WIN100.BIN`/`WIN100.OVL` and need
SETUP/relink.

## Making or auditing a patch

```sh
python3 make_patch.py --from stock/USER.EXE --to built/USER.EXE \
    --out USER-release.json --label "t_ovS23"
```

The format is documented in the script. It is deterministic for a given
input/target pair. The patch data is generated from the source in
`source/`; see `source/README.md` for which code produced which binary.

## Why the input hashes matter

Windows 1.01 shipped in several releases and the SDK DEBUG modules are
different binaries. These patches were made against the retail release
`USER.EXE`/`GDI.EXE` and the retail `MSDOS.EXE`. A DEBUG SDK `USER.EXE`
(`f2595bc8…`) is **not** accepted; it has a different layout.
