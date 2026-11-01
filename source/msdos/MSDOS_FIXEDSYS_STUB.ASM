; MSDOS_FIXEDSYS_STUB.ASM
;
; Stub inserted at _TEXT:0A0B of the Windows 1.01 MS-DOS Executive.
; The original three bytes there are:
;
;       56 57 06        push si / push di / push es
;
; They start the file-list line painter's frame.  The stub pops the near
; call return address, replays those three pushes so the original epilogue
; still balances, pushes the return address back, selects the OEM fixed
; font for the HDC in [bp+0Ch], restores the caller registers, and returns.
;
; The OEM handle 045Eh is the Fixedsys handle in the combined
; FONTS_30_SYS_FIXEDSYS.FON font library.  If the library changes, run
; FINFO.EXE and pass the new handle to patch_msdos_fixedsys.py.
;
; Do not use `push 045Eh`: 68h is an 80186 PUSH imm16 and decodes as JS rel8
; on an 8086/8088, which corrupts the stack.  Use mov bx / push bx.
;
; The far call target is the GDI SelectObject thunk in this EXE
; (cs:[1D0Bh]).  patch_msdos_fixedsys.py checks the bytes and writes the
; same instruction stream; this file is the readable source of that stream.

        .8086

        pop     ax                      ; near call return address
        push    si                      ; rebuild the original frame
        push    di
        push    es
        push    ax                      ; put the return address back
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        push    word ptr [bp+0Ch]       ; file-list HDC
        mov     bx, 045Eh               ; OEM fixed font handle
        push    bx
        call    far ptr cs:[1D0Bh]      ; GDI SelectObject
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        ret
