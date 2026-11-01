#!/usr/bin/env python3
# Reference source for the t_ovS23 patch.  This script expects the development
# reconstruction tree (windows1.01-reasm) and JWasm; those tools are not part
# of this release.  The binary patch in patches/ is the supported route.  The
# file is included so the site patches can be audited.
"""Build selected pieces of the class-preserving overlap prototype.

Base: work/inject/user_base (stock Windows 1.01 USER reassembly).
All new code is appended to _TEXT; _TILE is not grown.

PATCHES=comma,list
  create       CREATEWINDOW class-0 -> marker + popup list/type + size
  show         SHOWWINDOW dispatch of marked class-0 to the popup branch
  wmsize       suppress the initial WM_SIZE for marked class-0
  showtail     PUTPOPUPWND then COMPCLIENTRECT(hwnd,1) for marked class-0
  destroy      DESTROYWINDOW dispatch of marked class-0 to CLOSEPOPUPWND
  bringtop     BRINGWINDOWTOTOP dispatch of marked class-0 to BRINGPOPUPTOTOP
  movewin      MOVEWINDOW dispatch of marked class-0 to MOVEPOPUP
  close        CLOSEWNDPROLOG hides marked class-0 like a popup
  sysicon      SYSCOMMAND SC_ICON minimizes marked class-0 via ShowWindow(2)
  syszoom      SYSCOMMAND SC_ZOOM maximizes/restores marked class-0 via ShowWindow(3/1)
  tilmove      _TILE INITMOVESIZETILEDWND uses the popup move tracker
  activatetail raise marked windows at the activation tail (after ds:[64])
  activate     OLD pre-activation hook; known to recurse/hang.  Do not use.

The prototype default set is the validated core:
    create,show,wmsize,showtail

A class-0 window created with cx == 0 and cy == 0 asks for default
placement: it gets 480x252 on the 640x350 desktop at (80,40) plus a 4-step
8 px cascade so it can actually be moved.  A class-0 window that passes
cx == 0 with a non-zero cy is a placeholder-size request (the MS-DOS
Executive does this) and keeps the previous 600x310 default.  Windows that
pass an explicit size keep it.
"""
import base64
import json
import os
import re
import shutil
import struct
import subprocess
import sys

ROOT = os.environ.get('WIN1OP_ROOT', os.getcwd())
BASE = os.environ.get(
    'BASE', os.path.join(ROOT, 'work/inject/user_base'))
OUT = os.environ.get('OUT', os.path.join(ROOT, 'work/inject/ov_variant'))
JWASM = os.path.join(ROOT, 'windows1.01-reasm/tools/jwasm')
# Release builds use a map produced by make_release_symbols.py.  The map
# contains DEBUG -> RELEASE _TEXT offsets and the release assembly line for
# every DEBUG label.  The builder inserts REL_<label> aliases at those lines
# and translates the labels used by the appended chunks.
SYMBOL_MAP = os.environ.get(
    'SYMBOL_MAP', os.path.join(BASE, 'release_symbols.json'))
SYMBOLS = {}
SITES = {}
RELEASE = False
if os.path.exists(SYMBOL_MAP):
    _map = json.load(open(SYMBOL_MAP))
    SYMBOLS = _map.get('labels', {})
    SITES = _map.get('sites', {})
    RELEASE = True
PATCHES = set(filter(None, os.environ.get(
    'PATCHES',
    'create,show,wmsize,showtail'
).split(',')))
if 'edgehit' in PATCHES and 'iconhit' not in PATCHES:
    raise SystemExit('edgehit requires iconhit')

sys.path.insert(0, os.path.join(ROOT, 'windows1.01-reasm'))
import grow


def run(cmd, env=None):
    p = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if p.returncode:
        print(p.stdout)
        print(p.stderr)
        raise SystemExit('failed: %r' % (cmd,))
    return p


def find_label(lines, label, start=0):
    if RELEASE and (label in SYMBOLS or label in SITES):
        alias = 'REL_' + label + ':'
        for i in range(start, len(lines)):
            if lines[i].strip() == alias:
                return i
        raise SystemExit('missing release alias %s' % alias)
    for i in range(start, len(lines)):
        if lines[i].strip().startswith(label + ':'):
            return i
    raise SystemExit('missing label %s' % label)


CHUNK_DEFS = set()


def find_label_end(lines, label, start=0):
    """Return the original label line at the end of a patch range.

    In release mode find_label() returns the REL_ alias, which is placed
    immediately before the instruction and after the original label.  A
    range replacement that ends at the alias would also delete the original
    label (and break any branch that targets it).  Return the original label
    line instead so the range excludes it.
    """
    i = find_label(lines, label, start)
    if not RELEASE:
        return i
    j = i - 1
    while j >= 0 and (not lines[j].strip() or
                      lines[j].strip().startswith(';')):
        j -= 1
    if j >= 0 and lines[j].strip().startswith(label + ':'):
        return j
    return i


def alias_target(lines, line):
    """Line before which a REL_ alias must go.

    The map's line is the release assembly line for the DEBUG offset.  If it
    is a label line, skip consecutive labels/comments/blank lines so the
    alias lands immediately before the first instruction; patch functions
    use `alias + 1` for that instruction.
    """
    if line is None or line < 0 or line >= len(lines):
        return None
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*:', lines[line]):
        i = line + 1
    else:
        i = line
    while i < len(lines):
        s = lines[i].strip()
        if (not s or s.startswith(';') or
                re.match(r'^[A-Za-z_][A-Za-z0-9_]*:', lines[i])):
            i += 1
            continue
        return i
    return None


def insert_release_aliases(lines):
    """Put REL_<label> aliases at the release instruction for each label."""
    by_line = {}
    for name, rec in SYMBOLS.items():
        if name in CHUNK_DEFS or not rec.get('exact', False):
            continue
        t = alias_target(lines, rec.get('line'))
        if t is not None:
            by_line.setdefault(t, set()).add('REL_' + name)
    # Site aliases are used as the line *before* the instruction; the patch
    # functions add +1 explicitly.
    for name, rec in SITES.items():
        t = alias_target(lines, rec.get('line'))
        if t is not None:
            by_line.setdefault(t, set()).add('REL_' + name)
    for t in sorted(by_line, reverse=True):
        aliases = [a + ':' for a in sorted(by_line[t])]
        lines[t:t] = aliases
    print('inserted %d release alias lines for %d labels and %d sites'
          % (sum(len(v) for v in by_line.values()), len(SYMBOLS), len(SITES)))


def translate_release_labels(text):
    """Replace original labels in the appended chunks with REL_ aliases."""
    if not RELEASE:
        return text

    def repl(m):
        name = m.group(0)
        if name in CHUNK_DEFS:
            return name
        if name in SYMBOLS or name in SITES:
            return 'REL_' + name
        return name

    return re.sub(r'\b[A-Za-z_][A-Za-z0-9_]*\b', repl, text)




def jmp_ret(label, nbytes):
    """push cs / mov ax,offset / push ax / retf, NOP padded."""
    assert nbytes >= 6
    out = ['        push cs',
           '        mov ax,offset %s' % label,
           '        push ax',
           '        retf']
    pad = nbytes - 6
    while pad:
        n = min(16, pad)
        out.append('        db ' + ','.join('090h' for _ in range(n)))
        pad -= n
    return out


def patch_create(lines):
    i = find_label(lines, 'L_031F')
    j = find_label_end(lines, 'L_0340', i)
    lines[i + 1:j] = jmp_ret('CREATE_OVERLAP_STUB', 0x21)


def patch_show(lines):
    i = find_label(lines, 'L_0E6A')
    j = find_label_end(lines, 'L_0E79', i)
    lines[i + 1:j] = (['        mov [bp-6h],ax'] +
                      jmp_ret('SHOW_DISPATCH_STUB', 12))


def patch_wmsize(lines):
    i = find_label(lines, 'L_04C8')
    k = next(x for x in range(i, len(lines))
             if lines[x].strip() == 'cmp word ptr [bp-1Ah],0h' and
             lines[x + 1].strip() == 'jz short L_04FF')
    lines[k:k + 2] = jmp_ret('WMSIZE_STUB', 6)
    # label the send path
    for x in range(k, len(lines)):
        if lines[x].strip() == 'push si':
            lines.insert(x, 'PATCH_04DE:')
            break


def patch_destroy(lines):
    i = find_label(lines, 'L_07FC')
    k = next(x for x in range(i, len(lines))
             if lines[x].strip() == 'mov al,[si+33h]' and
             lines[x + 3].strip() == 'jnz short L_0814')
    lines[k:k + 4] = jmp_ret('DESTROY_DISPATCH_STUB', 9)
    for x in range(k, len(lines)):
        if lines[x].strip() == 'push si':
            lines.insert(x, 'PATCH_080E:')
            break


def patch_bringtop(lines):
    i = find_label(lines, 'L_203A')
    lines[i + 1:i + 5] = jmp_ret('BRINGTOP_DISPATCH_STUB', 9)
    for x in range(i, len(lines)):
        if lines[x].strip() == 'push si':
            lines.insert(x, 'PATCH_2043:')
            break


def patch_movewin(lines):
    i = find_label(lines, 'L_207A')
    lines[i + 1:i + 5] = jmp_ret('MOVEWIN_DISPATCH_STUB', 9)
    for x in range(i, len(lines)):
        if lines[x].strip() == 'push si':
            lines.insert(x, 'PATCH_2083:')
            break


def patch_activate(lines):
    i = find_label(lines, 'L_3180')
    lines[i + 1:i + 5] = jmp_ret('ACTIVATE_DISPATCH_STUB', 15)
    for x in range(i, len(lines)):
        if lines[x].strip() == 'push si':
            lines.insert(x, 'PATCH_3189:')
            break


