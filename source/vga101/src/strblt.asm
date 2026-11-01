	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	STRBLT.ASM
;
;   This module contains the strblt function and the ExtendedTextOut
;   function.
;
; Created: 17-Mar-1987
; Author:  **** ***** [*****]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	Strblt
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;-----------------------------------------------------------------------;


FIXED_PITCH_ON = 1			;en/disables smartfix code


;	This function will perform private stack checking.  In order for
;	private stack checking to occur, two symbols must be defined
;	prior to the inclusion of cmacros.inc.	?CHKSTK must be defined
;	if the cmacros are to perform stack checking on procedures with
;	local parameters.  ?CHKSTKPROC must be defined if private stack
;	checking will be used.
;
;	The actual macro body for ?CHKSTKPROC will be defined later.


?CHKSTK = 1
?CHKSTKPROC	macro
		endm


	.xlist
	include cmacros.inc
incFont 	= 1			;Include control for gdidefs.inc
incDrawMode	= 1			;Include control for gdidefs.inc
	include gdidefs.inc
	include display.inc
	include ega.inc
	include egamem.inc
	include macros.mac
	include strblt.inc
	include fontseg.inc
	.list


	??_out	strblt


;	Link time constants describing the size and color format
;	that the EGA will be running in.

	externA ScreenSelector		;Selector to the screen
	externA SCREEN_W_BYTES		;Screen width in bytes
	externA SCREEN_WIDTH		;Screen width in pixels
	externA COLOR_FORMAT		;Color format (0103h or 0104h)

	extrn	ega_saved:word

;	Other functions required for strblt.

ifdef	 EXCLUSION
	externNP exclude		;Exclude area from screen
	externNP unexclude		;Clear excluded area
endif


extrn	ega_state_rot:word
extrn	ega_state_mode:word
extrn	ega_state_mask:word

sBegin	Code
assumes cs,Code
page
;--------------------------Exported-Routine-----------------------------;
; Strblt
;
; This is the old strblt entry point.  Null parameters are pushed
; for the ExtTextOut's extra parameters, and control given to
; ExtTextOut.
;
; Entry:
;	EGA registers in default state
; Returns:
;	DX = Y extent of string if extent call
;	AX = X extent of string if extent call
;	EGA registers in default state
; Error Returns:
;	DX:AX = 8000:0000H
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	See ExtTextOut
; History:
;	Thu 09-Apr-1987 13:36:08 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


	assumes ds,Data
	assumes es,nothing

;
; WIN1 In Windows 1, STRBLT now becomes live!
;
cProc	Strblt,<FAR,PUBLIC,WIN,PASCAL>,<si,di>

	parmD	lp_device		;Destination device
	parmW	x			;Left origin of string
	parmW	y			;Top  origin of string
	parmD	lp_clip_rect		;Clipping rectangle
	parmD	lp_string		;The string itself
	parmW	count			;Number of characters in the string
	parmD	lp_font 		;Font to use
	parmD	lp_draw_mode		;Drawmode structure to use
	parmD	lp_xform		;Current text transform

;	ExtTextOut parameters we have to dummy up.
;
;	parmD	lp_dx			;Widths for the characters
;	parmD	lp_opaque_rect		;Opaquing rectangle
;	parmW	eto_options		;ExtTextOut options

	localW	bp4
	localW	abs_count		;*[bp-6] WIN1
	localW 	local_str		;*[bp-8] WIN1
	localW	next_scan		;*[bp-0a] Index to get to next scan line
	localW	y_step			;*[bp-0c] Y step
	localW	draw_func		;*[bp-10]
	localB	num_planes		;Number of planes in a bitmap
	localB	opaque_routine		;Routine which does actual opaquing
	localW	colors			;Text/background colors
;		^--- this is probably actually opaque_routine
	localW	next_plane		;Index to get to next plane
	localW	fontw_bytes		;*[bp-18h] Source font width (bytes)
	localW	opaque_height		;Height of opaque box (sometimes)
	localW	clip_left		;*[bp-1c] WIN1
	localW	clip_right		; [bp-1e] WIN1
;;;	localD	lp_surface		;Pointer to first byte of destination
	localW	temp_off_lp_bits	;Intermediate pointer to dev surface
	localW	scan_start		;Delta from start of scan
	localW	clipped_font_height	;Actual height of bits to be drawn
