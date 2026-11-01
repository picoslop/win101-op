# USER.EXE patch source (t_ovS23)

The binary patch `patches/USER-release.json` changes the shipping Windows 1.01
release `USER.EXE` into the t_ovS23 class-preserving overlap build.

## What is here

| file | purpose |
|---|---|
| `build_overlap_stock.py` | the patch generator: site patches in `_TEXT`, new `_TEXT` code, resource edits |
| `remove_menu_size.py` | removes the system-menu **Size** item after the build |
| `USER_OVERLAY.ASM` | the appended `_TEXT` overlay code, extracted from the release build listing for review |
| `USER_TEXT.diff` | assembly-level diff of the stock release `_TEXT` vs the built `_TEXT` (includes the added overlay) |

`USER_OVERLAY.ASM` is **not** a complete standalone module: it uses labels and
`REL_*` aliases from the full `_TEXT` build. `build_overlap_stock.py` is kept
as the source of record for the site patches; `USER_TEXT.diff` is the
assembly-level result.

## Provenance

The release build was produced from the stock release USER reassembly with
`build_overlap_stock.py`, using this t_ovS23 patch set:

```
create,show,wmsize,showtail,tilmove,destroy,close,bringtop,movewin,
activatetail,openwnd,getstyle,setstyle,anypopup,sysicon,syszoom,
iconhit,edgehit,captioncenter
```

`remove_menu_size.py` was run afterwards. The reconstruction/build toolchain
is **not** part of this release; the binary patch is the supported route. The
generator and diff are included for audit and for developers who already have
the development tree.

The release `USER.EXE` is 125,360 bytes,
`74ccf1196e1fd621a7ffcf1161afdfe0c8eb30906defd6de3f33651c1f8da3cd`.
The retail input is 122,400 bytes,
`bcdf488987cc4633bd3d246f6327df3239c03bec5bc9ffba478e23ab1f5eb237`.

## What the patch changes

The t_ovS23 design is described in `docs/OVERLAP.md` and in the comments at
the top of `build_overlap_stock.py`. In short:

* class-0 top-level windows keep their class and stock input path;
* a marker plus the popup z-order list gives free placement and overlap;
* `CREATEWINDOW` / `SHOWWINDOW` / `DESTROYWINDOW` / raise / move dispatch
  marked class-0 windows to the popup path;
* the painted border and grow box lie outside the window's inner rect, so
  the hit test and popup scan accept six pixels outside it;
* edge and corner drag resize is event-driven and raises the window;
* captions are centred in the available title area;
* the system-menu **Size** item is removed.

The patch also bumps the USER header resource words required by the grown
segments; `remove_menu_size.py` pads the 48-byte menu resource slot.