def patch_close(lines):
    i = find_label(lines, 'CLOSEWNDPROLOG')
    k = next(x for x in range(i, i + 100)
             if lines[x].strip() == 'test byte ptr [si+33h],0C0h')
    lines[k] = '        test byte ptr [si+33h],0C1h'


def patch_activatetail(lines):
    """Raise a marked class-0 window after it becomes active.

    Raising before ds:[64]=si makes BRINGPOPUPTOTOP's nested
    ACTIVATEWINDOW(3) recurse and hang the splash.  Hook the function tail
    instead, after the active-window/focus state is committed.
    """
    i = find_label(lines, 'L_322D')
    # 0x322D..0x3235 is mov [bp-4],ax + mov ds:[3BA],1 (9 bytes).
    assert lines[i + 1].strip() == 'mov [bp-4h],ax'
    assert lines[i + 2].strip() == 'mov word ptr ds:[3BAh],1h'
    lines[i + 1:i + 3] = jmp_ret('ACTIVATE_TAIL_STUB', 9)


def patch_anypopup(lines):
    """Count only true popups; marked top-level overlap windows do not count."""
    i = find_label(lines, 'ANYPOPUP')
    j = find_label_end(lines, 'DESTROYWINDOW', i)
    body = []
    for x in range(i + 1, j):
        t = lines[x].strip()
        if (t and not t.startswith('db ') and not t.startswith('add ') and
                not t.startswith('REL_')):
            body.append(x)
    k = body[0]
    n = (0x07E5 - (0x07D8 + 5))
    lines[k:j] = jmp_ret('ANYPOPUP_STUB', n)


def patch_syszoom(lines):
    """Route the system-menu Zoom command for marked class-0 windows to
    ShowWindow(hwnd,3) or restore via ShowWindow(hwnd,1)."""
    i = find_label(lines, 'L_4206')
    k = next(x for x in range(i, i + 50)
             if lines[x].strip() == 'cmp word ptr [bp-0Ah],0h')
    assert lines[k + 1].strip().startswith('jnz short ')
    assert lines[k + 2].strip().startswith('jmp near ptr ')
    lines[k:k + 3] = jmp_ret('SC_ZOOM_STUB', 9)


def patch_icon_open(ilines):
    """Icon double-click: restore the window instead of activate+open it.

    The stock branch calls FARACTIVATEWINDOW(hwnd,1) and then FARFOPENICON,
    which spins on a stale icon-slot handle.  The two pushes already pass
    (hwnd, 1), so retarget that one far call to SHOWWINDOW(hwnd, 1): the
    overlap show path restores a marked window from SAVED_RECTS.
    """
    i = find_label(ilines, 'L_02C9')
    k = i + 1
    assert ilines[k].strip() == 'push di', ilines[k]
    assert ilines[k + 1].strip() == 'mov ax,1h', ilines[k + 1]
    assert ilines[k + 2].strip() == 'push ax', ilines[k + 2]
    assert 'FARACTIVATEWINDOW' in ilines[k + 3], ilines[k + 3]
    ilines[k + 3] = ('        FARCALL 0332h, 0EEEEh'
                     '  ; far call SHOWWINDOW (export #42)')
    assert ilines[k + 4].strip() == 'or ax,ax', ilines[k + 4]
    assert ilines[k + 5].strip() == 'jnz short L_02DA', ilines[k + 5]
    assert ilines[k + 6].strip() == 'jmp near ptr L_0433', ilines[k + 6]
    ilines[k + 4:k + 7] = ['        jmp near ptr L_0433',
                           '        db 090h', '        db 090h',
                           '        db 090h', '        db 090h']


def patch_sysicon(lines):
    """Route the system-menu Icon command for marked class-0 windows to
    ShowWindow(hwnd, SW_MINIMIZE).  Stock SYSCOMMAND ignores SC_ICON for
    class-0 windows, so the menu item previously did nothing."""
    i = find_label(lines, 'L_41B5')
    k = next(x for x in range(i, i + 50)
             if lines[x].strip() == 'cmp word ptr [bp-0Ah],0h')
    assert lines[k + 1].strip().startswith('jnz short ')
    assert lines[k + 2].strip().startswith('jmp near ptr ')
    lines[k:k + 3] = jmp_ret('SC_ICON_STUB', 9)


def patch_syscomm(lines):
    """Hook SYSCOMMAND's INITMOVESIZETILEDWND call for marked windows."""
    i = find_label(lines, 'SYSCOMMAND')
    k = next(x for x in range(i, len(lines))
             if 'export #424' in lines[x])
    assert lines[k + 1].strip() == 'cmp ds:[62h],si'
    lines[k:k + 2] = jmp_ret('SYSCOMMAND_SIZE_STUB', 9)


def patch_getstyle(lines):
    """Mask the overlap marker bit from GetWindowLong(GWL_STYLE)."""
    i = find_label(lines, 'GETWINDOWLONG')
    k = next(x for x in range(i, i + 100)
             if lines[x].strip() == 'mov ax,[bx+40h]')
    assert lines[k + 1].strip() == 'mov dx,[bx+42h]'
    lines[k:k + 2] = jmp_ret('GETWC2_STUB', 6)


def patch_setstyle(lines):
    """Preserve the overlap marker when SetWindowLong writes GWL_STYLE."""
    i = find_label(lines, 'SETWINDOWWORD')
    k = next(x for x in range(i, i + 200)
             if lines[x].strip() == 'mov dx,[bp+8h]')
    assert lines[k + 1].strip() == 'xchg dx,[bx+42h]'
    lines[k:k + 2] = jmp_ret('SETWC2_STUB', 6)


def patch_openwnd(lines):
    """Route icon-click OPENWND(hwnd, col, flag) for marked windows to
    SHOWWINDOW(hwnd,1), after OPENWNDPROLOG has run."""
    i = find_label(lines, 'OPENWND')
    k = next(x for x in range(i, i + 100)
             if lines[x].strip() == 'cmp word ptr ds:[18h],0h')
    assert lines[k + 1].strip().startswith('jnz short ')
    lines[k:k + 2] = jmp_ret('OPENWND_STUB', 7)
    # label the ds:[18h]==0 branch so the stub can jump straight to it
    j = next(x for x in range(k, k + 20)
             if lines[x].strip() == 'push si')
    if lines[j - 1].strip() != 'PATCH_0D49:':
        lines.insert(j, 'PATCH_0D49:')


def patch_iconhit(lines):
    """Route icon-area clicks to the icon area window.

    CHECKSYSQUEUE hit-tests the pointer and posts the mouse message to the
    window it finds.  With two minimized marked windows the first one stays
    hit-testable at its icon cell even though it is hidden and iconic, so the
    click is posted to the app window and the icon area never sees it.  The
    hit test is called through ICONHIT, which maps a point inside the icon
    area rect (and only then) to ds:[634h], the icon area window.
    """
    if RELEASE:
        k = find_label(lines, 'SITE_HITTEST_CALL') + 1
        assert lines[k].strip().startswith('call near ptr '), lines[k]
    else:
        i = find_label(lines, 'CHECKSYSQUEUE')
        k = next(x for x in range(i, i + 160)
                 if lines[x].strip() == 'call near ptr HITTEST')
    lines[k] = '        call near ptr ICONHIT'


def patch_edgehit(lines):
    """Modern edge/corner drag resize for marked class-0 windows.

    CHECKSYSQUEUE is the central system-queue dispatcher: every hardware
    mouse event is hit-tested here before it is posted to a window.  Route
    the hit test through EDGEHIT, which calls ICONHIT for the normal result,
    then turns a left-button-down within four pixels of a marked window's
    frame into a live resize drag instead of posting the click.

    This must run after patch_iconhit (EDGEHIT calls ICONHIT).
    """
    if RELEASE:
        k = find_label(lines, 'SITE_HITTEST_CALL') + 1
        assert lines[k].strip().startswith('call near ptr '), lines[k]
    else:
        i = find_label(lines, 'CHECKSYSQUEUE')
        k = next(x for x in range(i, i + 160)
                 if lines[x].strip() == 'call near ptr ICONHIT')
    lines[k] = '        call near ptr EDGEHIT'


def patch_captioncenter(lines):
    """Centre the caption text inside the caption fill, not the frame.

    DRAWCAPTION computes y as ([506h] - textHeight + 1) / 2 and draws at
    the window top + y.  [506h] includes the top frame, so with a larger
    System font the text is shifted up over the frame by half the frame
    height.  Add the frame height back before the shift: the stub does
    add [480h]; sub dx; inc ax, and the caller still does sar ax,1.
    """
    if RELEASE:
        k = find_label(lines, 'SITE_CAPTION_CENTER') + 1
        assert lines[k].strip() == 'sub ax,dx', lines[k]
        assert lines[k + 1].strip() == 'inc ax', lines[k + 1]
        lines[k:k + 2] = ['        call near ptr CAPTION_CENTER']
    else:
        i = find_label(lines, 'DRAWCAPTION')
        k = next(x for x in range(i, i + 400)
                 if lines[x].strip() == 'mov ax,ds:[506h]' and
                 lines[x + 1].strip() == 'sub ax,dx' and
                 lines[x + 2].strip() == 'inc ax')
        lines[k + 1:k + 3] = ['        call near ptr CAPTION_CENTER']


def patch_showtail(lines):
    """After PUTPOPUPWND, send WM_SIZE for marked class-0 windows.

    The original six bytes are push si / call PUTPOPUPWND / jmp L_0F14.
    The appended stub uses a near-ret chain so it can call low near
    helpers (PUTPOPUPWND, SENDSIZEMESSAGE) from the end of _TEXT.
    """
    i = next(x for x in range(len(lines))
             if lines[x].strip() == 'call near ptr PUTPOPUPWND' and
             lines[x + 1].strip() == 'jmp short L_0F14')
    assert lines[i - 1].strip() == 'push si'
    assert lines[i + 1].strip() == 'jmp short L_0F14'
    lines[i - 1:i + 2] = jmp_ret('SHOW_AFTER_PUTPOPUP_STUB', 6)