;
; BP-24h
;
;;;	localW	tot_brk_extra		;Total break extra
	localW	df_pixel_w		; WIN1 font pixel width
	localW	brk_extra		;*# extra pixels to add each break char
	localW	brk_err 		;*Justification DDA error term
	localW	brk_rem 		;*  extra pixels are distributed
	localW	brk_count		;*DDA - # breaks into which BrkRem
	localW	char_xtra		;*# extra pixels to add each char


	localW	buffer			;[bp-30] Offset of buffer on the stack
	localW	plane_pitch		;[bp-32] Gap from one plane to next
	localW	codebuf			;[bp-34] Offset of generated code

	localD	background		;[bp-36]
	localD	foreground		;[bp-3a]

cBegin
	if	???			;Do test only if locals
	jc	j_exit_strblt		;No room for locals, return now
	endif

	mov	ax, count
	cwd
	xor	ax,dx			;Force positive
	shl	ax, 1			;Check that there's room on the stack
	shl	ax, 1			;for the string
	add	ax, 20h			;at 4 bytes / character + 32 overhead
	mov	cx, ax
	call	my_check_stack
	jnc	strblt_01
j_exit_strblt:
	jmp	exit_strblt
;
strblt_01:
	add	sp, cx
	mov	local_str, sp	
	lds	si, lp_clip_rect
	les	di, lp_font
	xor	dx, dx
	
;;;	mov	al,enabled_flag 	;Save enabled_flag incase we need it
;;;	mov	local_enabled_flag,al

;;;	call	get_mode		;Get data from drawmode, set flags
;;;	call	get_font		;Get font data (aborts if invalid)


;	If the character count is negative, then the extent of the
;	string should be calculated.  If positive, then the string
;	should be drawn.

	mov	ax,count
	or	ax,ax
	jz	j_only_draw		;No chars, might have opaque rect
	jg	strblt_02		;Positive count, output string
	neg	ax
	xor	bx, bx
	mov	word ptr lp_clip_rect, bx
strblt_02:
	mov	abs_count, ax
	mov	cx, es:[di].dfWidthBytes
	mov	fontw_bytes, cx
	mov	ax, es:[di].dfPixWidth
	mov	df_pixel_w, ax
	or	si, si			;Clip rectangle present?
	jz	strblt_05
	mov	ax, [si].top
	mov	dx, ax
	sub	ax, y
	mov	bx, ax
	jge	strblt_03
	sub	dx, bx
	xor	bx, bx
strblt_03:
	mov	temp_off_lp_bits,dx
	mov	scan_start,dx
	mov	dx, es:[di].dfPixHeight
	cmp	bx, dx
	jge	j_only_draw
	mov	ax, [si].bottom
	sub	ax, y
	cmp	ax, dx
	jl	strblt_04
	mov	ax, dx
strblt_04:
	or	ax, ax
	jle	j_only_draw
	cmp	ax, bx
	jle	j_only_draw
	jmp	short strblt_06

j_only_draw:
	jmp	only_draw


strblt_05:
	mov	bx, y
	mov	temp_off_lp_bits,bx
	mov	scan_start,bx
	xor	bx, bx
	mov	ax, es:[di].dfPixHeight
strblt_06:
	sub	ax, bx
	mov	clipped_font_height,ax
	add	scan_start, ax
	add	ax, bx
	mul	cx
	mov	dx,es:[di].dfBitsPointer
	add	ax, dx
	dec	ax
	mov	opaque_height, ax
	mov	ax, bx
	mov	si, bx
	mov	bx, dx
	mul	cx
	add	ax, bx
	dec	ax
	mov	next_plane,ax
	mov	ax, si
	lds	si, lp_draw_mode
	mov	brk_err, 0
	cmp	word ptr es:[di].dfPixWidth, 0
	jz	strblt_08
	mov	dx, offset X152D
	mov	opaque_routine,dx		
	cmp	[si].TBreakExtra,0
	jz	strblt_07
	mov	dx, offset X1553
	mov	opaque_routine,dx
	mov	dx, [si].BreakExtra
	mov	brk_extra,dx
	mov	dx, [si].BreakRem
	mov	brk_rem,dx
	mov	dx, [si].BreakErr
	mov	brk_err,dx
	mov	dx, [si].BreakCount
	mov	brk_count,dx
	xor	dx, dx
	mov	df_pixel_w, dx
strblt_07:
	mov	dx, [si].CharExtra
	mov	si, offset X1511
	or	dx, dx
	jz	strblt_10
	mov	si, offset X150B
	mov	char_xtra,dx
	xor	dx, dx
	mov	df_pixel_w, dx
	jmp	short strblt_10
