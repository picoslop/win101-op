# How win1-op was made

This is a development history reconstructed from the DeepSeek Harness (DSH)
session logs, not a design document. The source of record is:

```
~/.dsh/sessions/--home-cpage-aitests-windows--/
  session-86d5e1c6-47dc-44e5-9ec6-1e73fa59af46/session.v3.jsonl.zstd
```

The history spans five sessions in the same folder, in this order:

| session | title | covers |
|---|---|---|
| `session-ae4e3170-a937-4bde-959c-0e072e57ba9f` | Decompile Windows 1.0 SDK DEBUG files | Ghidra C reconstruction |
| `session-6d20f9a3-3457-45a1-b636-dff6b24e76a7` | Continue decompiling Windows 1.0 with symbols | rebuildable 8086 assembly, linker, injection |
| `session-fe5dece9-64cf-4d43-99c8-88d8cf477b7b` | Continue decompiling Windows 1.0 with symbols | parallel continuation of the same work |
| `session-f81927bb-499d-4287-bdd5-fe3d10a66869` | Overlapping windows in Windows 1.01 USER.EXE | class-preserving overlap prototype |
| `session-86d5e1c6-47dc-44e5-9ec6-1e73fa59af46` | Starting from `~/aitests/windows/win1vga` | VGA, proportional fonts, t_ovS23, release |

The two “Continue decompiling” sessions share a starting point and were used
as parallel continuations; they converge on the same rebuilt modules. The
last session is the 59 MB JSONL log (18 MB compressed, 65 turns, 142 user
messages, 4,554 tool results, six compaction summaries) that covers the VGA
work onward.

The history below was assembled from `user/message`, `assistant/message`,
`tool/call`, `tool/result` and `compaction/summary` records in all five logs.
The compaction summaries were the most useful: they preserve the state of the
work across context resets, including hashes, failed patches and open
questions.

The work ran in nine phases (0–8).

## Phase 0 — Decompiling the Windows 1.0 SDK DEBUG modules

The project began with a Ghidra reconstruction, not a driver:

> Take a look at the windows 1.0 sdk files in the DEBUG directory. Attempt to
> do a nice C decompilation using the symbol files as a guide. Ghidra
> available.

Method:

* The SDK DEBUG `KERNEL.EXE`, `GDI.EXE` and `USER.EXE` were loaded together
  with their matching `.SYM` files in Ghidra.
* The first Ghidra pass produced `windows1.01-decompiled/`: 1,649 functions,
  0 failures, 411 prototypes, 83 `FUN_` and 112 `_REAL` names.
* A NE-header `0x2000` misdecode (32-bit fields read as 16-bit) was fixed,
  and a `patch_ne.py` tool was added so the analysis could be regenerated.
* The C was useful as a map of the code, but not yet a rebuildable system.

## Phase 1 — Rebuildable 8086 assembly and a real linker

The next session picked up an interrupted decompilation. The decisive
correction was:

> I think ghidra might be getting in the way a little here. start by making a
> rebuildable version of the debug exe's using assembler.

and:

> note: this is 8088/8086 code ONLY, it predates 80386

Method:

* Built `windows1.01-reasm/`: `meta.py` parses the NE header/tables/relocs,
  `reasm.py` emits 60 MASM segment sources from the original payloads, and
  `pack.py` rebuilds byte-identical EXEs. KERNEL, GDI and USER all reproduced
  (`f2595bc8…`, `db28be59…`, `58b28e3b…`).
* Readability passes replaced `db` runs with instructions where possible,
  added symbol labels and comments, and preserved the binary encoding when
  the decoder could not prove an instruction boundary.
* The NE relocation tables turned out to be **source chains**: a record names
  one target, and the word at the source offset can head an `FFFF`-terminated
  chain of additional references. Following the chains recovered 1,522 far
  calls that looked unrelocated.
* The code is 8086 real mode and mostly Pascal calling convention. Exported
  or callee-clean functions put the first argument at the highest `[bp+N]`;
  explicit `__cdecl` stays right-to-left.
* `grow.py` implemented append-at-end segment growth and relocation-table
  shifts; `patch_func.py`/`make_seg_build.py` patched functions and emitted
  NE type-3 relocations. The loader patches the first three bytes of every
  export with a DGROUP load, which is why trampolines keep those three bytes
  and jump at `entry+3`.