TRACE_ASM = r'''
        call near ptr SYSCOMMAND_SIZE_TRACE
'''

TRACE_STUB = r'''
SYSCOMMAND_SIZE_TRACE:
        push es
        push ax
        push bx
        mov bx,40h
        mov es,bx
        mov byte ptr es:[0FAh],0A5h
        mov al,[si+33h]
        mov es:[0F0h],al
        mov al,[si+42h]
        mov es:[0F1h],al
        mov ax,ds:[16h]
        mov es:[0F2h],ax
        mov ax,ds:[6Ah]
        mov es:[0F4h],ax
        mov ax,ds:[1BEh]
        mov es:[0F6h],ax
        mov ax,[bp-0Ch]
        mov es:[0F8h],ax
        pop bx
        pop ax
        pop es
        ret

OPENWND_TRACE:
        push es
        push ax
        push di
        push dx
        mov dx,40h
        mov es,dx
        mov di,0C0h
        mov es:[di],al
        mov ax,si
        mov es:[di+1],ax
        mov al,[si+33h]
        sub ah,ah
        mov es:[di+3],ax
        mov ax,[si+1Eh]
        mov es:[di+4],ax
        mov ax,[si+20h]
        mov es:[di+6],ax
        mov ax,[si+22h]
        mov es:[di+8],ax
        mov ax,[si+24h]
        mov es:[di+10],ax
        pop dx
        pop di
        pop ax
        pop es
        ret
SHOW_REST_TRACE:
        push es
        push ax
        push di
        push dx
        mov dx,40h
        mov es,dx
        mov di,0E0h
        mov es:[di],al
        mov ax,si
        mov es:[di+1],ax
        mov ax,[si+1Eh]
        mov es:[di+3],ax
        mov ax,[si+20h]
        mov es:[di+5],ax
        mov ax,[si+22h]
        mov es:[di+7],ax
        mov ax,[si+24h]
        mov es:[di+9],ax
        mov ax,cs:[bx+2]
        mov es:[di+11],ax
        mov ax,cs:[bx+4]
        mov es:[di+13],ax
        pop dx
        pop di
        pop ax
        pop es
        ret
'''