;
strblt_08:
	mov	dx, offset X158E
	mov	opaque_routine, dx
	cmp	[si].TBreakExtra, 0
	jz	strblt_09
	mov	dx, offset X153F
	mov	opaque_routine, dx
	mov	dx, [si].BreakExtra
	mov	brk_extra,dx
	mov	dx, [si].BreakRem
	mov	brk_rem,dx
	mov	dx, [si].BreakErr
	mov	brk_err,dx
	mov	dx, [si].BreakCount
	mov	brk_count,dx
	xor	dx, dx
	mov	df_pixel_w, dx
strblt_09:	
	mov	dx, [si].CharExtra
	mov	si, offset X1576
	or	dx, dx
	jz	strblt_10
	mov	si, offset X1570
	mov	char_xtra, dx
	xor	dx, dx
	mov	df_pixel_w, dx
strblt_10:
	mov	draw_func, si
	xor	si, offset X15AF
	mov	colors, si		;XXX
	lds	si, lp_device
	mov	dx, [si].bmWidthBytes
	mov	y_step, dx
	add	ax, y
	mul	dx
	lds	si, lp_clip_rect
	mov	bx, x
	or	si, si
	jz	strblt_15
	mov	cx, [si].left
	mov	clip_left, cx
	mov	di, bx
	mov	dx, [si].right
	mov	clip_right, dx
	sub	dx, cx
	sub	bx, cx
	jl	strblt_11
	mov	clip_left, di
	mov	cx, di
	sub	dx, bx
	xor	bx, bx
strblt_11:
	mov	di, cx
	and	di, word ptr 7
	sub	di, 8
	neg	di
	mov	bp4, di		;XXX
	shr	cx, 1
	shr	cx, 1
	shr	cx, 1
	add	ax, cx
	mov	next_scan, ax	;XXX
	cmp	bx, dx
	jge	j2_only_draw
	lds	si, lp_string
	les	di, lp_font
strblt_12:
	call	word ptr draw_func
	jle	strblt_12
	or	ax, ax
	jz	strblt_14
	add	ax, cx
	sub	ax, bx
	mov	cx, bx
	sub	bx, dx
strblt_13:
	jge	strblt_21
	mov	ch, cl
	mov	cl, al
	shr	ax, 1
	shr	ax, 1
	shr	ax, 1
	push	ax
	and	cl, 7
	push	cx
	call	word ptr draw_func
	jmp	short strblt_13
;
strblt_14:
	add	ax, cx
	sub	ax, bx
	and	ax, 7
	mov	cx, bx
	sub	bx, dx
	jmp	short strblt_13
;
strblt_15:
	mov	clip_left, bx
	mov	clip_right, bx
	mov	cx, bx
	mov	di, cx
	and	di, word ptr 7
	sub	di, 8
	neg	di
	mov	bp4, di	;XXX
	shl	bx, 1
	shl	bx, 1
	shl	bx, 1
	add	ax, bx
	mov	next_scan, ax	;XXX
	lds	si, lp_string
	les	di, lp_font
	xor	bx, bx
strblt_16:
	call	word ptr draw_func
	mov	ch, cl
	mov	cl, al
	shr	ax, 1
	shr	ax, 1
	shr	ax, 1
	push	ax
	and	cl, 7
	push	cx
	jmp	short strblt_16
;
j2_only_draw:	
	jmp	only_draw
j_strblt_42:
	jmp	strblt_42

strblt_20:
	pop	dx
	pop	si
	xor	ax, ax
	push	ax
	dec	ax
	push	ax
	push	si
	push	dx
	jmp	short strblt_23
;
strblt_21:
	sub	cx, bx
	jle	strblt_22
	mov	ch, cl
	mov	cl, al
	shr	ax, 1
	shr	ax, 1
	shr	ax, 1
	push	ax
	and	cl, 7
	push	cx
strblt_22:
	cmp	sp, local_str
	jz	j2_only_draw
	cmp	df_pixel_w, 8
	jz	strblt_20
strblt_23:
	xor	ax, ax
	push	ax
	dec	ax
	push	ax
	mov	cx, count
	or	cx, cx
	jg	strblt_25
	mov	cx, brk_err
	jcxz	strblt_24
	lds	si, lp_draw_mode
	mov	[si].BreakErr, ax
strblt_24:
	mov	ax, clip_right
	sub	ax, clip_left
	mov	dx, scan_start
	sub	dx, temp_off_lp_bits
	jmp	only_draw