* An OMF/LINK4 path was built (`omf.py`, `link.py`, KERNEL.LIB/IMPLIB) to
  test the real linker, but the exact rebuilt binary path remained the
  reassembly/pack route. LINK4 `PACKCODE` was rejected because it collapsed
  GDI's 31 segments to 2.
* MS C 5.0 was found in the Windows 2.11 image and used for C bodies;
  MS C 3.0 did not support the required `pascal`/`far` behavior. The 8-byte
  external identifier limit forced short names. `/AL /Gw /Os /Gs` became the
  standard flags; near absolute pointers need `/AS` or a `near *` type.
* A debug DOSBox-X build (upstream `c19e15e`, heavy debug, no dynamic core)
  added `LOGSEGLOAD`, `BREAK`, `BP`, `MEMREAD`, `STEPIN` and later the binary
  `LOGB` trace. This became the main runtime microscope. The same changes
  were later integrated into a clean `66480b4a8` tree as the `win1-op-debug`
  branch.
* Mouse support and 86Box Fast Forward were added to the test VM so the
  rebuilt modules could be driven interactively.

The two “Continue decompiling” sessions both landed here. Their outputs are
the `windows1.01-reasm/` tree and the injection tooling in `work/inject/`,
which the later overlap/font work reused.

## Phase 2 — Overlapping windows in USER.EXE

The overlap work started from stock 1.01 code:

> Starting with stock windows 1.01 code, look at the techniques in AGENT.md
> and HANDOFF.md and previous attempts to plan out a working overlapping
> window version of USER.EXE.

The early plan — converting class-0 windows to popups — was rejected by the
user:

> Don't make all windows popups... change USER to handle 'tiled' windows as
> moving etc like popups already are but keep other behavior

The class-preserving design that emerged:

* Class-0 stays class-0. A marker bit in `[wnd+33h]` and the popup z-order
  list `ds:[5BAh]` provide overlap; `_TILE` never lays marked windows out.
* `CREATEWINDOW`, `SHOWWINDOW`, `DESTROYWINDOW`, `BRINGWINDOWTOTOP` and
  `MOVEWINDOW` dispatch marked windows to popup routines.
* The build appends stubs to `_TEXT`, uses same-segment far-return jumps to
  bypass the ±32K near range, and emits NE relocations for new far calls.
* Early prototypes (`t_ovS9`, `t_ovS10`, …) were tested with SYSW, BATCH8 and
  PageMaker. Input/focus bugs, icon restore and saved-bits handling were the
  recurring failures.
* The overlap work also produced the DOSBox-X `LOGB` binary trace and the
  coverage tooling used later.

The `t_ovS23` cleanup (Phase 5 below) is the final form of this design.

## Phase 3 — A VGA driver that does not need a 386

This phase's request was:

> Starting from `~/aitests/windows/win1vga` and the Windows 2.0 DDK EGA
> driver, make a Windows 1.01 VGA driver that unlike win1vbe does **not**
> require a 386.

`win1vbe` was the reference VBE implementation, but it used protected-mode
setup and bank switching. The DDK EGA colour driver was the better parent:
Windows 1.01 already had an EGA driver, and VGA mode 12h has the same planar
A000 window and 80-byte scanline as EGA 640x350.

Method:

* Started from John Elliott's Windows 1.x EGA reconstruction (itself built
  from the Windows 2.0 DDK), not from `win1vbe`.
* Added `vga.asm` with `SCREEN_HEIGHT=480`, BIOS mode 12h, a 640x480 GDIINFO,
  and corrected metric/English/twips fields for 480 lines.
* Assembled `cursor.asm` with `-DVGA`; the cursor save-area bounds move to
  480 lines while the scanline stride stays 80 bytes.
* Changed `.286p`/`.286c` to `.8086` in `bitblt.asm`/`cmacros.inc` for a
  strict 8086 build.
* Built with MASM 5.1, LINK4 4.00 and RC 1.00 through `tools/dosrun`/emu2.
* Verified in 86Box (IBM AT 286 + IBM VGA) and DOSBox-X (`svga_s3`,
  `cputype=286` and `cputype=8086`), with byte-identical screenshots between
  the 286 and 8086 runs.

The result is `VGAHIRES.DRV`, 17,536 bytes. The driver is still the one in
this release; the only hash variation between rebuilds is the LINK4/RC NE
header CRC.

## Phase 4 — Proportional System font and Fixedsys