STUBS = r'''
CREATE_OVERLAP_STUB:
        mov word ptr [si+8h],0
        and byte ptr [si+33h],0EFh
        or byte ptr [si+33h],1
        mov word ptr [bp-1Ch],0C0h
        mov byte ptr [si+38h],0
        cmp word ptr [bp+12h],0
        jnz CREATE_OVERLAP_CX_OK
        cmp word ptr [bp+10h],0
        jnz CREATE_OVERLAP_FULL
        mov word ptr [bp+12h],1E0h
        mov word ptr [bp+10h],0FCh
        mov bx,word ptr cs:[CASCADE_N]
        inc word ptr cs:[CASCADE_N]
        and bx,3
        mov cl,3
        shl bx,cl
        cmp word ptr [bp-12h],0
        jnz CREATE_OVERLAP_SET_Y
        mov ax,bx
        add ax,50h
        mov [bp-12h],ax
CREATE_OVERLAP_SET_Y:
        cmp word ptr [bp-16h],0
        jnz CREATE_OVERLAP_CY_OK
        mov ax,bx
        add ax,28h
        mov [bp-16h],ax
        jmp CREATE_OVERLAP_CY_OK
CREATE_OVERLAP_FULL:
        mov word ptr [bp+12h],258h
        mov word ptr [bp+10h],136h
        jmp CREATE_OVERLAP_CY_OK
CREATE_OVERLAP_CX_OK:
        cmp word ptr [bp+10h],0
        jnz CREATE_OVERLAP_CY_OK
        mov word ptr [bp+10h],0FCh
CREATE_OVERLAP_CY_OK:
        mov ax,ds:[5BAh]
        mov [bp-4h],ax
        mov word ptr [bp-1Ah],2h
        push cs
        mov ax,offset L_0377
        push ax
        retf

SHOW_DISPATCH_STUB:
        test byte ptr [si+33h],1
        jnz SHOW_DISPATCH_MARKED
        mov al,[si+33h]
        and al,0C0h
        cmp al,80h
        jz SHOW_DISPATCH_POPUP
        push cs
        mov ax,offset L_0EFB
        push ax
        retf
SHOW_DISPATCH_MARKED:
        cmp di,2
        je SHOW_MINIMIZE_CHECK
        cmp di,6
        je SHOW_MINIMIZE_CHECK
        cmp di,7
        je SHOW_MINIMIZE_CHECK
        test byte ptr [si+33h],20h
        jz SHOW_MARKED_NOT_ICONIC
        cmp di,0
        je SHOW_RETURN_OLD
        jmp SHOW_RESTORE_STUB
SHOW_MARKED_NOT_ICONIC:
        cmp di,3
        je SHOW_FULLSCREEN
        cmp di,0
        je SHOW_DISPATCH_POPUP
        jmp SHOW_RESTORE_FULL_CHECK
SHOW_MINIMIZE_CHECK:
        test byte ptr [si+33h],20h
        jz SHOW_MIN_STUB
SHOW_RETURN_OLD:
        mov ax,[bp-6h]
        push cs
        mov ax,offset L_0F17
        push ax
        retf
SHOW_DISPATCH_POPUP:
        push cs
        mov ax,offset L_0E79
        push ax
        retf
SHOW_FULLSCREEN:
        mov bx,offset FULLSCREEN_RECTS
        mov cx,16
SHOW_FULLSCREEN_FIND:
        cmp word ptr cs:[bx],si
        je SHOW_FULLSCREEN_MOVE
        cmp word ptr cs:[bx],0
        je SHOW_FULLSCREEN_SAVE
        add bx,10
        loop SHOW_FULLSCREEN_FIND
        jmp SHOW_FULLSCREEN_MOVE
SHOW_FULLSCREEN_SAVE:
        mov cs:[bx],si
        mov ax,[si+1Eh]
        mov cs:[bx+2],ax
        mov ax,[si+20h]
        mov cs:[bx+4],ax
        mov ax,[si+22h]
        mov cs:[bx+6],ax
        mov ax,[si+24h]
        mov cs:[bx+8],ax
SHOW_FULLSCREEN_MOVE:
        push si
        sub ax,ax
        push ax
        push ax
        mov ax,ds:[18Eh]
        push ax
        mov ax,ds:[190h]
        push ax
        mov ax,offset SHOW_FULLSCREEN_DONE
        push ax
        mov ax,offset MOVEPOPUP
        push ax
        ret
SHOW_FULLSCREEN_DONE:
        push si
        mov ax,2
        push ax
        mov ax,offset SHOW_FULLSCREEN_AFTER_SIZE
        push ax
        mov ax,offset SENDSIZE
        push ax
        ret
SHOW_FULLSCREEN_AFTER_SIZE:
        push cs
        mov ax,offset L_0E79
        push ax
        retf

SHOW_RESTORE_FULL_CHECK:
        mov bx,offset FULLSCREEN_RECTS
        mov cx,16
SHOW_RESTORE_FULL_FIND:
        cmp word ptr cs:[bx],si
        je SHOW_RESTORE_FULL_FOUND
        cmp word ptr cs:[bx],0
        je SHOW_RESTORE_FULL_NONE
        add bx,10
        loop SHOW_RESTORE_FULL_FIND
        jmp SHOW_RESTORE_FULL_NONE
SHOW_RESTORE_FULL_FOUND:
        mov word ptr cs:[bx],0
        push si
        mov ax,cs:[bx+2]
        push ax
        mov ax,cs:[bx+4]
        push ax
        mov ax,cs:[bx+6]
        sub ax,cs:[bx+2]
        push ax
        mov ax,cs:[bx+8]
        sub ax,cs:[bx+4]
        push ax
        mov ax,offset SHOW_RESTORE_FULL_AFTER
        push ax
        mov ax,offset MOVEPOPUP
        push ax
        ret
SHOW_RESTORE_FULL_AFTER:
        jmp SHOW_DISPATCH_POPUP
SHOW_RESTORE_FULL_NONE:
        jmp SHOW_DISPATCH_POPUP

WMSIZE_STUB:
        test byte ptr [si+33h],1
        jnz WMSIZE_SKIP
        cmp word ptr [bp-1Ah],0h
        jz WMSIZE_SKIP
        push cs
        mov ax,offset PATCH_04DE
        push ax
        retf
WMSIZE_SKIP:
        push cs
        mov ax,offset L_04FF
        push ax
        retf

DESTROY_DISPATCH_STUB:
        test byte ptr [si+33h],1
        jnz DESTROY_DISPATCH_POPUP
        mov al,[si+33h]
        and al,0C0h
        cmp al,80h
        jnz DESTROY_DISPATCH_OTHER
DESTROY_DISPATCH_POPUP:
        push cs
        mov ax,offset PATCH_080E
        push ax
        retf
DESTROY_DISPATCH_OTHER:
        push cs
        mov ax,offset L_0814
        push ax
        retf

BRINGTOP_DISPATCH_STUB:
        test byte ptr [si+33h],1
        jnz BRINGTOP_DISPATCH_POPUP
        mov al,[si+33h]
        and al,0C0h
        cmp al,80h
        jnz BRINGTOP_DISPATCH_DONE
BRINGTOP_DISPATCH_POPUP:
        push cs
        mov ax,offset PATCH_2043
        push ax
        retf
BRINGTOP_DISPATCH_DONE:
        push cs
        mov ax,offset L_2049
        push ax
        retf

MOVEWIN_DISPATCH_STUB:
        test byte ptr [si+33h],1
        jnz MOVEWIN_DISPATCH_POPUP
        mov al,[si+33h]
        and al,0C0h
        cmp al,80h
        jnz MOVEWIN_DISPATCH_DONE
MOVEWIN_DISPATCH_POPUP:
        push cs
        mov ax,offset PATCH_2083
        push ax
        retf
MOVEWIN_DISPATCH_DONE:
        push cs
        mov ax,offset L_2093
        push ax
        retf

ACTIVATE_DISPATCH_STUB:
        test byte ptr [si+33h],1
        jnz ACTIVATE_DISPATCH_POPUP
        mov al,[si+33h]
        and al,0C0h
        cmp al,80h
        jnz ACTIVATE_DISPATCH_DONE
ACTIVATE_DISPATCH_POPUP:
        push cs
        mov ax,offset PATCH_3189
        push ax
        retf
ACTIVATE_DISPATCH_DONE:
        push cs
        mov ax,offset L_318F
        push ax
        retf

SHOW_AFTER_PUTPOPUP_STUB:
        test byte ptr [si+33h],1
        jz SHOW_AFTER_PUTPOPUP_NORMAL
        push si
        mov ax,1
        push ax
        mov ax,offset L_0F14
        push ax
        push si
        mov ax,offset COMPCLIENTRECT
        push ax
        mov ax,offset PUTPOPUPWND
        push ax
        ret
SHOW_AFTER_PUTPOPUP_NORMAL:
        push si
        mov ax,offset L_0F14
        push ax
        mov ax,offset PUTPOPUPWND
        push ax
        ret

ACTIVATE_TAIL_STUB:
        mov [bp-4h],ax
        mov word ptr ds:[3BAh],1h
        test byte ptr [si+33h],1
        jz ACTIVATE_TAIL_DONE
        push si
        push cs
        mov ax,offset ACTIVATE_TAIL_DONE
        push ax
        push cs
        mov ax,offset BRINGPOPUPTOTOP
        push ax
        retf
ACTIVATE_TAIL_DONE:
        mov ax,[bp-4h]
        ret

SC_ZOOM_STUB:
        test byte ptr [si+33h],1
        jz SC_ZOOM_ORIG
        mov bx,offset FULLSCREEN_RECTS
        mov cx,16
SC_ZOOM_FIND:
        cmp word ptr cs:[bx],si
        je SC_ZOOM_RESTORE
        cmp word ptr cs:[bx],0
        je SC_ZOOM_MAX
        add bx,10
        loop SC_ZOOM_FIND
        jmp SC_ZOOM_MAX
SC_ZOOM_RESTORE:
        mov ax,1
        jmp SC_ZOOM_CALL
SC_ZOOM_MAX:
        mov ax,3
SC_ZOOM_CALL:
        push si
        push ax
        push cs
        mov ax,offset SC_ZOOM_DONE
        push ax
        push cs
        mov ax,offset SHOWWINDOW
        push ax
        retf
SC_ZOOM_DONE:
        jmp L_4342
SC_ZOOM_ORIG:
        cmp word ptr [bp-0Ah],0h
        jz SC_ZOOM_DONE
        jmp L_420F

SC_ICON_STUB:
        test byte ptr [si+33h],1
        jz SC_ICON_ORIG
        test byte ptr [si+33h],20h
        jnz SC_ICON_DONE
        push si
        mov ax,2
        push ax
        push cs
        mov ax,offset SC_ICON_DONE
        push ax
        push cs
        mov ax,offset SHOWWINDOW
        push ax
        retf
SC_ICON_DONE:
        jmp L_4342
SC_ICON_ORIG:
        cmp word ptr [bp-0Ah],0h
        jz SC_ICON_DONE
        jmp L_41BE

ANYPOPUP_STUB:
        push si
        mov bx,ds:[5BAh]
        mov si,[bx+0Ch]
        xor cx,cx
ANYPOPUP_LOOP:
        or si,si
        jz ANYPOPUP_DONE
        test byte ptr [si+33h],1
        jnz ANYPOPUP_NEXT
        inc cx
ANYPOPUP_NEXT:
        mov si,[si]
        jmp ANYPOPUP_LOOP
ANYPOPUP_DONE:
        mov ax,cx
        pop si
        ret

SYSCOMMAND_SIZE_STUB:
        test byte ptr [si+33h],1
        jz SYSCOMMAND_SIZE_ORIG
        test byte ptr [si+33h],20h
        jnz SYSCOMMAND_SIZE_IGNORE
        cmp word ptr [bp-0Ch],0
        jz SYSCOMMAND_SIZE_ORIG
        test byte ptr [si+42h],4
        jz SYSCOMMAND_SIZE_IGNORE
        mov ax,word ptr [si+1Eh]
        mov word ptr cs:[EDGE_L0],ax
        mov ax,word ptr [si+20h]
        mov word ptr cs:[EDGE_T0],ax
        mov ax,word ptr [si+22h]
        mov word ptr cs:[EDGE_R0],ax
        mov ax,word ptr [si+24h]
        mov word ptr cs:[EDGE_B0],ax
        xor ax,ax
        mov word ptr cs:[EDGE_X0],ax
        mov word ptr cs:[EDGE_Y0],ax
        mov word ptr cs:[EDGE_HWND],si
        mov byte ptr cs:[EDGE_FLAGS],0Ah
        mov byte ptr cs:[EDGE_MOVED],0
        mov byte ptr cs:[EDGE_BUTTONS],0
        mov byte ptr cs:[EDGE_ORIGIN],0
        xor ax,ax
        mov word ptr cs:[EDGE_ADX],ax
        mov word ptr cs:[EDGE_ADY],ax
        mov byte ptr cs:[EDGE_ACTIVE],1
        ; The USER SETCURSOR export goes through the 86Box XT serial-mouse
        ; path and raises a DOS AUX critical error.  Resize without changing
        ; the cursor; the arrow is already active.
        jmp L_4342

SYSCOMMAND_SIZE_IGNORE:
        jmp L_4342
SYSCOMMAND_SIZE_ORIG:
        FARCALL 424, 0EEEEh
        cmp ds:[62h],si
        jnz SYSCOMMAND_SIZE_NOTACTIVE2
        jmp L_4342
SYSCOMMAND_SIZE_NOTACTIVE2:
        test byte ptr [si+33h],20h
        jnz L_4342
        jmp L_41E8
GETWC2_STUB:
        mov ax,[bx+40h]
        mov dx,[bx+42h]
        and dx,0FEFFh
GETWC2_STUB_NOMASK:
        push cs
        xchg ax,bx
        mov ax,offset L_6291
        push ax
        xchg ax,bx
        retf

SETWC2_STUB:
        mov dx,[bp+8h]
        cmp word ptr [bp+0Ah],-16
        jne SETWC2_STUB_NOMARK
        test byte ptr [bx+43h],1
        jz SETWC2_STUB_NOMARK
        or dx,0100h
SETWC2_STUB_NOMARK:
        xchg dx,[bx+42h]
        push cs
        xchg ax,bx
        mov ax,offset L_62E0
        push ax
        xchg ax,bx
        retf

OPENWND_STUB:
        test byte ptr [si+33h],1
        jz OPENWND_STUB_ORIG
        push si
        FARCALL 337, 0EEEEh
        FARCALL 336, 0EEEEh
        and byte ptr [si+33h],0DFh
        or byte ptr [si+33h],10h
        mov bx,offset SAVED_RECTS
        mov cx,16
OPENWND_FIND:
        cmp word ptr cs:[bx],si
        je OPENWND_FOUND
        add bx,10
        loop OPENWND_FIND
        jmp OPENWND_SHOW
OPENWND_FOUND:
        mov word ptr cs:[bx],0
        push si
        mov ax,cs:[bx+2]
        push ax
        mov ax,cs:[bx+4]
        push ax
        mov ax,cs:[bx+6]
        sub ax,cs:[bx+2]
        push ax
        mov ax,cs:[bx+8]
        sub ax,cs:[bx+4]
        push ax
        mov ax,offset OPENWND_AFTER_MOVE
        push ax
        mov ax,offset MOVEPOPUP
        push ax
        ret
OPENWND_AFTER_MOVE:
OPENWND_SHOW:
        push si
        mov ax,1
        push ax
        push cs
        mov ax,offset OPENWND_AFTER_SHOW
        push ax
        push cs
        mov ax,offset SHOWWINDOW
        push ax
        retf
OPENWND_AFTER_SHOW:
        ret
OPENWND_STUB_ORIG:
        cmp word ptr ds:[18h],0h
        jz OPENWND_STUB_BRANCH0
        push cs
        mov ax,offset L_0D54
        push ax
        retf
OPENWND_STUB_BRANCH0:
        push cs
        mov ax,offset PATCH_0D49
        push ax
        retf

SHOW_MIN_STUB:
        mov bx,offset SAVED_RECTS
        mov cx,16
SHOW_MIN_FIND:
        cmp word ptr cs:[bx],si
        je SHOW_MIN_FOUND
        cmp word ptr cs:[bx],0
        je SHOW_MIN_FOUND
        add bx,10
        loop SHOW_MIN_FIND
        jmp SHOW_RETURN_OLD
SHOW_MIN_FOUND:
        mov cs:[bx],si
        push bx
        push cx
        mov bx,offset FULLSCREEN_RECTS
        mov cx,16
SHOW_MIN_CLEAR_FULL:
        cmp word ptr cs:[bx],si
        je SHOW_MIN_CLEAR_FULL_HIT
        cmp word ptr cs:[bx],0
        je SHOW_MIN_CLEAR_FULL_DONE
        add bx,10
        loop SHOW_MIN_CLEAR_FULL
        jmp SHOW_MIN_CLEAR_FULL_DONE
SHOW_MIN_CLEAR_FULL_HIT:
        mov word ptr cs:[bx],0
SHOW_MIN_CLEAR_FULL_DONE:
        pop cx
        pop bx
        mov ax,[si+1Eh]
        mov cs:[bx+2],ax
        mov ax,[si+20h]
        mov cs:[bx+4],ax
        mov ax,[si+22h]
        mov cs:[bx+6],ax
        mov ax,[si+24h]
        mov cs:[bx+8],ax
        push si
        mov ax,offset SHOW_MIN_AFTER_UNLINK
        push ax
        mov ax,offset SHUTPOPUPWND
        push ax
        ret
SHOW_MIN_AFTER_UNLINK:
        FARCALL 331, 0EEEEh
        or byte ptr [si+33h],10h
        sub ax,ax
        push ax
        FARCALL 334, 0EEEEh
        push si
        FARCALL 338, 0EEEEh
        mov bx,offset ICON_RECTS
        mov cx,16
SHOW_MIN_ICON_SAVE:
        cmp word ptr cs:[bx],0
        je SHOW_MIN_ICON_SLOT
        add bx,10
        loop SHOW_MIN_ICON_SAVE
        jmp SHOW_MIN_ICON_DONE
SHOW_MIN_ICON_SLOT:
        mov cs:[bx],si
        mov ax,[si+1Eh]
        mov cs:[bx+2],ax
        mov ax,[si+20h]
        mov cs:[bx+4],ax
        mov ax,[si+22h]
        mov cs:[bx+6],ax
        mov ax,[si+24h]
        mov cs:[bx+8],ax
SHOW_MIN_ICON_DONE:
        jmp SHOW_RETURN_OLD

SHOW_RESTORE_STUB:
        push si
        FARCALL 337, 0EEEEh
        FARCALL 336, 0EEEEh
        and byte ptr [si+33h],0DFh
        or byte ptr [si+33h],10h
        mov bx,offset SAVED_RECTS
        mov cx,16
SHOW_REST_FIND:
        cmp word ptr cs:[bx],si
        je SHOW_REST_FOUND
        add bx,10
        loop SHOW_REST_FIND
        jmp SHOW_REST_NO_RECT
SHOW_REST_FOUND:
        push si
        mov ax,cs:[bx+2]
        push ax
        mov ax,cs:[bx+4]
        push ax
        mov ax,cs:[bx+6]
        sub ax,cs:[bx+2]
        push ax
        mov ax,cs:[bx+8]
        sub ax,cs:[bx+4]
        push ax
        mov ax,offset SHOW_REST_AFTER_MOVE
        push ax
        mov ax,offset MOVEPOPUP
        push ax
        ret
SHOW_REST_AFTER_MOVE:
SHOW_REST_NO_RECT:
        push si
        push word ptr ds:[5BAh]
        mov ax,offset SHOW_REST_AFTER_UNLINK
        push ax
        mov ax,offset UNLINKWND
        push ax
        ret
SHOW_REST_AFTER_UNLINK:
        push si
        push word ptr ds:[5BAh]
        sub ax,ax
        push ax
        mov ax,offset SHOW_REST_AFTER_LINK
        push ax
        mov ax,offset LINKWND
        push ax
        ret
SHOW_REST_AFTER_LINK:
        push si
        mov ax,1
        push ax
        FARCALL 408, 0EEEEh
        push si
        mov ax,offset SHOW_REST_AFTER_PUT
        push ax
        mov ax,offset PUTPOPUPWND
        push ax
        ret
SHOW_REST_AFTER_PUT:
        push si
        mov ax,1
        push ax
        mov ax,offset SHOW_REST_DONE
        push ax
        mov ax,offset COMPCLIENTRECT
        push ax
        ret
SHOW_REST_DONE:
        mov ax,[bp-6h]
        push cs
        mov ax,offset L_0F17
        push ax
        retf

ICON_CLICK:
        push bp
        mov bp,sp
        push si
        push di
        push bx
        push cx
        mov bx,offset ICON_RECTS
        mov cx,16
ICON_CLICK_LOOP:
        mov si,cs:[bx]
        or si,si
        jz ICON_CLICK_NONE
        mov ax,[bp+6h]
        cmp ax,cs:[bx+2]
        jl ICON_CLICK_NEXT
        cmp ax,cs:[bx+6]
        jge ICON_CLICK_NEXT
        mov ax,[bp+8h]
        cmp ax,cs:[bx+4]
        jl ICON_CLICK_NEXT
        cmp ax,cs:[bx+8]
        jge ICON_CLICK_NEXT
        mov word ptr cs:[bx],0
        push si
        mov ax,1
        push ax
        push ax
        FARCALL 395, 0EEEEh
        mov ax,1
        jmp ICON_CLICK_OUT
ICON_CLICK_NEXT:
        add bx,10
        loop ICON_CLICK_LOOP
ICON_CLICK_NONE:
        sub ax,ax
ICON_CLICK_OUT:
        pop cx
        pop bx
        pop di
        pop si
        pop bp
        retf 4

SAVED_RECTS:
        db 160 dup(0)
FULLSCREEN_RECTS:
        db 160 dup(0)
CASCADE_N:
        dw 0
ICON_RECTS:
        db 160 dup(0)


ICONHIT:
        push bp
        mov bp,sp
        push bx
        push cx
        push dx
        push si
        push word ptr [bp+8h]
        push word ptr [bp+6h]
        push word ptr [bp+4h]
        call near ptr HITTEST
        mov si,ax
        or si,si
        jz ICONHIT_DONE
        mov bx,offset ICON_RECTS
        mov cx,16
ICONHIT_SCAN:
        cmp word ptr cs:[bx],si
        je ICONHIT_HIT
        add bx,10
        loop ICONHIT_SCAN
        jmp ICONHIT_DONE
ICONHIT_HIT:
        test byte ptr [si+33h],20h
        jz ICONHIT_DONE
        mov bx,ds:[634h]
        or bx,bx
        jz ICONHIT_DONE
        mov si,bx
ICONHIT_DONE:
        mov ax,si
        pop si
        pop dx
        pop cx
        pop bx
        pop bp
        ret 6h

ICON_RECTS_CLEAR:
        push bx
        push cx
        mov bx,offset ICON_RECTS
        mov cx,16
ICON_RECTS_CLEAR_LOOP:
        cmp word ptr cs:[bx],si
        jne ICON_RECTS_CLEAR_NEXT
        mov word ptr cs:[bx],0h
        jmp ICON_RECTS_CLEAR_DONE
ICON_RECTS_CLEAR_NEXT:
        add bx,10
        loop ICON_RECTS_CLEAR_LOOP
ICON_RECTS_CLEAR_DONE:
        pop cx
        pop bx
        ret

CAPTION_CENTER:
        add ax,ds:[480h]
        sub ax,dx
        inc ax
        ret

EDGE_DATA:
EDGE_L0:
        dw 0
EDGE_T0:
        dw 0
EDGE_R0:
        dw 0
EDGE_B0:
        dw 0
EDGE_L:
        dw 0
EDGE_T:
        dw 0
EDGE_R:
        dw 0
EDGE_B:
        dw 0
EDGE_W:
        dw 0
EDGE_H:
        dw 0
EDGE_X0:
        dw 0
EDGE_Y0:
        dw 0
EDGE_DX:
        dw 0
EDGE_DY:
        dw 0
EDGE_ADX:
        dw 0
EDGE_ADY:
        dw 0
EDGE_FLAGS:
        db 0
EDGE_HITWND:
        dw 0
EDGE_HWND:
        dw 0
EDGE_ACTIVE:
        db 0
EDGE_ORIGIN:
        db 0
EDGE_MOVED:
        db 0
EDGE_BUTTONS:
        db 0
EDGE_POINT:
        dw 0
        dw 0

EDGEHIT:
        push bp
        mov bp,sp
        push bx
        push cx
        push dx
        push si
        push di

        cmp byte ptr cs:[EDGE_ACTIVE],0
        je EDGE_NEW
        mov ax,word ptr [bp+4h]
        cmp ax,200h
        jb EDGE_ACTIVE_PASS
        cmp ax,208h
        ja EDGE_ACTIVE_PASS
        cmp ax,202h
        je EDGE_DONE
        ; Do not poll INT 33h here.  The 86Box XT serial mouse driver
        ; raises a DOS AUX critical error for the button-state query; the
        ; WM_LBUTTONUP message is the normal end of the drag.
        ; A Size command from the system menu has no button-down position.
        ; Ignore its menu-close moves; wait for a real left-button-down and
        ; use that position as the drag origin.  Otherwise the menu-close
        ; coordinates feed MOVEPOPUP a huge rectangle and the 86Box mouse
        ; driver raises the DOS AUX error.
        cmp byte ptr cs:[EDGE_BUTTONS],0
        jne EDGE_HAVE_ORIGIN
        cmp ax,201h
        jne EDGE_SWALLOW
        mov byte ptr cs:[EDGE_BUTTONS],1
        mov ax,word ptr [bp+6h]
        mov word ptr cs:[EDGE_X0],ax
        mov ax,word ptr [bp+8h]
        mov word ptr cs:[EDGE_Y0],ax
EDGE_HAVE_ORIGIN:
        call near ptr EDGE_APPLY
        sub ax,ax
        jmp EDGE_EXIT
EDGE_SWALLOW:
        sub ax,ax
        jmp EDGE_EXIT
        sub ax,ax
        jmp EDGE_EXIT
EDGE_ACTIVE_PASS:
        jmp EDGE_NEW
EDGE_NEW:
        push word ptr [bp+8h]
        push word ptr [bp+6h]
        push word ptr [bp+4h]
        call near ptr ICONHIT
        mov si,ax
        mov word ptr cs:[EDGE_HITWND],si


        ; only a left-button-down starts a resize
        cmp word ptr [bp+4h],201h
        jne EDGE_WND
        ; Do not gate on ds:[66h] or ds:[6Ah].  The 86Box XT serial-mouse
        ; path leaves ds:[66h] in the menu-tracking state after a failed
        ; system-menu Size, so the next corner drag was ignored.  The hit
        ; test below already requires the pointer to be within the marked
        ; window's frame or grow box, which a menu click is not.

        or si,si
        jz EDGE_SCAN
        ; The hit test recurses into child windows.  Walk the parent chain
        ; to the marked top-level window whose frame the pointer is near.
        mov cx,8
EDGE_ROOT_LOOP:
        test byte ptr [si+33h],1
        jnz EDGE_ROOT_OK
        test byte ptr [si+33h],0C0h
        jz EDGE_SCAN
        mov bx,[si+38h]
        or bx,bx
        jz EDGE_SCAN
        mov si,bx
        loop EDGE_ROOT_LOOP
        jmp EDGE_SCAN

        ; No hit, or no marked ancestor: the rounded frame corners and the
        ; scrollbar ends lie outside the hit-test rect.  Look through the
        ; popup z-order for a marked window whose inner rect is within six
        ; pixels of the pointer.  The painted border/grow box sits outside
        ; that rect, so the tolerance must match the edge test below.
EDGE_SCAN:
        mov bx,ds:[5BAh]
        mov si,[bx+0Ch]
EDGE_SCAN_LOOP:
        or si,si
        jz EDGE_WND
        test byte ptr [si+33h],1
        jz EDGE_SCAN_NEXT
        test byte ptr [si+33h],20h
        jnz EDGE_SCAN_NEXT
        test byte ptr [si+33h],10h
        jz EDGE_SCAN_NEXT
        mov ax,[si+1Eh]
        sub ax,6
        cmp word ptr [bp+6h],ax
        jl EDGE_SCAN_NEXT
        mov ax,[si+22h]
        add ax,6
        cmp word ptr [bp+6h],ax
        jg EDGE_SCAN_NEXT
        mov ax,[si+20h]
        sub ax,6
        cmp word ptr [bp+8h],ax
        jl EDGE_SCAN_NEXT
        mov ax,[si+24h]
        add ax,6
        cmp word ptr [bp+8h],ax
        jg EDGE_SCAN_NEXT
        jmp EDGE_ROOT_OK
EDGE_SCAN_NEXT:
        mov si,[si]
        jmp EDGE_SCAN_LOOP

EDGE_ROOT_OK:
        test byte ptr [si+33h],20h
        jnz EDGE_WND
        test byte ptr [si+33h],10h
        jz EDGE_WND

        mov bx,si
        mov ax,[bx+1Eh]
        mov word ptr cs:[EDGE_L0],ax
        mov ax,[bx+20h]
        mov word ptr cs:[EDGE_T0],ax
        mov ax,[bx+22h]
        mov word ptr cs:[EDGE_R0],ax
        mov ax,[bx+24h]
        mov word ptr cs:[EDGE_B0],ax

        mov cx,[bp+6h]
        mov dx,[bp+8h]
        ; The object's rect is the inner/client rect; the visible frame and
        ; grow box extend a few pixels outside it.  Accept points up to six
        ; pixels outside so a drag on the painted border is not rejected.
        mov bx,word ptr cs:[EDGE_L0]
        sub bx,6
        cmp cx,bx
        jl EDGE_WND
        mov bx,word ptr cs:[EDGE_R0]
        add bx,6
        cmp cx,bx
        jg EDGE_WND
        mov bx,word ptr cs:[EDGE_T0]
        sub bx,6
        cmp dx,bx
        jl EDGE_WND
        mov bx,word ptr cs:[EDGE_B0]
        add bx,6
        cmp dx,bx
        jg EDGE_WND

        xor al,al
        mov bx,word ptr cs:[EDGE_L0]
        add bx,6
        cmp cx,bx
        ja EDGE_NO_LEFT
        or al,1
EDGE_NO_LEFT:
        mov bx,word ptr cs:[EDGE_R0]
        sub bx,6
        cmp cx,bx
        jb EDGE_NO_RIGHT
        or al,2
EDGE_NO_RIGHT:
        mov bx,word ptr cs:[EDGE_T0]
        add bx,6
        cmp dx,bx
        ja EDGE_NO_TOP
        or al,4
EDGE_NO_TOP:
        mov bx,word ptr cs:[EDGE_B0]
        sub bx,6
        cmp dx,bx
        jb EDGE_NO_BOTTOM
        or al,8
EDGE_NO_BOTTOM:
        ; Grow box: the Win1 size icon is the small square in the
        ; bottom-right.  It may be a frame HTGROWBOX (4) or an app-drawn
        ; client gadget, so accept either the hit code or a 16x16 corner.
        cmp word ptr ds:[63Ch],4
        je EDGE_GROWBOX_SET
        mov bx,word ptr cs:[EDGE_R0]
        sub bx,16
        cmp cx,bx
        jb EDGE_NO_GROWBOX
        mov bx,word ptr cs:[EDGE_B0]
        sub bx,16
        cmp dx,bx
        jb EDGE_NO_GROWBOX
EDGE_GROWBOX_SET:
        or al,0Ah
EDGE_NO_GROWBOX:
        or al,al
        jz EDGE_WND
        mov byte ptr cs:[EDGE_FLAGS],al
        mov byte ptr cs:[EDGE_MOVED],0

        ; raise the window in the popup z-order before resizing.  Do not
        ; call BRINGPOPUPTOTOP here: its ACTIVATEWINDOW tail runs a model
        ; loop and hangs when entered from CHECKSYSQUEUE.
        call near ptr INVALIDATEALLDCS
        push si
        push word ptr ds:[5BAh]
        call near ptr UNLINKWND
        push si
        push word ptr ds:[5BAh]
        sub ax,ax
        push ax
        call near ptr LINKWND
        push si
        call near ptr ONEWNDREPAINT
        call near ptr CALCALLVISRGNS

        ; No SETCURSOR here: see SYSCOMMAND_SIZE_STUB.  The 86Box XT
        ; serial-mouse SETCURSOR path raises the DOS AUX error.

        mov ax,word ptr [bp+6h]
        mov word ptr cs:[EDGE_X0],ax
        mov ax,word ptr [bp+8h]
        mov word ptr cs:[EDGE_Y0],ax
        mov word ptr cs:[EDGE_HWND],si
        xor ax,ax
        mov word ptr cs:[EDGE_ADX],ax
        mov word ptr cs:[EDGE_ADY],ax
        mov byte ptr cs:[EDGE_ORIGIN],1
        mov byte ptr cs:[EDGE_BUTTONS],1
        mov byte ptr cs:[EDGE_ACTIVE],1
        sub ax,ax
        jmp EDGE_EXIT

EDGE_APPLY:
        mov si,word ptr cs:[EDGE_HWND]
        mov ax,word ptr [bp+6h]
        sub ax,word ptr cs:[EDGE_X0]
        mov word ptr cs:[EDGE_DX],ax
        mov ax,word ptr [bp+8h]
        sub ax,word ptr cs:[EDGE_Y0]
        mov word ptr cs:[EDGE_DY],ax
        mov ax,word ptr cs:[EDGE_DX]
        cmp ax,word ptr cs:[EDGE_ADX]
        jne EDGE_APPLY_MOVE
        mov ax,word ptr cs:[EDGE_DY]
        cmp ax,word ptr cs:[EDGE_ADY]
        je EDGE_APPLY_RET
EDGE_APPLY_MOVE:
        jmp EDGE_MOVE
EDGE_APPLY_RET:
        ret

EDGE_MOVE:
        mov byte ptr cs:[EDGE_MOVED],1
        mov ax,word ptr cs:[EDGE_L0]
        mov word ptr cs:[EDGE_L],ax
        mov ax,word ptr cs:[EDGE_T0]
        mov word ptr cs:[EDGE_T],ax
        mov ax,word ptr cs:[EDGE_R0]
        mov word ptr cs:[EDGE_R],ax
        mov ax,word ptr cs:[EDGE_B0]
        mov word ptr cs:[EDGE_B],ax

        mov al,byte ptr cs:[EDGE_FLAGS]
        test al,1
        jz EDGE_M_NL
        mov bx,word ptr cs:[EDGE_DX]
        add word ptr cs:[EDGE_L],bx
EDGE_M_NL:
        test al,2
        jz EDGE_M_NR
        mov bx,word ptr cs:[EDGE_DX]
        add word ptr cs:[EDGE_R],bx
EDGE_M_NR:
        test al,4
        jz EDGE_M_NT
        mov bx,word ptr cs:[EDGE_DY]
        add word ptr cs:[EDGE_T],bx
EDGE_M_NT:
        test al,8
        jz EDGE_M_NB
        mov bx,word ptr cs:[EDGE_DY]
        add word ptr cs:[EDGE_B],bx
EDGE_M_NB:

        mov ax,word ptr cs:[EDGE_L]
        or ax,ax
        jns EDGE_CL
        sub ax,ax
        mov word ptr cs:[EDGE_L],ax
EDGE_CL:
        mov ax,word ptr cs:[EDGE_T]
        or ax,ax
        jns EDGE_CT
        sub ax,ax
        mov word ptr cs:[EDGE_T],ax
EDGE_CT:

        test byte ptr cs:[EDGE_FLAGS],3
        jz EDGE_HMIN_DONE
        mov bx,ds:[462h]
        mov ax,word ptr cs:[EDGE_R]
        sub ax,word ptr cs:[EDGE_L]
        cmp ax,bx
        jge EDGE_HMIN_DONE
        test byte ptr cs:[EDGE_FLAGS],1
        jz EDGE_HMIN_RIGHT
        mov ax,word ptr cs:[EDGE_R]
        sub ax,bx
        mov word ptr cs:[EDGE_L],ax
        or ax,ax
        jns EDGE_HMIN_DONE
        sub ax,ax
        mov word ptr cs:[EDGE_L],ax
        mov ax,bx
        mov word ptr cs:[EDGE_R],ax
        jmp EDGE_HMIN_DONE
EDGE_HMIN_RIGHT:
        mov ax,word ptr cs:[EDGE_L]
        add ax,bx
        mov word ptr cs:[EDGE_R],ax
EDGE_HMIN_DONE:

        test byte ptr cs:[EDGE_FLAGS],0Ch
        jz EDGE_HMAX_DONE
        mov bx,ds:[464h]
        mov ax,word ptr cs:[EDGE_B]
        sub ax,word ptr cs:[EDGE_T]
        cmp ax,bx
        jge EDGE_HMAX_DONE
        test byte ptr cs:[EDGE_FLAGS],4
        jz EDGE_HMAX_BOTTOM
        mov ax,word ptr cs:[EDGE_B]
        sub ax,bx
        mov word ptr cs:[EDGE_T],ax
        or ax,ax
        jns EDGE_HMAX_DONE
        sub ax,ax
        mov word ptr cs:[EDGE_T],ax
        mov ax,bx
        mov word ptr cs:[EDGE_B],ax
        jmp EDGE_HMAX_DONE
EDGE_HMAX_BOTTOM:
        mov ax,word ptr cs:[EDGE_T]
        add ax,bx
        mov word ptr cs:[EDGE_B],ax
EDGE_HMAX_DONE:

        mov ax,word ptr cs:[EDGE_R]
        sub ax,word ptr cs:[EDGE_L]
        mov word ptr cs:[EDGE_W],ax
        mov ax,word ptr cs:[EDGE_B]
        sub ax,word ptr cs:[EDGE_T]
        mov word ptr cs:[EDGE_H],ax

        mov ax,word ptr cs:[EDGE_DX]
        mov word ptr cs:[EDGE_ADX],ax
        mov ax,word ptr cs:[EDGE_DY]
        mov word ptr cs:[EDGE_ADY],ax

        push si
        mov ax,word ptr cs:[EDGE_L]
        push ax
        mov ax,word ptr cs:[EDGE_T]
        push ax
        mov ax,word ptr cs:[EDGE_W]
        push ax
        mov ax,word ptr cs:[EDGE_H]
        push ax
        mov ax,offset EDGE_AFTER_MOVE
        push ax
        mov ax,offset MOVEPOPUP
        push ax
        ret
EDGE_AFTER_MOVE:
        ret

EDGE_DONE:
        mov byte ptr cs:[EDGE_ORIGIN],0
        cmp byte ptr cs:[EDGE_MOVED],0
        je EDGE_DONE_NOSIZE
        push word ptr cs:[EDGE_HWND]
        call near ptr SENDSIZEMESSAGE
EDGE_DONE_NOSIZE:
        mov byte ptr cs:[EDGE_ACTIVE],0
        sub ax,ax
        jmp EDGE_EXIT
EDGE_WND:
        mov ax,word ptr cs:[EDGE_HITWND]
        jmp EDGE_EXIT
EDGE_ZERO:
        sub ax,ax
EDGE_EXIT:
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop bp
        ret 6h
'''.splitlines()