;
strblt_25:
	lds	si, lp_device
	mov	cx, [si].bmType
	jcxz	strblt_27
	mov	cx, clip_left
	mov	dx, temp_off_lp_bits
	mov	si, clip_right
	mov	di, scan_start
	call	exclude
	mov	ax, DR_SET shl 8 + GRAF_DATA_ROT 	;Rotate unmodified
	mov	dx, EGA_BASE + GRAF_ADDR
	mov	cs:ega_state_rot, ax
	mov	byte ptr cs:ega_saved, 2
	out16	dx,ax
	mov	ax, M_COLOR_WRITE shl 8  + GRAF_MODE
	mov	cs:ega_state_mode, ax
	out16	dx, ax
	mov	dl, SEQ_ADDR
	mov	ax, 0700h + SEQ_MAP_MASK
	mov	cs:ega_state_mask, ax
	out16	dx,ax
	lds	si, lp_draw_mode
	mov	al, [si].TextColor + 3
	and	al, 7
	mov	bptr foreground, al
	mov	dx, offset write_to_planes
	cmp	word ptr [si].bkMode, 1
	jz	strblt_26
	mov	al, bptr [si].bkColor + 3
	and	al, 7
	mov	bptr background, al
	mov	cx, offset strblt_31
	jmp	short strblt_29
;
strblt_26:	
	mov	buffer, dx
	jmp	strblt_42
;
strblt_27:
	mov	ax, [si].bmWidthPlanes
	cmp	word ptr [si].bmPlanes, 103h
	lds	si, lp_draw_mode
	jz	strblt_28
	mov	al, [si].TextColor + 3
	shl	al, 1
	cbw
	mov	bptr foreground, ah
	mov	dx, offset write_to_mono
	cmp	word ptr [si].bkMode, 1
	jz	strblt_26
	mov	al, [si].bkColor + 3
	shl	al, 1
	cbw
	mov	bptr background, ah
	mov	cx, offset blank_mono
	jmp	short strblt_29
;
strblt_28:
	mov	plane_pitch, ax
	mov	bx, ax
	add	ax, ax
	add	ax, bx
	add	ax, y_step
	mov	codebuf,ax
	mov	ax, [si].TextColor
	mov	wptr foreground, ax
	mov	al, [si].TextColor+2
	mov	bptr foreground+2, al
	mov	dx, offset write_to_cbitmap
	cmp	word ptr [si].bkMode, 1
	jz	strblt_26
	mov	ax, [si].bkColor
	mov	wptr background, ax
	mov	al, [si].bkColor+2
	mov	bptr background + 2, al
	mov	cx, offset strblt_38
strblt_29:
	mov	[bp-30h], dx
	push	cx
	mov	cx, clip_left
	mov	ax, cx
	shr	ax, 1
	shr	ax, 1
	shr	ax, 1
	mov	dl, 0FFh
	and	cx, word ptr 7
	shr	dl, cl		;Left fringe
	mov	cx, clip_right
	dec	cx
	mov	bx, cx
	shr	bx, 1
	shr	bx, 1
	shr	bx, 1
	mov	dh, 0FFh
	and	cx, word ptr 7
	sub	cx, 7
	neg	cx
	shl	dh, cl		;Right fringe
	inc	ax
	sub	bx, ax
	jge	strblt_30
	and	dl, dh	;Left fringe = right fringe
strblt_30:	
	mov	clip_left, bx
	les	di, lp_device
	les	di, es:[di].bmBits
	add	di, next_scan	
	retn
;
strblt_31:
	mov	si, y_step
	sub	si, bx
	sub	si, 2
	mov	bx, dx		;Fringe masks
	mov	dx, EGA_BASE + GRAF_ADDR
strblt_32:
	mov	ah, bl
	mov	al, GRAF_BIT_MASK
	cli	
	out	dx, ax
	mov	al, es:[di]	;Load EGA latches
	mov	al, bptr background
	stosb
	sti
	mov	cx, clip_left
	or	cx, cx
	jl	strblt_34
	jz	strblt_33
	mov	ax, 0FF00h + GRAF_BIT_MASK
	out	dx, ax		;Restore bitmask
	mov	al, bptr background
	rep	stosb
strblt_33:
	mov	ah, bh
	mov	al, GRAF_BIT_MASK
	cli
	out	dx, ax		;Mask for right fringe
	mov	al, es:[di]	;Load latches
	mov	al, bptr background 
	stosb
	sti
strblt_34:
	add	di, si
	dec	clipped_font_height
	jg	strblt_32
	jmp	short strblt_42