The next request was to save the VGA baseline as a zip and start a
`proportional/` study of the Windows 3.0 System font. The key prompt was:

> win3 system font will need to be conveted, then the vga driver and gdi need
> to cast a wider net of fonts

Then:

> It looks like the font renderer has issues with proportional fonts? Dig
> into the code (and use tracing etc) and figure out what's so inflexible

What was learned:

* Windows 1.01 GDI hard-rejects FNT versions other than `0x0100`. The 3.0
  fonts are FNT 2.00 and must be converted, not copied.
* FNT 1.00 uses a 0x42-byte prefix, a 2-byte-per-character bit-column table,
  an 8-bit guard and an even `dfWidthBytes`; FNT 2.00 uses a 4-byte
  `(width, offset)` table and plane-major glyph bytes.
* GDI's `ADDNEXTFONT`/`LOADPFONTHANDLER` in `_FONTRES.asm` strips the 1.00
  header and enforces the version. The VGA driver's `StrBlt` already
  supported `dfPixWidth=0`; the apparent failure was a font-table/bit-offset
  problem, not a missing driver feature.
* A converted 16-pixel proportional face exposed UI metric problems. USER
  takes `SM_CYMENU` from the FONTDIRENTRY (`tmHeight + tmExternalLeading +
  ds:[480]`); the shell uses its own `[0x31E]`/`[0x35E]` values. Correcting
  the glyphs without correcting the directory entry left the menu one or two
  rows short and lowercase descenders touching the border.
* The accepted UI height is **18 px**. The FONTDIRENTRY was patched to
  height/ascent/leading/width values that give the menu and drive-button
  toolbar their full cell height while keeping file-name columns clear.
* The final combined library uses the proportional face for System and a
  converted Windows 3.0 `VGAFIX` face as the OEM fixed resource, with
  charset 255 so GDI's stock matching keeps it in the OEM slot.
* Windows 3.x stock font objects were checked: `OEM_FIXED_FONT=10`,
  `ANSI_FIXED_FONT=11`, `ANSI_VAR_FONT=12`, `SYSTEM_FONT=13`,
  `DEVICE_DEFAULT_FONT=14`. Windows 1.01's `GETSTOCKOBJECT` only indexes
  `< 0Fh`, and the actual tested OEM handle in the combined library is
  `0x045E`.

The shell file-list hook is a 3-byte replacement at `MSDOS.EXE _TEXT:0A0B`.
The original `push si / push di / push es` frame is replayed, the line
painter selects the OEM font for its HDC, and the caller registers are
restored. The first version used `PUSH 045Eh`; on an 8086/8088 `68h` is
`PUSH imm16` on a 186+ but decodes as `JS rel8`, corrupting the stack. That
was one of the most expensive bugs in the project, found later during the XT
work.

Screenshot verification was automated with `detect_fonts.py`, which measures
the `File`/`View` word widths and the 8-pixel file-name pitch. The accepted
result is `menu=proportional files=fixed`; the old bad state was
`fixed/fixed`.

Artifacts from this phase:

* `win1vga/proportional/out/FONTS_30_SYS_FIXEDSYS.FON`
  `e5c32237b777ac675dca5cff5dcd72b321523c6f47b3c2316d24e553c127bcd1`
* `win1vga/proportional/out/MSDOS.EXE`
  `b26f5b26f94a5629ac044faa1cdc999e11d657f290e6b4aa926280f0b31e5ad6`

## Phase 5 — t_ovS23 cleanup, resize and menu Size

The original overlap design landed in Phase 2. This phase is the cleanup that
became t_ovS23. The request evolved from “Detail all code changes, by group,
for overlapped windows and the fonts” to specific bugs: Reversi hung after `menu → Size`; keyboard fuzzing broke the
MS-DOS Executive; “do a move then size”; and finally:

> I'd like to resize the windows by clicking and dragging the edges in the
> modern fashion

The design that survived is **class-preserving overlap**:

* Class-0 windows stay class 0. A private marker in `[wnd+33h]` and the
  popup z-order list provide overlap; the style's public bits are masked in
  `GetWindowLong` and restored in `SetWindowLong`.
* `CREATEWINDOW` / `SHOWWINDOW` / `DESTROYWINDOW` / `BRINGWINDOWTOTOP` /
  `MOVEWINDOW` / `OPENWND` dispatch marked class-0 windows to the popup
  routines.