def add_far_relocs(path):
    """Turn FARCALL <ordinal>, 0EEEEh markers into NE type-3 relocs.

    The generated _TEXT.asm defines FARCALL as db 9Ah; dw off; dw seg.
    We use seg=0EEEEh as a marker and put the export ordinal in off.
    The loader overwrites both words, but the off word must first be the
    FFFFh end-of-chain marker.
    """
    data = bytearray(open(path, 'rb').read())
    added = []
    pos = 0
    while True:
        i = data.find(b'\x9a', pos)
        if i < 0:
            break
        if i + 5 <= len(data) and data[i + 3:i + 5] == b'\xee\xee':
            ordv = int.from_bytes(data[i + 1:i + 3], 'little')
            if ordv:
                added.append({'type': 3, 'flags': 0, 'offset': i + 1,
                              'target_segment': 255,
                              'target_offset': ordv})
                data[i + 1:i + 3] = b'\xff\xff'
        pos = i + 1
    if added:
        open(path, 'wb').write(data)
    return added


def main():
    global STUBS
    shutil.rmtree(OUT, ignore_errors=True)
    shutil.copytree(BASE, OUT)
    text_path = os.path.join(OUT, 'generated/USER/_TEXT.asm')
    tile_path = os.path.join(OUT, 'generated/USER/_TILE.asm')
    lines = open(text_path, errors='replace').read().splitlines()

    # Release source: labels from the DEBUG .SYM are at DEBUG offsets (and
    # some are missing).  Put REL_ aliases at the mapped RELEASE lines and
    # translate the labels referenced by the appended chunks.
    CHUNK_DEFS.clear()
    for _l in STUBS:
        _m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):', _l)
        if _m:
            CHUNK_DEFS.add(_m.group(1))
    if RELEASE:
        insert_release_aliases(lines)
        STUBS = [translate_release_labels(_l) for _l in STUBS]

    if 'create' in PATCHES:
        patch_create(lines)
    if 'show' in PATCHES:
        patch_show(lines)
    if 'openwnd' in PATCHES:
        patch_openwnd(lines)
    if 'getstyle' in PATCHES:
        patch_getstyle(lines)
    if 'resize' in PATCHES:
        patch_syscomm(lines)
    if 'anypopup' in PATCHES:
        patch_anypopup(lines)
    if 'norest' in PATCHES:
        j = STUBS.index('SHOW_RESTORE_STUB:')
        STUBS.insert(j + 1, '        jmp near ptr SHOW_REST_NO_RECT')
    if 'iconopen' in PATCHES:
        icon_path = os.path.join(OUT, 'generated/USER/_ICON.asm')
        ilines = open(icon_path, errors='replace').read().splitlines()
        patch_icon_open(ilines)
        open(icon_path, 'w').write('\n'.join(ilines) + '\n')
        imp = os.path.join(OUT, 'meta/USER.json')
        im = json.load(open(imp))
        for seg in im['segments']:
            if seg['index'] != 9:
                continue
            for r in seg['relocs']:
                if r['target_segment'] == 1 and r['target_offset'] == 0x2FA7:
                    r['target_segment'] = 255
                    r['target_offset'] = 42
        json.dump(im, open(imp, 'w'), indent=1)
    if 'sysicon' in PATCHES:
        patch_sysicon(lines)
    if 'syszoom' in PATCHES:
        patch_syszoom(lines)
    if 'setstyle' in PATCHES:
        patch_setstyle(lines)
    if 'iconhit' in PATCHES:
        patch_iconhit(lines)
    if 'edgehit' in PATCHES:
        patch_edgehit(lines)
    if 'captioncenter' in PATCHES:
        patch_captioncenter(lines)
    if 'showtail' in PATCHES:
        patch_showtail(lines)
    if 'wmsize' in PATCHES:
        patch_wmsize(lines)
    if 'destroy' in PATCHES:
        patch_destroy(lines)
    if 'bringtop' in PATCHES:
        patch_bringtop(lines)
    if 'movewin' in PATCHES:
        patch_movewin(lines)
    if 'activate' in PATCHES:
        patch_activate(lines)
    if 'activatetail' in PATCHES:
        patch_activatetail(lines)
    if 'close' in PATCHES:
        patch_close(lines)

    if 'tilmove' in PATCHES:
        tlines = open(tile_path, errors='replace').read().splitlines()
        i = find_label(tlines, 'INITMOVESIZETILEDWND')
        k = next(x for x in range(i, i + 40)
                 if tlines[x].strip() == 'test byte ptr [si+33h],0C0h')
        tlines[k] = '        test byte ptr [si+33h],0C1h'
        open(tile_path, 'w').write('\n'.join(tlines) + '\n')

    if 'trace' in PATCHES:
        for lab, tag in (('SYSCOMMAND_SIZE_STUB:', '0A5h'),
                         ('OPENWND_STUB:', '55h'),
                         ('SHOW_REST_FOUND:', '52h')):
            idx = STUBS.index(lab)
            STUBS[idx + 1:idx + 1] = ['        mov al,' + tag,
                                      '        call near ptr ' +
                                      {'0A5h': 'SYSCOMMAND_SIZE_TRACE',
                                       '55h': 'OPENWND_TRACE',
                                       '52h': 'SHOW_REST_TRACE'}[tag]]
        idx = STUBS.index('SHOW_REST_NO_RECT:')
        STUBS[idx + 1:idx + 1] = ['        sub ax,ax', '        mov bx,ax',
                                  '        mov al,53h',
                                  '        call near ptr SHOW_REST_TRACE']
        STUBS.extend(TRACE_STUB.splitlines())
        top_extra = ('SYSCOMMAND_SIZE_TRACE', 'OPENWND_TRACE', 'SHOW_REST_TRACE')
    else:
        top_extra = ()
    top = ('CREATE_OVERLAP_STUB', 'SHOW_DISPATCH_STUB', 'WMSIZE_STUB',
           'DESTROY_DISPATCH_STUB', 'BRINGTOP_DISPATCH_STUB',
           'MOVEWIN_DISPATCH_STUB', 'ACTIVATE_DISPATCH_STUB',
           'SHOW_AFTER_PUTPOPUP_STUB', 'ACTIVATE_TAIL_STUB',
           'SHOW_MIN_STUB', 'SHOW_RESTORE_STUB', 'OPENWND_STUB', 'GETWC2_STUB', 'SETWC2_STUB',
           'SYSCOMMAND_SIZE_STUB', 'ANYPOPUP_STUB', 'SC_ICON_STUB', 'SC_ZOOM_STUB',
           'ICONHIT', 'EDGE_DATA', 'EDGEHIT', 'CAPTION_CENTER') + top_extra
    chunks = {}
    cur = None
    for l in STUBS:
        t = l.strip()
        if t.endswith(':') and t[:-1] in top:
            cur = t[:-1]
            chunks[cur] = [l]
        elif cur:
            chunks[cur].append(l)
    use = {'CREATE_OVERLAP_STUB': 'create',
           'SHOW_DISPATCH_STUB': 'show',
           'WMSIZE_STUB': 'wmsize',
           'DESTROY_DISPATCH_STUB': 'destroy',
           'BRINGTOP_DISPATCH_STUB': 'bringtop',
           'MOVEWIN_DISPATCH_STUB': 'movewin',
           'ACTIVATE_DISPATCH_STUB': 'activate',
           'SHOW_AFTER_PUTPOPUP_STUB': 'showtail',
           'ACTIVATE_TAIL_STUB': 'activatetail',
           'SHOW_MIN_STUB': 'show',
           'SHOW_RESTORE_STUB': 'show',
           'OPENWND_STUB': 'openwnd',
           'GETWC2_STUB': 'getstyle',
           'SETWC2_STUB': 'setstyle',
           'SYSCOMMAND_SIZE_STUB': 'resize',
           'ANYPOPUP_STUB': 'anypopup',
           'SC_ICON_STUB': 'sysicon',
           'SC_ZOOM_STUB': 'syszoom',
           'ICONHIT': 'iconhit',
           'EDGE_DATA': 'edgehit',
           'EDGEHIT': 'edgehit',
           'CAPTION_CENTER': 'captioncenter',
           'SYSCOMMAND_SIZE_TRACE': 'trace',
           'OPENWND_TRACE': 'trace',
           'SHOW_REST_TRACE': 'trace'}
    if 'iconhit' in PATCHES:
        ch = chunks['SHOW_RESTORE_STUB']
        k = next(i for i, l in enumerate(ch)
                 if l.strip() == 'or byte ptr [si+33h],10h')
        ch[k + 1:k + 1] = ['        push si',
                           '        call near ptr ICON_RECTS_CLEAR']
    end = max(i for i, l in enumerate(lines) if l.strip() == 'end')
    add = []
    for label in top:
        if use[label] in PATCHES:
            add.extend(chunks.get(label, []))
    lines[end:end] = add
    open(text_path, 'w').write('\n'.join(lines) + '\n')

    check = os.path.join(OUT, 'check.bin')
    lst = os.path.join(OUT, 'check.lst')
    run([JWASM, '-nologo', '-bin', '-Fl=' + lst, '-Fo=' + check, text_path])
    newlen = len(open(check, 'rb').read())
    added = add_far_relocs(check)
    if added:
        print('added far relocs', added)
    if 'resize' in PATCHES:
        drop_off = (SITES['SITE_SYSCOMM_RELOC']['release']
                    if RELEASE else 0x4288)
        drop = [(drop_off, drop_off + 1)]
    else:
        drop = None
    shift = grow.relayout(os.path.join(OUT, 'meta'), 'USER', 1, newlen,
                          added_relocs=added, drop_ranges=drop)
    mp = os.path.join(OUT, 'meta/USER.json')
    m = json.load(open(mp))
    hs = bytearray(base64.b64decode(m['header_suffix']))
    for o in (0x0A, 0x1E, 0x2A, 0x3E, 0x52):
        v = struct.unpack_from('<H', hs, o)[0]
        struct.pack_into('<H', hs, o, v + (shift >> 4))
    m['header_suffix'] = base64.b64encode(bytes(hs)).decode('ascii')
    open(mp, 'w').write(json.dumps(m, indent=1) + '\n')
    if 'iconfix' in PATCHES:
        icon_off = None
        for l in open(lst, errors='replace'):
            t = l.split()
            if len(t) >= 2 and t[-1] == 'ICON_CLICK:':
                icon_off = int(t[0], 16)
                break
        if icon_off is None:
            raise SystemExit('ICON_CLICK label not found in the listing')
        print('ICON_CLICK at _TEXT+%04X' % icon_off)
        ip = os.path.join(OUT, 'generated/USER/_ICON.asm')
        il = open(ip, errors='replace').read().splitlines()
        k = next(i for i, l in enumerate(il)
                 if l.strip() == 'mov si,[bp+0Eh]')
        il[k] = '        jmp near ptr ICON_DBL_STUB'
        il[k + 1:k + 1] = ['ICON_DBL_RET:']
        e = max(i for i, l in enumerate(il) if l.strip() == 'end')
        il[e:e] = [
            'ICON_DBL_STUB:',
            '        mov si,[bp+0Eh]',
            '        cmp word ptr [bp+0Ch],203h',
            '        jne ICON_DBL_NORMAL',
            '        push word ptr [bp+6h]',
            '        push word ptr [bp+8h]',
            '        FARCALL 01234h, 0EEEEh  ; far call ICON_CLICK in _TEXT',
            '        or ax,ax',
            '        jz ICON_DBL_NORMAL',
            '        jmp near ptr L_0433',
            'ICON_DBL_NORMAL:',
            '        jmp near ptr ICON_DBL_RET',
            '',
        ]
        open(ip, 'w').write('\n'.join(il) + '\n')
        ci = os.path.join(OUT, 'check_icon.bin')
        run([JWASM, '-nologo', '-bin', '-Fo=' + ci, ip])
        idata = bytearray(open(ci, 'rb').read())
        marker = b'\x9a\x34\x12\xee\xee'
        at = idata.find(marker)
        if at < 0:
            raise SystemExit('icon stub far-call marker not found')
        oper = at + 1
        idata[oper:oper + 2] = b'\xff\xff'
        open(ci, 'wb').write(idata)
        irel = [{'type': 3, 'flags': 0, 'offset': oper,
                 'target_segment': 1, 'target_offset': icon_off}]
        ishift = grow.relayout(os.path.join(OUT, 'meta'), 'USER', 9,
                               len(idata), added_relocs=irel)
        print('grew _ICON to', len(idata), 'file shift', ishift)
        im2 = json.load(open(os.path.join(OUT, 'meta/USER.json')))
        hs2 = bytearray(base64.b64decode(im2['header_suffix']))
        for o in (0x0A, 0x1E, 0x2A, 0x3E, 0x52):
            v = struct.unpack_from('<H', hs2, o)[0]
            struct.pack_into('<H', hs2, o, v + (ishift >> 4))
        im2['header_suffix'] = base64.b64encode(bytes(hs2)).decode('ascii')
        json.dump(im2, open(os.path.join(OUT, 'meta/USER.json'), 'w'), indent=1)
        os.makedirs(os.path.join(OUT, 'tmp'), exist_ok=True)
        json.dump({str(oper): 0xffff},
                  open(os.path.join(OUT, 'tmp/USER_09.patch.json'), 'w'))
        pf9 = os.path.join(OUT, 'payload/USER_09.bin')
        if os.path.exists(pf9):
            os.remove(pf9)
    if 'icongrow' in PATCHES:
        ip = os.path.join(OUT, 'generated/USER/_ICON.asm')
        il = open(ip, errors='replace').read().splitlines()
        e = max(i for i, l in enumerate(il) if l.strip() == 'end')
        il[e:e] = ['        db 64 dup(090h)']
        open(ip, 'w').write('\n'.join(il) + '\n')
        ci = os.path.join(OUT, 'check_icon.bin')
        run([JWASM, '-nologo', '-bin', '-Fo=' + ci, ip])
        ilen = len(open(ci, 'rb').read())
        ishift = grow.relayout(os.path.join(OUT, 'meta'), 'USER', 9, ilen)
        print('grew _ICON to', ilen, 'file shift', ishift)
        im2 = json.load(open(os.path.join(OUT, 'meta/USER.json')))
        hs2 = bytearray(base64.b64decode(im2['header_suffix']))
        for o in (0x0A, 0x1E, 0x2A, 0x3E, 0x52):
            v = struct.unpack_from('<H', hs2, o)[0]
            struct.pack_into('<H', hs2, o, v + (ishift >> 4))
        im2['header_suffix'] = base64.b64encode(bytes(hs2)).decode('ascii')
        json.dump(im2, open(os.path.join(OUT, 'meta/USER.json'), 'w'), indent=1)
        pf9 = os.path.join(OUT, 'payload/USER_09.bin')
        if os.path.exists(pf9):
            os.remove(pf9)
    pf = os.path.join(OUT, 'payload/USER_01.bin')
    if os.path.exists(pf):
        os.remove(pf)
    # pack.py assembles the source again; force every new relocation site's
    # chain word to FFFFh (the marker ordinal must not remain there).
    if added:
        os.makedirs(os.path.join(OUT, 'tmp'), exist_ok=True)
        patch = {str(r['offset']): 0xffff for r in added}
        json.dump(patch, open(os.path.join(OUT, 'tmp/USER_01.patch.json'), 'w'))
    env = dict(os.environ,
               PACK_GEN=os.path.join(OUT, 'generated'),
               PACK_META=os.path.join(OUT, 'meta'),
               PACK_OUT=os.path.join(OUT, 'build'),
               PACK_TMP=os.path.join(OUT, 'tmp'),
               PACK_PAYLOAD_DIR=os.path.join(OUT, 'payload'),
               PACK_SKIP_HASH='1')
    run(['python3', os.path.join(ROOT, 'windows1.01-reasm/pack.py'), 'USER'], env=env)
    print('built', os.path.join(OUT, 'build/USER.EXE'),
          'patches', ','.join(sorted(PATCHES)), 'len', newlen)


if __name__ == '__main__':
    main()