;
blank_mono:
	mov	ah, bptr background	;Colour
	mov	si, y_step
	sub	si, bx
	dec	si
	mov	bx, clipped_font_height
strblt_36:
	mov	al, es:[di]
	xor	al, ah
	and	al, dl
	xor	es:[di], al
	inc	di
	mov	cx, clip_left
	or	cx, cx
	jl	strblt_37
	mov	al, ah
	rep	stosb
	mov	al, es:[di]
	xor	al, ah
	and	al, dh
	xor	es:[di], al
strblt_37:
	add	di, si
	dec	bx
	jg	strblt_36
	jmp	short strblt_42
;
strblt_38:
	mov	ax, plane_pitch
	add	ax, ax
	add	di, ax
strblt_39:
	mov	si, 2
strblt_40:
	mov	bx, di
	mov	ah, background[si]	;Colour for this plane
	mov	al, es:[di]
	xor	al, ah
	and	al, dl		;Left fringe
	xor	es:[di], al
	inc	di
	mov	cx, clip_left
	or	cx, cx
	jl	strblt_41	;No middle or right
	mov	al, ah
	rep	stosb
	mov	al, es:[di]
	xor	al, ah
	and	al, dh		;Right fringe
	xor	es:[di], al
strblt_41:
	mov	di, bx
	sub	di, plane_pitch
	dec	si
	jns	strblt_40
	add	di, codebuf
	dec	clipped_font_height
	jg	strblt_39

strblt_42:
	lds	si, lp_font
	lds	si, [si].dfBitsPointer
	les	di, lp_device
	les	di, es:[di].bmBits
	add	di, next_scan
	mov	next_scan, di
	jmp	strblt_52
;
strblt_43:
	add	cl, dh
	shl	ax, cl
	mov	cl, dh
	call	word ptr buffer
	mov	dh, 8
	neg	cl
	jz	strblt_45
strblt_44:
	sub	dh, cl
	jle	strblt_43
	shl	ax, cl
strblt_45:
	cmp	ch, 8
	ja	strblt_47
	or	ch, ch
	jz	strblt_49
	xor	al, al
	or	si, si
	jz	strblt_46
	lodsb
strblt_46:
	mov	cl, ch
	xor	ch, ch
	jmp	short strblt_44
;
strblt_47:
	xor	al, al
	or	si, si
	jz	strblt_48
	lodsb
strblt_48:
	mov	cl, 8
	sub	ch, cl
	jmp	short strblt_44
strblt_49:
	dec	bx
	dec	bx
	mov	si, ss:[bx]
	dec	bx
	dec	bx
	mov	cx, ss:[bx]
	or	cl, cl
	js	strblt_51
	xor	al, al
	or	si, si
	jz	strblt_50
	add	si, next_plane
	lodsb
strblt_50:
	shl	al, cl
	sub	cl, 8
	neg	cl
	sub	ch, cl
	jnc	strblt_44
	add	cl, ch
	xor	ch, ch
	jmp	short strblt_44
;
strblt_51:
	add	si, next_plane
	mov	cl, dh
	shl	ah, cl
	call	word ptr buffer
	mov	si, next_plane
	add	si, fontw_bytes
	cmp	si, opaque_height
	jnc	strblt_53
	mov	next_plane, si
	mov	di, y_step 
	add	di, next_scan
strblt_51a:
	mov	next_scan, di
strblt_52:
	mov	bx, local_str
	xor	ax, ax
	mov	dh, bptr bp4	;XXX
	cmp	df_pixel_w, 8
	jz	strblt_54
	jmp	short strblt_49
;
strblt_53:
	jmp	short only_draw
	nop
strblt_54:
	xor	cx, cx
	mov	cl, dh
	dec	bx
	dec	bx
	mov	si, ss:[bx]
	or	si, si
	jz	strblt_61
	add	si, next_plane
	mov	cx, ss:[bx-2]
	lodsb
	xchg	ah, al
	shl	ah, cl
	sub	cl, 8
	neg	cl		;Right fringe
	cmp	dh, cl
	jg	strblt_55
	xchg	cl, dh
	rol	ax, cl
	sub	cl, dh
	jnz	strblt_59
	mov	cl, 8
	jmp	short strblt_57
;
strblt_55:
	rol	ax, cl
	sub	cl, dh
	jmp	short strblt_60

strblt_56:
	add	si, next_plane
	lodsb