* The initial `WM_SIZE` is sent from the show path, not `CreateWindow`:
  tiled windows never got one there, and PageMaker hangs if it arrives
  before the window is ready.
* Minimize/restore uses the icon slot, a 64-entry saved-rectangle table in
  `_TEXT`, and `MOVEPOPUP`.
* The earlier popup-class conversion (`[wnd+33h] |= 0x80`) was discarded.

Resize was the hard part. Windows 1.01 has no modern edge hit codes and
returns `HTCLIENT` for much of the frame. The working path is the central
mouse dispatcher `CHECKSYSQUEUE` at `_TEXT:2A20`, not `WININPUT`:

* On button-down, the hit test and popup-z-order scan accept six pixels
  outside the window's inner rect, because the painted border/grow box lies
  outside it.
* An `EDGE_*` state records the window, edges, original rectangle, cursor
  origin and button state.
* Mouse moves apply 1:1 screen deltas with min/max clamping from
  `ds:[462h]/[464h]`; the window is moved live with `MOVEPOPUP`.
* Button-up sends the size message. Raising uses a lightweight
  `INVALIDATEALLDCS`/`UNLINKWND`/`LINKWND`/`ONEWNDREPAINT` path because
  `BRINGPOPUPTOTOP` enters the activation model loop and can hang.
* Caption text is centred as
  `y = ([506h] + [480h] - textHeight + 1) / 2`.
* GDI draws a border around the client area; ADDBORDER is the matching GDI
  change that keeps it outside the inner rect.

The system-menu **Size** item was a separate dead end. The modal
`SYSCOMMAND_SIZE_STUB` used a `INT 33h` loop, `MOVEPOPUP`,
`INVALIDATEALLDCS`, `CALCALLVISRGNS` and `COMPCLIENTRECT`; on the XT it
raised a DOS `AUX` error, and the state it left behind could break a later
drag. The final decision was to remove the menu item entirely from USER's
menu resource and keep the native Size handler as dead code. The accepted
resize path is the visible border/grow box.

The overlap/font code changes are documented in
`win1vga/OVERLAP_AND_FONTS_CHANGES.md`; the build chain is
`work/inject/t_ovS23/`.

## Phase 6 — XT, release builds, menu removal

Several asks converged here:

* “Set up a script to run in 86box with a selection of XT, 286, or 386, with
  EGA or VGA. Default to 640K XT with VGA.”
* “Spin an agent to look at feasibility of patching the win 1.01 release
  user.exe and gdi.exe.”
* “generate the release symbol map and make our patch script work on either.”
* “Look and see what modified code is causing performance issues on the XT.”
* “see if dosbox-x can be set for 808x only instructions.”

Outcomes:

* `run-86box.sh` and `make-86box-images.sh` gave a reproducible
  XT/286/386 × EGA/VGA test matrix, with 640K XT VGA as the default.
* The release `USER.EXE`/`GDI.EXE` are byte-identical reassemblies of the
  shipping files; `release_symbols.json` maps DEBUG `_TEXT` labels to the
  release offsets, so the same patch source builds both.
* The XT blank file list was traced with the MCP debugger to the MSDOS
  `68 5E 04` 80186 `PUSH imm16` stub. The fix is `BB 5E 04 53`
  (`mov bx,045Eh; push bx`). VGA and EGA XT file lists then matched the 286
  results.
* DOSBox-X was configured with `core=normal`, `cputype=8086_prefetch` and
  `cycles=fixed 4772` for an 808x-only profile. It is a useful semantic
  check, not a strict 186/286 validator.
* The menu **Size** item was removed from USER by
  `USER_SRC/remove_menu_size.py`, a post-build resource edit. Debug USER
  became `3172a399…`, release USER `74ccf119…`.

Gold checkpoints were saved as `win1vga/archive/PGOLD*.ZIP`; PGOLD34 is the
last pre-release gold (`f9c35691…`).

## Phase 7 — AT&T PC 6300 branch

The AT&T work started from a question about whether video-driver changes were
needed for proportional fonts. The answer was no, but the AT&T 6300 /
Olivetti M24 640x400 was worth a separate driver target:

* Windows 1.03a AT&T OEM `ATTDC.DRV` (15,776 bytes, `120,96,80`) and
  `FONTS400.FON` were extracted from the WinWorld AT&T OEM set.
