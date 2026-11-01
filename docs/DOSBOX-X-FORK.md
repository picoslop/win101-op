# DOSBox-X fork for the development harness

`DOSBOX-X-WIN101-HELPERS.patch` is the patch for the development
workspace's DOSBox-X fork. It is **not required to install or run** the
win1-op release; stock DOSBox-X can mount a disk image and copy files. It is
documented because the screenshots, traces and hash tests were produced with
it.

## Base

Upstream DOSBox-X master, commit
`66480b4a84c9adc8002f21b332da8f694a9978c4` (2026-10-29). The changes are
merged to `master`; `win1-op-debug` points at the same commit,
`cba6bf5ff04e3b73e804818114149e57c992a52f`. Build with
`--enable-debug=heavy --disable-dynamic-core --disable-optimize` and the
debug CFLAGS in `WIN1-OP-DEBUG.md` for the harness.

## What the patch adds

| change | purpose |
|---|---|
| `DEBUG_MCP_*` break/headless entry points | drive the emulator over the MCP socket without an attached SDL window |
| `LOGSEGLOAD` in `debug.cpp` | log every Windows `SEGLOAD` call and return, with the module name, to `SEGLOAD.TXT` without stopping the CPU |
| `LOGB` binary CPU trace | compact per-instruction register delta trace (`LOGCPU.BIN`) for long drawing traces |
| `MOUSEMOVE` / `MOUSEBUTTON` | inject relative mouse motion/buttons from the test harness |
| memory/NEDUMP commands | `MEMDUMPASC`, `MEMCMP`, `MEMFINDSTR`, `MEMFINDHEX`, `NEDUMP`, `WINSCAN` |
| `SAVESTATE` / `LOADSTATE` | full emulator state save/restore |
| richer illegal-interrupt message | print the faulting `CS:IP` and `SS:SP` |
| monitor null-server guard | fail the listen instead of leaving a null `_server`; guard a null listener thread |

The monitor's empty/`off` handling was already improved upstream; the
integrated fork keeps that version and adds only the null-server/null-thread
guard.

This is a test/debug fork, not a runtime dependency. The release's install
steps use the DOS `copy` command through DOSBox-X; no patched debugger
feature is used.

## Applying to a clean tree

```sh
git clone https://github.com/joncampbell123/dosbox-x.git
cd dosbox-x
git checkout 66480b4a84c9adc8002f21b332da8f694a9978c4
git apply /path/to/DOSBOX-X-WIN101-HELPERS.patch
./autogen.sh
(cd vs/sdl && ./build-dosbox.sh)
(cd vs/sdlnet && ./build-dosbox.sh)
CFLAGS='-g3 -O0 -fno-inline -fno-omit-frame-pointer' \
CXXFLAGS='-g3 -O0 -fno-inline -fno-omit-frame-pointer' \
./configure --enable-debug=heavy --disable-dynamic-core --disable-optimize \
    --prefix=/usr
make -j48
```

The patch is GPL-2.0-or-later, like DOSBox-X. It is not part of the MIT
license for win1-op; see `NOTICE.md`.