strblt_57:
	xchg	al, ah
	call	word ptr buffer
	xchg	al, ah
	sub	bx, 4
	mov	si, ss:[bx]
	or	si, si
	jnz	strblt_56
	jmp	short strblt_61
;
strblt_58:
	add	si, next_plane
	mov	ah, [si]
	rol	ax, cl
	sub	cl, 8
strblt_59:
	neg	cl
	xchg	al, ah
	call	word ptr buffer
	xchg	al, ah
	rol	ax, cl
	sub	cl, 8
strblt_60:
	neg	cl
	sub	bx, 4
	mov	si, ss:[bx]
	or	si, si
	jnz	strblt_58
strblt_61:	
	dec	bx
	dec	bx
	mov	ah, al
	mov	dh, cl
	jmp	strblt_49
;
only_draw:
	mov	sp, local_str
	mov	byte ptr cs:ega_saved, 0
	call	unexclude
exit_strblt:

cEnd	<nogen>
	pop	di
	pop	si
	sub	bp, 2
	mov	sp, bp
	pop	ds
	pop	bp
	dec	bp
	retf	1Eh
	page
;

X1505:	mov	al, es:[di].dfDefaultChar
	jmp	short X1523
;
X150B:	mov	cx,colors
	xor	draw_func,cx
X1511:	lodsb
	dec	abs_count
	jl	X1535
	cmp	al, es:[di].dfLastChar
	ja	X1505
	sub	al, es:[di].dfFirstChar
	jb	X1505
X1523:	mov	cx, es:[di].dfPixWidth
	cmp	al, es:[di].dfBreakChar
	jz	X153C
X152D:	mul	cl
	add	ax, 8
	add	bx, cx
	ret
;
X1535:	add	clip_right, bx
	pop	ax
	jmp	strblt_22
;
X153C:	jmp	wptr opaque_routine
;
X153F:	xor	ah, ah
	shl	ax, 1
	push	bx
	mov	bx, ax
	mov	ax, es:[bx+di].dfCharOffset
	mov	cx, es:[bx+di].dfCharOffset+2
	sub	cx, ax
	pop	bx
	jz	X1576
X1553:	add	cx, brk_extra
	mov	ax, brk_err
	sub	ax, brk_rem
	jg	X1562
	add	ax, brk_count
	inc	cx
X1562:	mov	brk_err, ax
	xor	ax, ax
	add	bx, cx
	ret
;
X156A:	mov	al, es:[di].dfDefaultChar
	jmp	short X1588

X1570:	mov	cx, colors
	xor	draw_func, cx
X1576:	lodsb
	dec	abs_count
	jl	X15A8
	cmp	al, es:[di].dfLastChar
	ja	X156A
	sub	al, es:[di].dfFirstChar
	jc	X156A
X1588:	cmp	al, es:[di].dfBreakChar
	jz	X153C
X158E:	xor	ah, ah
	shl	ax, 1
	push	bx
	mov	bx, ax
	mov	ax, es:[bx+di].dfCharOffset
	mov	cx, es:[bx+di].dfCharOffset+2
	sub	cx, ax
	add	ax, 8
	pop	bx
	jz	X1576
	add	bx, cx
	ret

X15A8:
	add	clip_right, bx
	pop	ax
	jmp	strblt_22

X15AF:
	mov	cx, colors
	xor	draw_func, cx
	mov	cx, char_xtra
	xor	ax, ax
	add	bx, cx
	ret
;
; Write to a multiplane display
;
write_to_planes:
	push	ax
	mov	al, GRAF_BIT_MASK
	mov	dx, EGA_BASE + GRAF_ADDR
	cli
	out	dx, ax
	mov	al, es:[di]
	mov	al, bptr foreground
	stosb
	sti
	pop	ax
	ret
;
write_to_mono:
	mov	dl, es:[di]
	xor	dl, bptr foreground
	and	dl, ah
	xor	es:[di], dl
	inc	di
	ret
;
; Write to a multiplane bitmap
;
write_to_cbitmap:
	push	bx
	mov	bx, plane_pitch
	mov	dl, es:[di]
	xor	dl, bptr foreground
	and	dl, ah
	xor	es:[di], dl
	mov	dl, es:[bx+di]
	xor	dl, bptr foreground+1
	and	dl, ah
	xor	es:[bx+di],dl
	add	bx,bx
	mov	dl, es:[bx+di]
	xor	dl, bptr foreground+2
	and	dl, ah
	xor	es:[bx+di], dl
	inc	di
	pop	bx
	ret	


sEnd	Code
	end