* 86Box `machine = m24`, `gfxcard = internal`, 8086 8 MHz, 640K, XTIDE.
* Windows 3.0 uses `OLIBW.DRV` and `EGASYS`/`EGAFIX`/`EGAOEM` at this
  resolution. `EGASYS` was converted to FNT 1.00 by
  `tools/convert_egasys.py`, with a 12px/10pt, 96x72 FONTDIRENTRY.
* The first proportional build let the file-name columns touch; raising
  `dfAveCharWidth` from 7 to 9 fixed it.
* The original image installed `ATTMOUSE.DRV` (the keyboard mouse) while
  still running `MOUSE.COM` for a serial mouse. That left two mouse stacks
  active. The shipping images now use the stock serial `MOUSE.DRV` +
  `MOUSE.COM /C1 /R1` and `mouse_type = msserial`; `ATTMOUSE.DRV` is kept
  only as provenance.
* The user reported “no mouse, and alt-space seems to have crashed it.” A
  later test found the system menu opens normally on the serial image, and
  a `Parity error on system board` report on Alt+Space could not be
  reproduced in five cycles on either the old ATTMOUSE image or the serial
  image. The BIOS message is a real M24 NMI/parity path, not a Windows
  error; the old ATTMOUSE INT 9 handler is the only image component that
  writes the keyboard controller. The shipping image forces
  `MOUSE.COM /C1 /R1` so it does not probe Inport/PS2 paths.
* A Windows 2.03 `ATTDC.DRV` test failed at the splash screen with a PRN
  write fault; the 1.03a driver remains the compatible one.
* Mouse-bar menu clicks on the AT&T driver raise a blank **System Error**
  dialog. It reproduces with the **stock** 1.01 USER/GDI image, so it is an
  AT&T 1.03a driver/1.01 runtime issue, not the overlap patch. Keyboard
  menus and Alt+Space work.

The AT&T branch is documented in `win1vga/att6300/`; it is deliberately not
part of this release because its OEM driver/fonts are not redistributable.

## Phase 8 — Release packaging

The final phase turned the working tree into a redistributable package:

* Decided on a patches+scripts release with no Microsoft OS binaries, then
  named the project **win1-op** (Win1 + **Op**verlap + **P**roportional)
  because “win1vga” did not describe the two headline features.
* Added binary patches from the retail 1.01 files:
  * USER `bcdf4889…` → `74ccf119…`
  * GDI `8af20331…` → `47d780da…`
  * MSDOS `108f4a53…` → `b26f5b26…`
* The patch format is a block-copy/literal stream. A 32-byte block index
  gives compact patches (USER 5.7 KB, GDI 4.7 KB, MSDOS 1.1 KB) and a
  source/target SHA-256 check before writing.
* Added the source for each diff: `build_overlap_stock.py`,
  `USER_OVERLAY.ASM`, `USER_TEXT.diff`, `ADDBORDER.C`, `addborder.asm`,
  `POLYGON.diff`, `MSDOS_FIXEDSYS_STUB.ASM`, and the full VGA source.
* The user required the assembly/C source used to make each diff, then
  asked to remove the “Rebuild USER/GDI from source” section for now. The
  source is retained as audit material; the binary patches are the
  supported route, and the JWasm/MS C/`windows1.01-reasm` instructions were
  removed from the release docs.
* Added `tools/extract_winworld.py`, a pure-Python FAT12/FAT16 reader for
  the WinWorld ZIPs. It writes **separate destinations**:
  `originals/win101/` and `originals/win30/`, so a Windows 3.0 disk's
  `USER.EXE`/`GDI.EXE` cannot land in the 1.01 tree. `HIFONTS.FON` is
  accepted as `FONTS.FON` because SETUP installs it under that name, and
  the SZDD-compressed Windows 3.0 fonts are decompressed in pure Python.
* Added the prebuilt `drivers/VGAHIRES.DRV` (plus `.GRB`/`.LGO` and
  `MKSETUP.COM`) so users do not need the 1980s Microsoft toolchain just to
  get the VGA driver. This is the one DDK-derived binary in the package;
  `NOTICE.md` records that it is not covered by the MIT license.
* Added `docs/verify.py` and a checksum manifest, then archived the result
  as `win1-op-0.1.0.zip` / `.tar.gz`.

## Methods and tools

The workflow was not a straight line; the repeatable methods were:

* **Compaction summaries** kept the state across context resets. Hashes,
  rejected patches and open questions were carried in the summaries, not
  from memory.
