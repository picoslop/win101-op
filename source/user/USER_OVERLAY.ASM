; USER_OVERLAY.ASM
; Appended _TEXT code for the t_ovS23 class-preserving overlap build.
; Extracted from the release USER build's generated _TEXT.asm beginning at
; CREATE_OVERLAP_STUB.  The site patches in the original _TEXT body and the
; resource edits are in build_overlap_stock.py and remove_menu_size.py.
; This file is reference source for the binary patch; it is not a complete
; assemblable module (it uses the full build's labels and REL_ aliases).

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
        mov ax,offset REL_L_0377
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
        mov ax,offset REL_L_0EFB
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
        mov ax,offset REL_L_0F17
        push ax
        retf
SHOW_DISPATCH_POPUP:
        push cs
        mov ax,offset REL_L_0E79
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
        mov ax,offset REL_MOVEPOPUP
        push ax
        ret
SHOW_FULLSCREEN_DONE:
        push si
        mov ax,2
        push ax
        mov ax,offset SHOW_FULLSCREEN_AFTER_SIZE
        push ax
        mov ax,offset REL_SENDSIZE
        push ax
        ret
SHOW_FULLSCREEN_AFTER_SIZE:
        push cs
        mov ax,offset REL_L_0E79
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
        mov ax,offset REL_MOVEPOPUP
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
        mov ax,offset REL_L_04FF
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
        mov ax,offset REL_L_0814
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
        mov ax,offset REL_L_2049
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
        mov ax,offset REL_L_2093
        push ax
        retf

SHOW_AFTER_PUTPOPUP_STUB:
        test byte ptr [si+33h],1
        jz SHOW_AFTER_PUTPOPUP_NORMAL
        push si
        mov ax,1
        push ax
        mov ax,offset REL_L_0F14
        push ax
        push si
        mov ax,offset REL_COMPCLIENTRECT
        push ax
        mov ax,offset REL_PUTPOPUPWND
        push ax
        ret
SHOW_AFTER_PUTPOPUP_NORMAL:
        push si
        mov ax,offset REL_L_0F14
        push ax
        mov ax,offset REL_PUTPOPUPWND
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
        mov ax,offset REL_BRINGPOPUPTOTOP
        push ax
        retf
ACTIVATE_TAIL_DONE:
        mov ax,[bp-4h]
        ret

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
        mov ax,offset REL_SHUTPOPUPWND
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
        push si
        call near ptr ICON_RECTS_CLEAR
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
        mov ax,offset REL_MOVEPOPUP
        push ax
        ret
SHOW_REST_AFTER_MOVE:
SHOW_REST_NO_RECT:
        push si
        push word ptr ds:[5BAh]
        mov ax,offset SHOW_REST_AFTER_UNLINK
        push ax
        mov ax,offset REL_UNLINKWND
        push ax
        ret
SHOW_REST_AFTER_UNLINK:
        push si
        push word ptr ds:[5BAh]
        sub ax,ax
        push ax
        mov ax,offset SHOW_REST_AFTER_LINK
        push ax
        mov ax,offset REL_LINKWND
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
        mov ax,offset REL_PUTPOPUPWND
        push ax
        ret
SHOW_REST_AFTER_PUT:
        push si
        mov ax,1
        push ax
        mov ax,offset SHOW_REST_DONE
        push ax
        mov ax,offset REL_COMPCLIENTRECT
        push ax
        ret
SHOW_REST_DONE:
        mov ax,[bp-6h]
        push cs
        mov ax,offset REL_L_0F17
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
        mov ax,offset REL_MOVEPOPUP
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
        mov ax,offset REL_SHOWWINDOW
        push ax
        retf
OPENWND_AFTER_SHOW:
        ret
OPENWND_STUB_ORIG:
        cmp word ptr ds:[18h],0h
        jz OPENWND_STUB_BRANCH0
        push cs
        mov ax,offset REL_L_0D54
        push ax
        retf
OPENWND_STUB_BRANCH0:
        push cs
        mov ax,offset PATCH_0D49
        push ax
        retf

GETWC2_STUB:
        mov ax,[bx+40h]
        mov dx,[bx+42h]
        and dx,0FEFFh
GETWC2_STUB_NOMASK:
        push cs
        xchg ax,bx
        mov ax,offset REL_L_6291
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
        mov ax,offset REL_L_62E0
        push ax
        xchg ax,bx
        retf

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
        mov ax,offset REL_SHOWWINDOW
        push ax
        retf
SC_ICON_DONE:
        jmp REL_L_4342
SC_ICON_ORIG:
        cmp word ptr [bp-0Ah],0h
        jz SC_ICON_DONE
        jmp REL_L_41BE

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
        mov ax,offset REL_SHOWWINDOW
        push ax
        retf
SC_ZOOM_DONE:
        jmp REL_L_4342
SC_ZOOM_ORIG:
        cmp word ptr [bp-0Ah],0h
        jz SC_ZOOM_DONE
        jmp REL_L_420F

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
        call near ptr REL_HITTEST
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
        ; coordinates feed REL_MOVEPOPUP a huge rectangle and the 86Box mouse
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
        ; call REL_BRINGPOPUPTOTOP here: its REL_ACTIVATEWINDOW tail runs a model
        ; loop and hangs when entered from REL_CHECKSYSQUEUE.
        call near ptr REL_INVALIDATEALLDCS
        push si
        push word ptr ds:[5BAh]
        call near ptr REL_UNLINKWND
        push si
        push word ptr ds:[5BAh]
        sub ax,ax
        push ax
        call near ptr REL_LINKWND
        push si
        call near ptr REL_ONEWNDREPAINT
        call near ptr REL_CALCALLVISRGNS

        ; No REL_SETCURSOR here: see SYSCOMMAND_SIZE_STUB.  The 86Box XT
        ; serial-mouse REL_SETCURSOR path raises the DOS AUX error.

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
        mov ax,offset REL_MOVEPOPUP
        push ax
        ret
EDGE_AFTER_MOVE:
        ret

EDGE_DONE:
        mov byte ptr cs:[EDGE_ORIGIN],0
        cmp byte ptr cs:[EDGE_MOVED],0
        je EDGE_DONE_NOSIZE
        push word ptr cs:[EDGE_HWND]
        call near ptr REL_SENDSIZEMESSAGE
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
CAPTION_CENTER:
        add ax,ds:[480h]
        sub ax,dx
        inc ax
        ret

end