* **MCP/DOSBox-X debugging** (`LOGSEGLOAD`, `BREAK`, `BP`, `MEMREAD`,
  `STEPIN`, binary CPU traces) was used to catch runtime segment bases,
  entry-vs-prologue breakpoints and the 80186 opcode bug. Static
  disassembly alone was not enough.
* **86Box differential screenshots** were the byte-identical acceptance
  test for XT/286/386 and EGA/VGA. Screenshot SHA-256s are in the test logs.
* **DOSBox-X 8086 profile** (`core=normal`, `cputype=8086_prefetch`,
  `cycles=fixed 4772`) was the quick 808x semantics loop.
* **Source reconstruction and builders**: `windows1.01-reasm` reassembles
  stock USER/GDI/KERNEL byte-identically; `build_overlap_stock.py` emits
  the overlap assembly; `make_seg_build.py` patches GDI `_POLYGON`;
  `patch_msdos_fixedsys.py` emits the shell stub. C bodies were built with
  MS C 5, assembly with JWasm, the driver with MASM/LINK4/RC.
* **Golden checkpoints**: `win1vga/archive/PGOLD*.ZIP` captured working
  states before risky changes; PGOLD34 is the last pre-release gold.
* **Release verification**: patch, font, and driver rebuilds were run in a
  clean copy of the release. USER/GDI/MSDOS and FONTS reproduce exact
  hashes; the VGA rebuild is deterministic except for the NE header CRC.

## What failed and why it matters

* The old popup-class conversion and modal `Size` stub were removed rather
  than repaired. The `Size` path is not needed once edge drag works, and
  its `INT 33h`/AUX behavior was not portable to the XT.
* `ATTMOUSE.DRV` is not reliable under 86Box's M24 keyboard-controller
  emulation; the serial mouse path is the shipping one.
* The AT&T 640x400 driver has a menu-bar mouse `System Error` that
  reproduces on stock 1.01. It is a driver/runtime compatibility issue, not
  something the overlap patch caused.
* The `Parity error on system board` report on Alt+Space was not
  reproduced. It is recorded as an open environmental/BIOS-level issue, not
  claimed fixed.
* Fast-boot `WIN100.BIN`/`WIN100.OVL` installs are not covered; the release
  targets slow-boot trees with separate `USER.EXE`/`GDI.EXE`/`DISPLAY.DRV`.

## Evidence

| item | value |
|---|---|
| debug USER | `3172a3997ccee3be3f19f20c2bf97a6e9165f22b75df813994ac5449abca3e50` |
| release USER | `74ccf1196e1fd621a7ffcf1161afdfe0c8eb30906defd6de3f33651c1f8da3cd` |
| debug GDI | `1401495c612db8ab162a8e744ae8218a3406f040acce14a27f6798e3e99fd400` |
| release GDI | `47d780da2d5d7712ed5e4fa59c9f4efd7331a18858784e99fcf3a91503d117db` |
| MSDOS (Fixedsys) | `b26f5b26f94a5629ac044faa1cdc999e11d657f290e6b4aa926280f0b31e5ad6` |
| proportional FONTS | `e5c32237b777ac675dca5cff5dcd72b321523c6f47b3c2316d24e553c127bcd1` |
| VGAHIRES.DRV | `07df255c2680e6d215c007970a32c1a4b5ce047eefc05aa0ba9ce872abc13653` |
| VGA payload (CRC-zeroed) | `4d244e87bfe4c350102718092cb88c6f34e8d864b5ab6d417d3193bf292b9077` |

## What is in this repository versus what was discarded

Kept:

* t_ovS23 USER/GDI patches, source and assembly diff.
* Proportional font kit and Fixedsys shell patch.
* VGA driver source and prebuilt binary.
* WinWorld extraction and install documentation.
* Test evidence, hashes and gold checkpoints in the development tree.

Discarded or kept only as history:

* The popup-class conversion and modal `Size` prototype.
* `ATTMOUSE.DRV` as a shipping mouse path.
* The Windows 2.03 AT&T driver experiment.
* Fast-boot integration.
* The development reconstruction/JWasm/MS C rebuild workflow from the
  release (source is retained for audit; the binary patches are supported).

The DSH logs remain the authoritative record of the sequence, including the
failed attempts that the summaries compress. The release docs are the
distilled, reproducible subset.
