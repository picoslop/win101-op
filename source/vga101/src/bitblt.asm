	page	,132
;----------------------------Module-Header------------------------------;
; Module Name: BITBLT.ASM
;
; BitBLT at level of device driver.
;
; Created: In Windows' distant past (c. 1983)
;
; Copyright (c) 1983 - 1987  Microsoft Corporation
;
;
; This is the main module of those comprising the source to BitBLT
; (Bit BLock Transfer) for Microsoft Windows display drivers. It
; defines the procedure, and performs general preprocessing for all BLT
; requests.
;
; BitBLT  transfers a rectangle of bits from source to destination,
; doing some useful operations on the way, namely:
;
; o	clipping the source rectangle to fit within the
; 	source device dimensions;
;
; o	excluding the cursor;
;
; o	performing a user-specified raster operation, out of
; 	a vast array of choices, which takes the form
;
; 	D = f(S,D,P)
;
; 	where S = source bit, D = destination bit, P = pattern
; 	bit, and  f  is a sequence of logical operations (AND, OR,
;	XOR, NOT) on S, D, and P;
;		
; o	recognizing common special cases for accelerated processing.
;
;
; For a detailed explanation of the contortions BitBLT goes through
; to put your bits in place, see the file COMMENT.BLT.
;
;
; BitBLT consists of the following files:
;
;	BITBLT.ASM		procedure definition
;	CBLT.ASM		procedure to compile arbitrary BLT on stack
;
;	GENLOCAL.BLT		function parameters and generic locals
;	CLRLOCAL.BLT		color/monochrome-related locals
;	DEVLOCAL.BLT		device-related locals
;
;	GENCONST.BLT		generic constants
;	CLRCONST.BLT		color/monochrome constants
;	DEVCONST.BLT		constants used by device-dependent code
;
;	GENDATA.BLT		generic compiled code templates and data
;	CLRDATA.BLT		color/monochrome-dependent templates and data
;	DEVDATA.BLT		device-dependent code templates and data
;
;	ROPDEFS.BLT		constants relating to ROP definitions
;	ROPTABLE.BLT		table of ROP templates
;
;	PDEVICE.BLT		PDevice processing
;	PATTERN.BLT		pattern preprocessing
;	COPYDEV.BLT		copy device data into local frame
;	COMPUTEY.BLT		compute y-related values
;
;	EXIT.BLT		device-specific cleanup before exiting
;	SPECIAL.BLT		special case code
;
;	COMMENT.BLT		overview of history and design
;-----------------------------------------------------------------------;

THIS_IS_DOS_3_STUFF = 1		; remove this line for WinThorn

	title	BitBLT
	%out	BitBlt


;	This function will perform private stack checking.  In order for
;	private stack checking to occur, two symbols must be defined
;	prior to the inclusion of CMACROS.INC.	?CHKSTK must be defined
;	if the cmacros are to perform stack checking on procedures with
;	local parameters.  ?CHKSTKPROC must be defined if private stack
;	checking will be used.
;
;	The actual macro body for ?CHKSTKPROC will be defined later.
;	(See MACROS.MAC).

?CHKSTK		 = 1
?CHKSTKPROC	macro
		endm

extrn	ega_state_graf:word
extrn	ega_state_mode:word
extrn	ega_state_mask:word
extrn	ega_state_rot:word
extrn	ega_saved:word


ifdef	THIS_IS_DOS_3_STUFF
else
	.8086
endif


;	Define the portions of GDIDEFS.INC that will be needed by bitblt.

incLogical	= 1		;Include GDI logical object definitions
incDrawMode	= 1		;Include GDI DrawMode definitions

	.xlist
	include GDIDEFS.INC
	include MACROS.MAC
	include CMACROS.INC
	include DISPLAY.INC
ifdef	TEFTI
	include TEFTI.MAC
endif
ifdef	THIS_IS_DOS_3_STUFF
else
	include	FIREWALL.INC
	include	DDC.INC
	include ERROR.INC
	include INSTANCE.INC
endif
	.list

        externA SCREEN_HEIGHT           ;Screen height in scanlines
        externA SCREEN_W_BYTES          ;Screen width in bytes
        SCAN_BYTES equ  80              ;this is true for both EGA and VGA

ifdef	THIS_IS_DOS_3_STUFF
	externA ScreenSelector		;Segment of Regen RAM
endif
;;;	externNP	CBLT		;(must be NP, even though defined
					; as FAR -- see CBLT.ASM)
ifdef	EXCLUSION			;If cursor exclusion
	externNP	exclude		;Exclude area from screen
	externNP	unexclude	;Restore excluded area to screen
endif



sBegin	Code
assumes cs,Code
assumes ds,Data
assumes es,nothing


;	Following are the BitBLT include-files.  Some are commented out
;	because they contain address definitions are are included in
;	CBLT.ASM, but are listed here for completeness.  The remaining
;	files include those that make up the local variable frame, and 
;	those containing subroutines.  The frame-variable files are
;	included immediately after the cProc BITBLT declaration.  The
;	subroutines files are included near the end of this file.

	.xlist
	include                 GENCONST.BLT	;EQUs
	include	                CLRCONST.BLT	;EQUs
	include	                DEVCONST.BLT	;EQUs
;
; WIN1 devdata.blt included here rather than in cblt.a86
;
	include			win1.blt
	include                 DEVDATA.BLT	;Driver specific templates,data
	include	                GENDATA.BLT	;bitmask and phase tables
	include	                CLRDATA.BLT	;Color/mono specific templates,data
	include                 ROPDEFS.BLT	;Raster operation definitions
;;;	include	                ROPTABLE.BLT	;Raster operation code templates
	.list




cProc	BITBLT,<FAR,PUBLIC>,<si,di>

	.xlist
	include	                GENLOCAL.BLT	;arguments and generic local vars
	include	                CLRLOCAL.BLT	;color/monochrome-related locals
	include	                DEVLOCAL.BLT	;device-related locals
	.list

cBegin

ife	???				;If no locals
	?CHKSTKPROC 0			;See if room
endif
	jnc	bitblt_stack_ok		;There was room for the frame
	jmp	bitblt_stack_ov 	;There was no room


bitblt_stack_ok:
;;; WIN1 doesn't do this
;;; 	mov	al,enabled_flag 	;Save enabled_flag while we still
;;; 	mov	local_enable_flag,al	;  have DS pointing to Data

ifdef	TEFTI_WHOLE
	timer_begin
endif


	subttl	ROP Preprocessing
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Get the encoded raster operation, and map the raster op if needed.
;
;	To map the ROPS 80h through FFh to 00h through 7Fh, take the
;	1's complement of the ROP, and invert the "negate needed" flag.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

	cld				;Let's make no assumptions about this!
;
; << WIN1 From here on the blit function is completely different
;
	mov	cx, 100h
	mov	wptr bp32, cx
	xor	ax,ax			;Assume not 80h : FFh
	mov	wptr bp30, ax
	mov	ax, word ptr Rop
	cmp	ax, 20h			; SRCCOPY? 
	jz	X06B2
	mov	gl_src_present, cl
	mov	dx, 0C0h
	xchg	ch, cl
X0651:	inc	ch
	test	ax,dx
	jz	X065B
	inc	cl	
	xor	ch, ch
X065B:	shl	dx,1
	shl	dx,1
	jnb	X0651
	mov	dl,5
	test	ax,20h
	jz	X066C
	inc	ch
	inc	dl
X066C:	and	ch, 0FEh
	sub	dl, ch
	mov	bptr bp0b, dl
	mov	bx, ax
	and	bx, word ptr 1Ch
	shr	bx, 1
	and	al, 3
	cmp	bl, 5
	jb	X0686
	add	cl, 2
X0686:	mov	dl, cl
	add	cl, al
	add	cl, cl
	mov	bx, cs:word ptr win1_unktable[bx]
	rol	bx, cl
	mov	gl_operands, bx		; XXX What is this
X0696:	mov	si, bx
	and	si, word ptr 3
	ror	bx, 1
	ror	bx, 1
	inc	bptr bp32[si]
	dec	dl
	jnz	X0696
	test	byte ptr bp32, 1
	jz	X06B2

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	complain - complain that something is wrong
;
;	An error is returned to the caller without BLTing anything.
;
;	Entry:	None
;
;	Exit:	AX = 0 (error flag)
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

complain:
	xor	ax,ax			;Set the error code
	jmp	bitblt_exit_fail
;
X06B2:
	xor	cx,cx
	mov	dx, 1
	cmp	gl_src_present, cl
	jz	X06E7
	mov	ch,1
	lds	si,lpSrcDev
	lodsw			;bmType
	cmp	ax,dx
	cmc
	rcl	ch,1
	lodsw			;bmWidth
	lodsw			;bmHeight
	lodsw			;bmWidthBytes
	mov	gl_src_width_bytes, ax
	lodsw			;bmPlanes / bmBitsPixel
	cmp	ax, 101h
	jz	X06D9		;1 plane,  1bpp: Mono DDB 
	cmp	ax, 103h	;3 planes, 1bpp: Colour DDB 
	jnz	complain
	stc
X06D9:	rcl	ch, 1
	lodsw		
	mov	off_lpSrcDev,ax	;bmBits	off
	lodsw
	mov	seg_lpSrcDev,ax	;bmBits seg
	lodsw
	mov	gl_plane_w,ax ;bmWidthPlanes
X06E7:
	lds	si, lpDestDev
	lodsw			;bmType
	cmp	ax, dx
	cmc
	rcl	ch, 1
	lodsw			;bmWidth
	lodsw			;bmHeight
	lodsw			;bmWidthBytes
	mov	gl_dest_width_bytes, ax
	lodsw			;bmPlanes / bmBitsPixel
	cmp	ax, 101h	;1 plane mono
	jz	X0705
	or	ch, 20h
	cmp	ax, 103h
	jnz	complain
	stc
X0705:	rcl	ch, 1
	lodsw
	mov	off_lpDestDev, ax
	lodsw
	mov	seg_lpDestDev, ax
	lodsw
	mov	gl_dest_plane_w,ax ;bmWidthPlanes
	test	ch, 10h
	jz	X0725
	mov	al, ch
	and	al, 5
	jz	X0725
	xor	al, 5
	jz	X0725
	or	ch, 80h
X0725:	mov	gl_the_flags,ch	
	cmp	gl_pat_present, dh	
	jz	pattern_preproc_end	
	or	byte ptr gl_the_flags, 20h
;
; In Windows 2 this is pattern_preprocessing in pattern.blt
;
	lds	si,lpPBrush		;--> physical brush
;
; Win1 doesn't check this
;
;;;	mov	ax,ds
;;;	or	ax,si
;;;	jz	pattern_preproc_error	;Null pointer, error

	cmp	oem_brush_style[si],BS_HOLLOW
	je	pattern_preproc_error	;Hollow brush.	Abort with an error

	mov	al,oem_brush_accel[si]	;Save EGA brush accelerator
	mov	cl_brush_accel,al

ifdef	GEN_COLOR_BLT
	shl	ch, 1			;What type of pattern fetch?
	js	pattern_preproc_end
	jnc	pattern_preproc_mono

;	This is a color ==> mono BLT.  The color brush must be processed
;	against the background and foreground colors as stated above,
;	giving a pseudo monochrome brush.
;
;	This new brush will be stored on the frame and the brush pointer
;	biased to point to it.

	les	di,lpDrawMode			; Get background color
	mov	bx,wptr es:bkColor.pcol_C0[di]	; DL = red, DH = green
	.errnz	pcol_C1 - pcol_C0 - 1
if NUMBER_PLANES eq 3
	mov	dx,wptr es:bkColor.pcol_C2[di]	; BL = blue = either FF or 00
else
	mov	dx,wptr es:bkColor.pcol_C2[di]	; BL = blue = either FF or 00
	.errnz	SPECIAL - pcol_C2 - 1
;;; Win1 has no intensity plane
;;;	and	bh,C3_BIT
;;;	neg	bh
;;;	sbb	bh,bh		; BH = intensity plane = either FF or 00
endif
	mov	ax,ss
	mov	es,ax
	lea	di,cl_a_brush		;ES:DI --> temp brush area
	mov	cx,SIZE_PATTERN		;Set loop count
pattern_preproc_color:
	lodsb				;Get red plane
	mov	ah, oem_brush_C1-1[si]	;Get green plane
	xor	ax, dx			;Set matching bits to 0
if NUMBER_PLANES eq 3
	or	ah,al
	mov	al,oem_brush_C2-1[si]	;Process blue plane
	xor	al,bl
else
	xchg	di,ax
	mov	al,oem_brush_C2-1[si]	;Process blue plane
	mov	ah,oem_brush_C3-1[si]	;Process intensity plane
	xor	ax,bx
	or	ax,di
endif
	or	al,ah			;Combine red and green
	not	al			;Do final inversion
	stosb				;  and store the byte
	loop	pattern_preproc_color

	mov	seg_lpPBrush,es		;Set segment of brush
	lea	si,-oem_brush_style[di]	;Set up for offsetting mono brush	
pattern_preproc_mono:
endif	;GEN_COLOR_BLT
	add	si, oem_brush_mono
	mov	off_lpPBrush, si
	jmp	short pattern_preproc_end

pattern_preproc_error:
	jmp	complain

pattern_preproc_end:
	mov	si, xExt
	or	si, si
	jz	pattern_preproc_error
	mov	di, yExt
	or	di, di
	jz	pattern_preproc_error

	subttl	Cursor Exclusion
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Cursor Exclusion
;
;	If either device or both devices are for the display, then
;	the cursor must be excluded.  If both devices are the display,
;	then a union of both rectangles must be performed to determine
;	the exclusion area.
;
;	Currently:
;		SI = X extent
;		DI = Y extent
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

cursor_exclusion:

ifdef	EXCLUSION
	dec	si			;Make the extents inclusive of the
	dec	di			;  last point

	mov	al,gl_the_flags
	and	al,F0_SRC_IS_DEV+F0_DEST_IS_DEV	;Are both memory bitmaps?
	jz	cursor_exclusion_end	;  Yes, no exclusion needed

	mov	cx,DestxOrg		;Assume only a destination on the
	mov	dx,DestyOrg		;  display
	test	al,F0_SRC_IS_DEV	;Is the source a memory bitmap?
	jz	cursor_exclusion_no_union;  Yes, go set right and bottom
	test	al,F0_DEST_IS_DEV	;  (set 'Z' if dest is memory)
	mov	ax,cx			;  No, prepare for the union
	mov	bx,dx

	mov	cx,SrcxOrg		;Set source org
	mov	dx,SrcyOrg
	jz	cursor_exclusion_no_union;Dest is memory. Set right and bottom

;	If the source/destination starting Y is greater than SCREEN_HEIGHT,
;	then the blt is supporting a save_screen_bitmap call.  In this case,
;	we only want to exclude whichever rectangle is visible.
;
; (This does not appear to happen in WIN1) 
;
;;;	cmp	bx,SCREEN_HEIGHT	  ;If destination is off the screen
;;;	jge	cursor_exclusion_no_union ;  then only use source rectangle
;;;	cmp	dx,SCREEN_HEIGHT	  ;If source is off the screen
;;;	jl	cursor_exclusion_not_ssb  ;  then only use dest rectangle
;;;	xchg	ax,cx
;;;	mov	dx,bx
;;;	jmp	short cursor_exclusion_no_union


;	The union of the two rectangles must be performed.  The top left
;	corner will be the smallest x and smallest y.  The bottom right
;	corner will be the largest x and the largest y added into the
;	extents

cursor_exclusion_not_ssb:
	cmp	cx,ax			;Get smallest x
	jle	cursor_exclusion_y	;CX is smallest
	xchg	ax,cx			;AX is smallest

cursor_exclusion_y:
	cmp	dx,bx			;Get smallest y
	jle	cursor_exclusion_union	;DX is smallest
	xchg	dx,bx			;BX is smallest

cursor_exclusion_union:
	add	si,ax			;Set right
	add	di,bx			;Set bottom
	jmp	short cursor_exclusion_do_it	;Go do exclusion

cursor_exclusion_no_union:
	add	si,cx			;Set right
	add	di,dx			;Set bottom

cursor_exclusion_do_it:
	call	exclude 		;Exclude the area from the screen

endif	;EXCLUSION

	mov	ax, GRAF_DATA_ROT
;;;	mov	dx, EGA_BASE + GRAF_ADDR ; XXX Something's inserting 
					 ;NOPs here again
	db	0BAh
	dw	EGA_BASE + GRAF_ADDR
	mov	cs:ega_state_rot, ax
	mov	byte ptr cs:ega_saved, 4
	out	dx, ax			;Reset EGA rotate register
	mov	ax, 0FF00h + GRAF_BIT_MASK
	mov	cs:ega_state_graf, ax
	out	dx, ax			;Reset EGA colour don't care register
	mov	ax, GRAF_MODE
	mov	cs:ega_state_mode, ax
	out	dx, ax
	
cursor_exclusion_end:
	subttl	Phase Processing (X)
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Now the real work comes along:  In which direction will the
;	copy be done?  Refer to the 10 possible types of overlap that
;	can occur (10 cases, 4 resulting types of action required).
;
;	If there is no source bitmap involved in this particular BLT,
;	then the path followed must allow for this.  This is done by
;	setting both the destination and source parameters equal.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

phase_processing:
phase_processing_x:
	mov	dx,xExt 		;Get X extent
	dec	dx			;Make X extent inclusive

	mov	bx,DestxOrg		;Get destination X origin
	mov	di,bx
	and	bx, wptr 00000111b	;Get offset of destination within byte
					;   and set up BX for a base register!

;	If there is no source, then just use the pointer to the destination
;	bitmap and load the same parameters, which will cause the "equality"
;	path to be followed in the set-up code.  This path is the favored
;	path for the case of no source bitmap.


	mov	ax,di			;Assume no source needed
;;;	test	gl_the_flags,F0_SRC_PRESENT;Is a source needed?
	cmp	gl_src_present, bh
	jz	phase_proc_10		;  No, just use destination parameters
	mov	ax,SrcxOrg		;  Yes, get source origin X
	mov	gl_first_fetch,2	;  Assume two initial fetches (if no
					;    source, then it will be set = 1
					;    later)
phase_proc_10:
	mov	si,ax
	and	ax,00000111b		;Get offset of source within byte

	cmp	si,di			;Which direction will we be moving?
	jl	phase_proc_30		;Move from right to left




;	The starting X of the source rectangle is >= the starting X of
;	the destination rectangle, therefore we will be moving bytes
;	starting from the left and stepping right.
;
;	Alternatively, this is the path taken if there is no source
;	bitmap for the current BLT.
;
;	Rectangle cases: 3,4,5,6,8

	sub	al,bl			;Compute horiz. phase  (source-dest)
	mov	gl_step_direction,STEPRIGHT ;Set direction of move
	mov	ch,cs:[bx].bitmask_tbl1	;Get starting byte mask
	ja	phase_proc_20		;Scan line case 2, everything is
					;  already set for this case.



;	Scan line cases 1 and 3:
;
;	The correct first byte fetch needs to be set for the beginning
;	of the outer loop, and the phase must be made into a positive
;	number.
;
;	This is the path that will be followed if there is no source bitmap
;	for the current BLT.

	mov	gl_first_fetch,1	;Set one initial fetch




;	We now have the correct phase and the correct first character fetch
;	routine set.  Save the phase and ...
;
;	currently:   AL = phase
;		     BL = dest start mod 8
;		     CH = first byte mask
;		     DX = inclusive X bit count
;		     SI = source X start (if there is a source)
;		     DI = destination X start
;

phase_proc_20:
	add	al,8			;Phase must be positive
	and	al,00000111b



;	To calculate the last byte mask, the inclusive count can be
;	added to the start X MOD 8 value, and the result taken MOD 8.
;	This is attractive since this is what is needed later for
;	calculating the inclusive byte count, so save the result
;	of the addition for later.

	add	bx,dx			;Add inclusive extent to dest MOD 8
	mov	dx,bx			;Save for innerloop count !!!
	and	bx,wptr 00000111b		;Set up bx for a base reg
	mov	cl,cs:[bx].bitmask_tbl2	;Get last byte mask

	mov	bl,al			;Compute offset into phase mask table
	add	bx,bx
	mov	bx,cs:[bx].phase_tbl1	;Get the phase mask


;	Currently:
;		AL = phase
;		BX = phase mask
;		CL = last byte mask
;		CH = first byte mask
;		DX = inclusive bit count + dest start MOD 8
;		SI = source X start (if there is a source)
;		DI = destination starting X

	jmp	short phase_proc_50	;Finish here






;	The starting X of the source rectangle is < the X of the destination
;	rectangle, therefore we will be moving bytes starting from the right
;	and stepping left.
;
;	This code should never be reached if there is no source bitmap
;	for the current BLT.
;
;	Rectangle cases: 1,2,7

phase_proc_30:
	mov	gl_step_direction,ah	;Set direction of move
	errnz	STEPLEFT
	mov	cl,cs:[bx].bitmask_tbl1	;Get last byte mask
	add	ax,dx			;Find end of the source


;	To calculate the first byte mask, the inclusive count is
;	added to the start MOD 8 value, and the result taken MOD 8.
;	This is attractive since this is what is needed later for
;	calculating the inclusive byte count, so save the result
;	of the addition for later.

	add	bx,dx			;Find end of the destination
	add	di,dx			;Will need to update dest start address
	add	si,dx			;  and source's too
	mov	dx,bx			;Save inclusive bit count + start MOD 8
	and	ax,00000111b		;Get source offset within byte
	and	bx,wptr 00000111b		;Get dest   offset within byte
	mov	ch,cs:[bx].bitmask_tbl2	;Get start byte mask
	sub	al,bl			;Compute horiz. phase  (source-dest)
	jb	phase_proc_40		;Scan line case 5, everything is
					;  already set for this case.



;	Scan line cases 4 and 6:
;
;	The correct first byte fetch needs to be set for the beginning
;	of the outer loop

	mov	gl_first_fetch,1	;Set initial fetch routine


phase_proc_40:
	add	al,8			;Ensure phase positive
	and	al,00000111b




;	We now have the correct phase and the correct first character fetch
;	routine set.  Generate the phase mask and save it.
;
;	currently:   AL = phase
;		     CH = first byte mask
;		     CL = last byte mask
;		     DX = inclusive bit count + start MOD 8

	mov	ah,cl			;Save last mask
	mov	cl,al			;Create the phase mask
	mov	bx,00FFh		;  by shifting this
	shl	bx,cl			;  according to the phase
	mov	cl,ah			;Restore last mask
;	jmp	phase_proc_50		;Go compute # of bytes to BLT
	errn$	phase_proc_50




; The different processing for the different X directions has been
; completed, and the processing which is the same regardless of
; the X direction is about to begin.
;
; The phase mask, the first/last byte masks, the X byte offsets,
; and the number of innerloop bytes must be calculated.
;
;
; Nasty stuff coming up here!  We now have to determine how
; many bits will be BLTed and how they are aligned within the bytes.
; This is how it's done (or how I'm going to do it):
;
; The number of bits (inclusive number that is) is added to the
; start MOD 8 value ( the left side of the rectangle, minimum X
; value), then the result is divided by 8. Then:
;
;
;    1)	If the result is 0, then only one destination byte is being
;	BLTed.	In this case, the start & ending masks will be ANDed
;	together, the innerloop count (# of full bytes to BLT) will
;	be zeroed, and the gl_last_mask set to all 0's (don't alter any
;	bits in last byte which will be the byte following the first
;	(and only) byte).
;
;		|      x x x x x|		|
;		|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|
;		 0 1 2 3 4 5 6 7
;
;		start MOD 8 = 3,  extent-1 = 4
;		3+7 DIV 8 = 0, only altering one byte
;
;
;
;    2)	If the result is 1, then only two bytes will be BLTed.
;	In this case, the start and ending masks are valid, and
;	all that needs to be done is set the innerloop count to 0.
;	(it is true that the last byte could have all bits affected
;	the same as if the innerloop count was set to 1 and the
;	last byte mask was set to 0, but I don't think there would be
;	much time saved special casing this).
;
;		|  x x x x x x x|x x x x x x x|
;		|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|
;		 0 1 2 3 4 5 6 7
;
;		start MOD 8 = 1,  extent-1 = 14
;		3+14 DIV 8 = 1.  There is a first and last
;		byte but no innerloop count
;
;
;
;    3)	If the result is >1, then there is some number of entire
;	bytes to be BLted by the innerloop.  In this case the
;	number of innerloop bytes will be the result - 1.
;
;		|	       x|x x x x x x x x|x
;		|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|
;		 0 1 2 3 4 5 6 7
;
;		start MOD 8 = 7,  extent-1 = 9
;		7+9  DIV 8 = 2.  There is a first and last
;		byte and an innerloop count of 1 (result - 1)
;
;	Currently:	AL = horizontal phase
;			BX = horizontal phase mask
;			CH = first byte mask
;			CL = last byte mask
;			DX = left side X MOD 8 + inclusive X count
;			SI = source start X
;			DI = dest   start X


phase_proc_50:
	mov	gl_phase_h,al		;Save horizontal phase
	mov	gl_mask_p,bx		;Save phase mask
	shr	dx,1			;/8 to get full byte count
	shr	dx,1
	shr	dx,1
	jnz	phase_proc_60		;Result is >0, check it out


;	There will only be one byte affected.  Therefore the two byte masks
;	must be combined, the last byte mask cleared, and the innerloop
;	count set to zero.

	and	ch,cl			;Combine the two masks
	xor	cl,cl			;Clear out the last byte mask
	inc	dx			;Now just fall through to set
	errn$	phase_proc_60		;  the innerloop count to 0!


phase_proc_60:
	dec	dx			;Dec count (might become 0 just like
	mov	gl_inner_loop_count,dx 	;  we want), and save it
	mov	bl,ch
	mov	ch,cl			;Compute last byte mask
	not	cl			;  and save it
	mov	gl_last_mask,cx
	mov	bh,bl			;Compute start byte mask
	not	bl			;  and save it
	mov	gl_start_mask,bx



;	There may or may not be a source bitmap for the following address
;	computation.  If there is no source, then the vertical setup code
;	will be entered with both the source and destination Y's set to the
;	destination Y and the address calculation skipped.  If there is a
;	source, then the address calculation will be performed and the
;	vertical setup code entered with both the source and destination Y's.

phase_processing_y:
	shiftr	di,3			;Compute byte offset of destination
					;  and add to current destination
					;  offset
	add	wptr lpDestDev, di

	mov	bx,DestyOrg		;Get destination Y origin
	mov	cx,bx			;Assume no source
	cmp	gl_src_present, 0	;Is a source needed?
;;;	mov	cl,gl_the_flags
;;;	test	cl,F0_SRC_PRESENT	;Is a source needed?
	jz	phase_proc_70		;  No, skip source set-up

	shiftr	si,3			;Compute byte offset of source
					;  and add to current source offset
;;;	add	wptr gl_src.lp_bits[0],si
	add	wptr lpSrcDev, si
	mov	cx,SrcyOrg		;Get source Y origin



	subttl	Phase Processing (Y)
	page

;	The horizontal parameters have been calculated.  Now the vertical
;	parameters must be calculated.
;
;	Currently:
;		DX = destination Y origin
;		CX = source Y origin (destination origin if no source)

phase_proc_70:
	mov	ax,yExt 		;Get the Y extent of the BLT
	mov	dh, INCREASE



;	The BLT will be Y+ if the top of the source is below or equal
;	to the top of the destination (cases: 1,4,5,7,8).  The BLT
;	will be Y- if the top of the source is above the top of the
;	destination (cases: 2,3,6)
;
;
;		  !...................!
;		  !D		      !
;	      ____!		..x   !
;	     |S   !		  :   !     Start at top of S walking down
;	     |	  !		      !
;	     |	  !...................!
;	     |			  :
;	     |____________________:
;
;
;	      __________________
;	     |S 		|
;	     |	  .....................     Start at bottom of S walking up
;	     |	  !D		      !
;	     |	  !		:     !
;	     |____!	      ..x     !
;		  !		      !
;		  !....................


;;;	mov	ch,INCREASE		;Set Y direction for top to bottom
	cmp	cx,bx			;Which direction do we move?
	jge	phase_proc_80		;Step down screen (cases: 1,4,5,7,8)


;	Direction will be from bottom of the screen up (Y-)
;
;	This code will not be executed if there is no source since
;	both Y's were set to the destination Y.

	dec	ax
	add	bx,ax			;Find bottom scan line index for
	add	cx,ax			;  destination and source
	mov	dh,DECREASE		;Set pattern increment

phase_proc_80:
	mov	gl_pat_row,bl		;Set pattern row and increment
	mov	gl_direction,dh
	mov	di, gl_dest_width_bytes
	mov	ax, di
	mul	bx
	add	wptr lpDestDev, ax
	test	gl_direction, 80h
	jz	phase_proc_81
	neg	di
phase_proc_81:	
	mov	gl_dest_increment, di

;	The Y direction has been computed.  Compute the rest of the
;	Y parameters.  These include the actual starting address,
;	the scan line and plane increment values, and whether or not
;	the extents will cross a 64K boundary.
;
;	Currently:
;		DX = Y of starting destination scan
;		AX = Y of starting source scan
;		CH = BLT direction
;		       00 = increasing BLT, Y+
;		       FF = decreasing BLT, Y-
;		CL = gl_the_flags
;		BX = inclusive Y extent


phase_proc_90:
	cmp	gl_src_present, 0	;Is a source needed?
	jz	phase_proc_100		;  No, skip source set-up
	mov	di, gl_src_width_bytes	;Source width bytes
	mov	ax, di
	mul	cx
	add	wptr lpSrcDev,ax
	test	gl_direction, 80h
	jz	phase_proc_91
	neg	di
phase_proc_91:
	mov	gl_src_increment, di
phase_proc_100:
;
; I think this corresponds to the subroutine check_device_special_cases in 
; the Windows 2 driver.
;
	mov	dh, gl_the_flags
	mov	al, bptr (Rop)
	test	al, 1Ch
	jnz	cblt_allocate
	test	al, 3
	jz	X0943
	mov	bl, cl_brush_accel
	shl	al, 1
	jns	X0916
	mov	bl, 87h
	mov	cl_brush_accel, 80h
X0916:	or	bl, bl
	js	X092E
	test	bl, 40h
	jz	cblt_allocate
	mov	ds, seg_lpPBrush
	mov	cx, 5
	shl	al, 1
	cbw
	not	ah
	mov	bl, ah
	jmp	short X093B
;
X092E:	shl	al, 1
	cbw
	not	ah
	xor	bl, ah
	and	bl, 7
	mov	cx, 205h
X093B:	test	dh, 2
	jz	cblt_allocate
	jmp	ega_solid_pat

X0943:	test	gl_phase_h, 0FFh
	jnz	cblt_allocate
	and	dh, 0Ah
	cmp	dh, 0Ah
	jnz	cblt_allocate
	jmp	ega_src_copy
;
	subttl	Memory allocation for BLT compilation
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Allow room for the BLT code.  The maximum that can be generated
;	is defined by the variable MAX_BLT_SIZE.  This variable must be
;	an even number.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

	assumes cs,Code
	assumes ds,nothing
	assumes es,nothing


cblt_allocate:

	?CHKSTKPROC MAX_BLT_SIZE+20h	;See if room on stack			 ;See if room
	jnc	cblt_alloc_stack_ok	;There was room
	jmp	bitblt_exit_fail	;There was no room

cblt_alloc_stack_ok:
	add	sp,20h			;Take off the slop

	mov	di,sp
	mov	off_gl_blt_addr,di	;Save the address for later
	mov	ax,ss			;Set the segment for the BLT
	mov	es,ax

ifdef	THIS_IS_DOS_3_STUFF
else
	assumes ss,InstanceData
	mov	ax,proc_cs_alias
	assumes ss,nothing
endif

	mov	seg_gl_blt_addr,ax	;Save the address for later
	mov	ax,cs			;Set data seg to CS so we can access
	mov	ds,ax			;  code without overrides
	xor	cx,cx			;Clear out count register
;
; Windows 1 inlines this; in Windows 2 it's a separate subroutine, CBLT.
;
	assumes ds,Code

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Pattern Fetch Code
;
;	The pattern fetch code will be created on the fly since
;	most of the instructions need fixups.
;
;	This template is really just a comment to indicate what
;	the generated code should look like.
;
;	Entry:	None
;
;	Exit:	DH = pattern
;
;	Uses:	AX,BX,CX,DH,flags
;
;
;	The following registers are available to the pattern fetch
;	logic (as implemented herein):
;
;		AX,BX,CX,DX,flags
;
;
;	For monochrome brushes:
;
;	    mov     ax,1234h		;Load segment of the brush
;	    mov     bx,1234h		;Load offset of the brush
;	    mov     cx,ds		;Save DS
;	    mov     ds,ax		;DS:BX --> brush
;	    mov     dh,7[bx]		;Get next brush byte
;	    mov     al,ss:[1234h]	;Get brush index
;	    add     al,gl_direction	;Add displacement to next byte (+1/-1)
;	    and     al,00000111b	;Keep it in range
;	    mov     ss:[1234h],al	;Store displacement to next byte
;	    mov     ds,cx		;Restore DS
;
;
ifdef	GEN_COLOR_BLT
;	For color brushes:
;
;	    mov     ax,1234h		;Load segment of the brush
;	    mov     bx,1234h		;Load offset of the brush
;	    mov     cx,ds		;Save DS
;	    mov     ds,ax		;DS:BX --> brush
;	    mov     dh,7[bx]		;Get next brush byte
;	    mov     al,ss:[1234h]	;Get brush index
;	    add     al,SIZE Pattern	;Add disp. to next plane's bits
;	    and     al,00011111b	;Keep it within the brush
;	    mov     ss:[1234h],al	;Store disp. to next plane's bits
;	    mov     ds,cx		;Restore DS
;
endif
;
;	For both templates, SS:[1234] is the address of the 7 in the
;	"mov dh,7[bx]" instruction.  This is the index to this scan's
;	bit pattern in the brush.  This value will range from 0 to
;	(SIZE pattern)-1 for monochrome devices, and from 0 to
;	((NumberPlanes)*(SIZE pattern))-1 for color devices.
;
ifdef	GEN_COLOR_BLT
;	For color brushes, SS:[1234] must also be fixed up when the next
;	scan line is selected, else it would index into the monochrome
;	portion of the brush (e.g. 1,9,17,25, where 25 is not part of the
;	color brush).
endif
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

	page
;-----------------------------Public-Routine----------------------------;
; CBLT
;
; Compile a BLT onto the stack.
;
; Entry:
;	ES:DI --> memory on stack to receive BLT program
; Returns:
;	Nothing
; Registers Preserved:
; Registers Destroyed:
; Calls:
;	y_update
; History:
;  Sun 16-Aug-1987 16:45:47 -by-  ****** *. ***** [*******]
; Bitmap Color Conversion uses image color
;  Mon 20-Jul-1987 17:30:14 -by-  ****** *. ***** [*******]
; Added 4-plane support.
;  Sun 22-Feb-1987 16:29:09 -by-  **** ***** [*****]
; Wrote it for Windows in distant past.
;-----------------------------------------------------------------------;

;;;ifdef	GEN_COLOR_BLT
;;;	mov	ax,(PLANE_1*256)+I_MOV_BL_BYTE_I
;;;	stosw
;;;endif

	subttl	Compile - Outer Loop
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Create the outerloop code.  The first part of this code will save
;	the scan line count register, destination pointer, and the source
;	pointer (if there is a source).
;
;
;	The generated code should look like:
;
;		push	cx		;Save scan line count
;		push	di		;Save destination pointer
;	<	push	si	>	;Save source pointer
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

	mov	bl,gl_the_flags
	mov	ax,I_PUSH_CX_PUSH_DI	;Save scan line count, destination ptr
	stosw
	test	bl,F0_SRC_PRESENT	;Is a source needed?
	jz	cblt_2020		;  No
	mov	al,I_PUSH_SI		;  Yes, save source pointer
	stosb

cblt_2020:



ifdef	GEN_COLOR_BLT
	subttl	Compile - Plane Selection
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	If the destination device is color and the display is involved in
;	the blt, then the color plane selection logic must be added in.
;	If the destination is monochrome, then no plane logic is needed.
;	Two color memory bitmaps will not cause the plane selection logic
;	to be copied.
;
;
;	The generated code should look like:
;
;	<	push	bx	>	;Save plane index
;	<	plane selection >	;Select plane
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


	test	bl,F0_DEST_IS_COLOR	;Is the destination color?
	jz	cblt_pattern_fetch	;  No
	mov	al,I_PUSH_BX		;Save plane index
	stosb
	test	bl,F0_DEST_IS_DEV+F0_SRC_IS_DEV	;Is the device involved?
	jz	cblt_pattern_fetch		;  No


;	The device is involved for a color blt.  Copy the logic for selecting
;	the read/write plane, and perform any fixups that are needed.

	mov	al, I_MOV_AX_WORD_I
	stosb
	mov	ax, cs
	stosw				;MOV AX,seg

	mov	si,CodeOFFSET cps	;--> plane select logic
	mov	cx,LENGTH_CPS/2
	rep	movsw
if	LENGTH_CPS AND 1
	movsb
endif
	lea	ax, ega_state_mask
	mov	es:[di-0Dh], ax

endif	;GEN_COLOR_BLT



	subttl	Compile - Pattern Fetch
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Set up any pattern fetch code that might be needed.
;	The pattern code has many fixups, so it isn't taken from a
;	template.  It is just stuffed as it is created.
;
;
;	Entry:	None
;
;	Exit:	DH = pattern
;
;	Uses:	AX,BX,CX,DH,flags
;
;
;	For monochrome brushes:
;
;	    mov     ax,1234h		;Load segment of the brush
;	    mov     bx,1234h		;Load offset of the brush
;	    mov     cx,ds		;Save DS
;	    mov     ds,ax		;DS:BX --> brush
;	    mov     dh,7[bx]		;Get next brush byte
;	    mov     al,ss:[1234h]	;Get brush index
;	    add     al,gl_direction	;Add displacement to next byte (+1/-1)
;	    and     al,00000111b	;Keep it in range
;	    mov     ss:[1234h],al	;Store displacement to next byte
;	    mov     ds,cx		;Restore DS
;
;
ifdef	GEN_COLOR_BLT
;	For color brushes:
;
;	    mov     ax,1234h		;Load segment of the brush
;	    mov     bx,1234h		;Load offset of the brush
;	    mov     cx,ds		;Save DS
;	    mov     ds,ax		;DS:BX --> brush
;	    mov     dh,7[bx]		;Get next brush byte
;	    mov     al,ss:[1234h]	;Get brush index
;	    add     al,SIZE Pattern	;Add displacement to next plane's bits
;	    and     al,00011111b	;Keep it within the brush
;	    mov     ss:[1234h],al	;Store displacement to next plane's bits
;	    mov     ds,cx		;Restore DS
;
;	    The address of the increment for the brush is saved for
;	    the plane looping logic if the destination is a three plane
;	    color device.  For a four plane color device, the AND
;	    automatically handles the wrap and no fixup is needed at
;	    the end of the plane loop.
endif
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

cblt_pattern_fetch:
	test	bl,F0_PAT_PRESENT	;Is a pattern needed?
	jz	cblt_initial_byte_fetch ;  No, skip pattern code

	mov	al,I_MOV_AX_WORD_I 	;mov ax,SEG_lpPBrush
	stosb
	mov	ax,seg_lpPBrush
	stosw
	mov	al,I_MOV_BX_WORD_I 	;mov bx,OFF_lpPBrush
	stosb
	mov	ax,off_lpPBrush
	stosw
	mov	ax,I_MOV_CX_DS		;mov cx,ds
	stosw
	mov	ax,I_MOV_DS_AX		;mov ds,ax
	stosw
	mov	ax,I_MOV_DH_BX_DISP8	;mov dh,gl_pat_row[bx]
	stosw
	mov	dx,di			;Save address of the brush index
	mov	al,gl_pat_row		;Set initial pattern row
	mov	bh,00000111b		;Set brush index mask
	and	al,bh			;Make sure it's legal at start
	stosb
	mov	ax,I_CS_OVERRIDE+(I_MOV_AL_MEM*256)
	stosw				;mov al,ss:[xxxx]
	mov	ax,dx
	stosw
	mov	al,I_ADD_AL_BYTE_I
	mov	ah,gl_direction		;Set brush index
	errnz	INCREASE-1		;Must be a 1
	errnz	DECREASE+1		;Must be a -1

ifdef	GEN_COLOR_BLT
	test	bl,F0_COLOR_PAT		;Color pattern required?
	jz	cblt_2060		;  No

	mov	ah,SIZE_PATTERN		;Set increment to next plane
ifndef	FOUR_PLANE
	mov	dl_addr_brush_index,dx	;Save address of brush index
endif

	mov	bh,00011111b		;Set brush index mask

cblt_2060:
endif
	stosw
	mov	ah,bh			;and al,BrushIndexMask
	mov	al,I_AND_AL_BYTE_I
	stosw
	mov	ax,I_CS_OVERRIDE+(I_MOV_MEM_AL*256)
	stosw				;mov ss:[xxxx],al
	mov	ax,dx
	stosw
	mov	ax,I_MOV_DS_CX		;mov ds,cx
	stosw

	subttl	Compile - Initial Byte Fetch
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Create the initial byte code.  This may consist of one or two
;	initial fetches (if there is a source), followed by the required
;	logic action.  The code should look something like:
;
;	BLTouterloop:
;	<	mov	bp,gl_mask_p >  ;Load phase mask for entire loop
;	<	xor	bh,bh	    >	;Clear previous unused bits
;
;	;	Perform first byte fetch
;
;	<	lodsb		    >	;Get source byte
ifdef	GEN_COLOR_BLT
;	<	color<==>mono munge >	;Color <==> mono conversion
endif
;	<	phase alignment     >	;Align bits as needed
;
;	;	If an optional second fetch is needed, perform one
;
;	<	lodsb		    >	;Get source byte
ifdef	GEN_COLOR_BLT
;	<	color to mono munge >	;Color to mono munging
endif
;	<	phase alignment     >	;Align bits as needed
;
;		logical action		;Perform logical action required
;
;		mov	ah,es:[di]	;Get destination
;		and	ax,cx		;Saved unaltered bits
;		or	al,ah		;  and mask in altered bits
;		stosb			;Save the result
;
;
;	The starting address of the first fetch/logical combination will be
;	saved so that the code can be copied later instead of recreating it
;	(if there are two fecthes, the first fetch will not be copied)
;
;	The length of the code up to the masking for altered/unaltered bits
;	will be saved so the code can be copied into the inner loop.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


cblt_initial_byte_fetch:
	xor	dx,dx
	or	dh,gl_phase_h		;Is the phase 0? (also get the phase)
	jz	cblt_3020		;  Yes, so no phase alignment needed
	mov	al,I_MOV_BP_WORD_I 	;Set up the phase mask
	stosb
	mov	ax,gl_mask_p		;Place the mask into the instruction
	stosw
	mov	ax,I_XOR_BH_BH		;Clear previous unused bits
	stosw

cblt_3020:
	mov	gl_start_fl,di		;Save starting address of action
;;;	test	gl_the_flags,F0_SRC_PRESENT ;Is there a source?
	or	dl, gl_src_present	;Is there a source?
	jnz	cblt_3040		;  Yes, generate fetch code
	jmp	cblt_4000		;  No, don't generate fetch code



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Generate the required sequence of instructions for a fetch
;	sequence.  Only the minimum code required is generated.
;
;	The code generated will look something like the following:
;
;	BLTfetch:
;	<	lodsb		      > ;Get the next byte
ifdef	GEN_COLOR_BLT
;	<	color munging	      > ;Mono <==> color munging
endif
;
;	;	If the phase alignment isn't zero, then generate the minimum
;	;	phase alignment needed.  RORs or ROLs will be generated,
;	;	depending on the fastest sequence.  If the phase alignment
;	;	is zero, than no phase alignment code will be generated.
;
;	<	ror	al,1	      > ;Rotate as needed
;	<	ror	al,1	      > ;Rotate as needed
;	<	ror	al,1	      > ;Rotate as needed
;	<	ror	al,1	      > ;Rotate as needed
;	<	mov	ah,al	      > ;Mask used, unused bits
;	<	and	ax,bp	      > ;(BP) = phase mask
;	<	or	al,bh	      > ;Mask in old unused bits
;	<	mov	bh,ah	      > ;Save new unused bits
;
;
;	The nice thing about the above is it is possible for the fetch to
;	degenerate into a simple LODSB instruction.
;
;	If this was a iAPX80286 implementation, if would be faster to
;	make three or four rotates into a "ror al,n" instruction.
;
;	Currently:	BL = gl_the_flags
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


cblt_3040:
ifdef	GEN_COLOR_BLT
	shl	bl,1			;Color conversion?
	jc	cblt_3060		;  Yes, gag and choke on it
	jmp	cblt_3180		;  No, we were lucky this time
	errnz	F0_GAG_CHOKE-10000000b

cblt_3060:
	mov	dl_moore_flags,0	;Assume REP cannot be used

	assumes ds,nothing

ifdef THIS_IS_DOS_3_STUFF
	lds	si,lpDrawMode		;--> background color
	lea	si,bkColor[si]		;  (lea preserves the flags)
else

; Here we use the knowledge that our brush is ddc_oem_brush (in DDC!).

	lds	si,lpPBrush		;--> background color
	ddc_check	<si - ddc_oem_brush>
	lea	si,[si][ddc_image_back_color_ours - ddc_oem_brush] ; preserves flags
endif
	js	cblt_3100		;Mono ==> color
	errnz	F0_COLOR_PAT-01000000b



	subttl	Compile - Initial Byte Fetch, Color ==> Mono
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Generate the code to go from color to mono.  Color to mono
;	should map all colors that are background to 1's (white), and
;	all colors which aren't background to 0's (black).  If the source
;	is the display, then the color compare register will be used.
;	If the source is a memory bitmap, each byte of the plane will be
;	XORed with the color from that plane, with the results all ORed
;	together.  The final result will then be complemented, giving
;	the desired result.
;
;	The generated code for bitmaps should look something like:
;
;	    mov     al,plane_w[si]	;Get C1 byte of source
;	    mov     ah,2*plane_w[si]	;Get C2 byte of source
;	    xor     ax,C1BkColor+(C2BkColor*256) ;XOR with plane's color
;	    or	    ah,al		;OR the result
;	if NUMBER_PLANES eq 4
;	    mov	    al,3*plane_w[si]	;Get C3 byte of source
;	    xor	    al,C3BkColor
;	    or	    ah,al
;	endif
;	    lodsb			;Get C0 source
;	    xor     al,C0BkColor 	;XOR with C0BkColor
;	    or	    al,ah		;OR with previous result
;	    not     al			;NOT to give 1's where background
;
;
;	    where plane_w is defined to be:
;
;		a)  bmWidthPlanes for bitmaps <64K
;		b)  bmWidthBytes  for bitmaps >64K
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


cblt_3070:
	test	bl,F0_SRC_IS_DEV SHL 1	;If device, use color compare register
	jz	cblt_3080		;It's a memory bitmap



;	We're in luck, the color compare register can be used.  Set up
;	for a color read, and use the normal mono fetch code.  Show the
;	innerloop code that the REP instruction can be used if this is
;	a source copy.


	mov	dl_moore_flags,F1_REP_OK;Show rep instructions ok in loop
	mov	cx,dx			;Save dx
	mov	ah,[si].SPECIAL		;Get SPECIAL byte of color
	and	ah, 7	; WIN1 MM_ALL

;;;XXX	mov	al,GRAF_COL_COMP	;Stuff color into compare register
	
;;;XXX	mov	dx,EGA_BASE+GRAF_ADDR
	db	0B0h, GRAF_COL_COMP	;mov al, GRAF_COL_COMP
	db	0BAh	;mov dx,
	dw	EGA_BASE+GRAF_ADDR
	out	dx,ax
;;;	mov	ax,GRAF_CDC		;Set Color Don't Care register
;;;	out16	dx,ax

;;;	push	ds
;;;	mov	ax,ScreenSelector	;Show color read mode to the
;;;	mov	ds,ax			;  EGA restoration code
;;;	assumes ds,EGAMem

	mov	ax,M_COLOR_READ SHL 8 + GRAF_MODE
	mov	cs:ega_state_mode,ax	    ;Must shadow this for state code
	out	dx,ax
;;;	pop	ds
;;;	assumes ds,nothing

	mov	dx,cx
	jmp	short cblt_3180		;Go generate mono fetch code


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	The source is a memory bitmap.	Generate the code to compute
;	the result of the three (or four!!!) planes:
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

cblt_3080:
	mov	ax,I_MOV_AL_SI_DISP16
	stosw
	mov	ax,gl_plane_w
	stosw
	mov	bx,ax			;(WIN2 xchg is one byte less than mov)
	add	bx,bx
	mov	ax,I_MOV_AH_SI_DISP16
	stosw
	mov	ax,bx
	stosw
	mov	al,I_XOR_AX_WORD_I
	stosb
	mov	ax,wptr [si].pcol_C1
	stosw
	errnz	<pcol_C2 - pcol_C1 - 1>
	mov	ax,I_OR_AH_AL
	stosw
if NUMBER_PLANES eq 4
;	    mov	    al,3*plane_w[si]	;Get C3 byte of source
;	    xor	    al,C3BkColor
;	    or	    ah,al
	mov	ax,I_MOV_AL_SI_DISP16
	stosw
	mov	ax,gl_src.plane_w
	add	ax,bx
	stosw
	mov	al,I_XOR_AL_BYTE_I
	mov	ah,[si].SPECIAL
	and	ah,C3_BIT
	neg	ah
	sbb	ah,ah
	stosw
	mov	ax,I_OR_AH_AL
	stosw
endif
	mov	ax,I_LODSB+(I_XOR_AL_BYTE_I*256)
	stosw
	movsb
	errnz	pcol_C0
	mov	ax,I_OR_AL_AH
	stosw
	mov	ax,I_NOT_AL
	stosw
	jmp	short cblt_3160		;Go create logic code

	subttl	Compile - Initial Byte Fetch, Mono ==> Color
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	The conversion is mono to color.  Generate the code to
;	do the conversion, and generate the table which will
;	have the conversion values in it.
;
;	When going from mono to color, 1 bits are considered to be
;	the background color, and 0 bits are considered to be the
;	foreground color.
;
;	For each plane:
;
;	  If the foreground=background=1, then 1 can be used in
;	  place of the source.
;
;	  If the foreground=background=0, then 0 can be used in
;	  place of the source.
;
;	  If the foreground=0 and background=1, then the source
;	  can be used as is.
;
;	  If the foreground=1 and background=0, then the source
;	  must be complemented before using.
;
;	  Looks like a boolean function to me.
;
;	An AND mask and an XOR mask will be computed for each plane,
;	based on the above.  The source will then be processed against
;	the table.  The generated code should look like
;
;		lodsb
;		and	al,ss:[xxxx]
;		xor	al,ss:[xxxx+1]
;
;
;	The table for munging the colors as stated above should look like:
;
;	     BackGnd   ForeGnd	  Result    AND  XOR
;		1	  1	    1	     00   FF
;		0	  0	    0	     00   00
;		1	  0	    S	     FF   00
;		0	  1	not S	     FF   FF
;
;	From this, it can be seen that the XOR mask is the same as the
;	foreground color.  The AND mask is the XOR of the foreground
;	and the background color.  Not too hard to compute
;
;
;	It can also be seen that if the background color is white and the
;	foreground (text) color is black, then the conversion needn't be
;	generated (it just gives the source).  This is advantageous since
;	it will allow phased aligned source copies to use REP MOVSW.
;
;
;	Currently:	ds:si --> bkColor in lpDrawMode
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

	errnz	TextColor-bkColor-4	;Must be contiguous

ifdef THIS_IS_DOS_3_STUFF
DIFF4	equ	(TextColor - bkColor)
else
DIFF4	equ	(ddc_image_color_ours - ddc_image_back_color_ours)
	.errnz	ddc_image_back_color_ours - ddc_image_color_ours - 8 ; needed?
endif

;++++++++++++++++++++++++++++++++++
;	Check to see if the background color is black, and the
;	foreground color is white.  This can be determined by
;	looking at the accelerator flags in the physical color.

cblt_3100:
	mov	ah,bptr [si].SPECIAL
	xor	ah, 47h			;Map black to white
	or	ah,[si][DIFF4].SPECIAL 	;AND in forground color
;;;	cmp	ah,MONO_BIT+ONES_OR_ZEROS
	jne	cblt_3110		;Not black
	mov	dl_moore_flags,F1_REP_OK+F1_NO_MUNGE;Show reps as ok, no color munge table
	jmp	short cblt_3170		;Normal fetch required

;	No way around it.  The color conversion table and code
;	must be generated.

cblt_3110:
	.errnz	TextColor - bkColor - 4
ifdef THIS_IS_DOS_3_STUFF
	mov	ah,DIFF4[si]		;Get foreground Red color (00 or FF)
	lodsb				;Get background Red color (00 or FF)
	xor	al,ah
	mov	wptr cl_a_brush.(pcol_C0 * 2),ax
	mov	ah,DIFF4[si]		;Get foreground Green color
	lodsb				;Get background Green color
	xor	al,ah
	mov	wptr cl_a_brush.(pcol_C1 * 2),ax
	mov	ah,DIFF4[si]		;Get foreground Blue color
	lodsb				;Get background Blue color
	xor	al,ah
	mov	wptr cl_a_brush.(pcol_C2 * 2),ax
else
	mov	cl,[si].SPECIAL		; Get BackGround Colors
	mov	ch,DIFF4[si].SPECIAL	; Get ForeGround Colors
	xor	cl,ch			      
	shr	cl,1
	sbb	al,al
	shr	ch,1
	sbb	ah,ah
	mov	wptr cl_a_brush.(pcol_C0 * 2),ax
	shr	cl,1
	sbb	al,al
	shr	ch,1
	sbb	ah,ah
	mov	wptr cl_a_brush.(pcol_C1 * 2),ax
	shr	cl,1
	sbb	al,al
	shr	ch,1
	sbb	ah,ah
	mov	wptr cl_a_brush.(pcol_C2 * 2),ax
if NUMBER_PLANES eq 4
	shr	cl,1
	sbb	al,al
	shr	ch,1
	sbb	ah,ah
	mov	wptr cl_a_brush.(pcol_C3 * 2),ax
endif
endif
	errnz	<TextColor - bkColor - 4>


;	Generate the code for munging the color as stated above.

	mov	ax,I_LODSB+(I_SS_OVERRIDE*256)
	stosw				;lodsb
	mov	ax,I_AND_AL_MEM		;and al,ss:[xxxx]
	stosw
	lea	ax,cl_a_brush		;  Set address of color munge
	stosw
	mov	bx,ax			;  Save address
	mov	al,I_SS_OVERRIDE 	;ss:
	stosb
	mov	ax,I_XOR_AL_MEM		;xor al,[xxxx]
	stosw
	lea	ax,1[bx]		;  Set address of XOR mask
	stosw
	jmp	short cblt_3160

;	Just need to generate the normal fetch sequence (lodsb)

cblt_3170:
cblt_3180:
	mov	al,I_LODSB		;Generate source fetch
	stosb
cblt_3160:
	mov	ax,cs			;Restore DS = CS
	mov	ds,ax


endif	;GEN_COLOR_BLT



	subttl	Compile - Phase Alignment
	page

	assumes ds,Code

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Generate the phase alignment if any.
;
;	It is assumed that AL contains the source byte
;
;	Currently:
;
;	    DS = CS
;	    DH = phase alignment
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

cblt_3240:
	xor	cx,cx			;Might have garbage in it
	or	dh,dh			;Any phase alignment?
	jz	cblt_3280		;  No, so skip alignment
	mov	cl,dh			;Get horizontal phase for rotating
	mov	ax,I_ROL_AL_1		;Assume rotate left n times
	cmp	cl,5			;4 or less rotates?
	jc	cblt_3260		;  Yes
	neg	cl			;  No, compute ROR count
	add	cl,8
	mov	ah,HIGH I_ROR_AL_1
	errnz	<(LOW I_ROL_AL_1)-(LOW I_ROR_AL_1)>

cblt_3260:
	rep	stosw			;Stuff the phase alignment rotates
					;  then the phase alignment code
	mov	si,CodeOFFSET phase_align
	mov	cl,(PHASE_ALIGN_LEN SHR 1)
	rep	movsw
if	PHASE_ALIGN_LEN AND 1
	movsb
endif

cblt_3280:
	dec	gl_first_fetch		;Generate another fetch?
	jz	cblt_4000		;  No

;	A second fetch needs to be stuffed.  Copy the one just created.

	mov	si,di			;Get start of fetch logic
	xchg	si,gl_start_fl		;Set new start, get old
	mov	cx,di			;Compute how long fetch is
	sub	cx,si			;  and move the bytes
	mov	ax,es
	mov	ds,ax
	rep	movsb
;;;	mov	ax,cs			;Must leave DS = CS  [WIN1 doesn't]
;;;	mov	ds,ax

	subttl	Compile - ROP Generation
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Create the logic action code
;
;	The given ROP will be converted into the actual code that
;	performs the ROP.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


SRC_IN_AL 	equ	00000001b	;Source field is in AL		(0)
DEST_IN_AH	equ	00000010b	;Destination field is in AH	(1)
PUSH_POP_FLAG	equ	00000100b	;Next push/pop is a pop 	(1)


;	Copy the ROP template into the BLT
; This is completely different in WIN1

cblt_4000:
	xor	dh,dh
	mov	cx,word ptr Rop
	cmp	cx,32
	jnz	cblt_4001
	jmp	cblt_4012

cblt_4001:
	shr	cx,1
	shr	cx,1
	mov	si,gl_operands			;XXX What is this?
	mov	dl,bp0b
	cmp	gl_src_present, 1
	jb	cblt_4003
	jnz	cblt_4002
	mov	ax,si
	and	al,3
	cmp	al,1
	jz	cblt_4003
cblt_4002:
	mov	ax, I_MOV_DL_AL
	stosw
cblt_4003:
	cmp	bp30,2	;XXX
	jb	cblt_4004
	mov	al, I_ES_OVERRIDE	;This looks similar to what was just
	stosb				;before cblt_4280 in the Win2 version
	mov	ax, I_MOV_AH_DEST	;MOV AH, ES:[DI]
	stosw
	or	dh, 2
cblt_4004:
	mov	ax, si
	and	ax, 3
	dec	ax
	jnz	cblt_4005
	test	dh, 1
	jz	cblt_4011
	and	dh, 0FEh
	mov	ax, I_MOV_AL_DL
	jmp	short cblt_4010
;
cblt_4005:
	dec	ax
	mov	ax, I_MOV_AL_DH
	jnz	cblt_4009
	mov	ax, I_MOV_AL_AH
	test	dh, 2
	jnz	cblt_4009
	mov	al, I_ES_OVERRIDE
	stosb
	mov	ax, I_MOV_AL_DEST
	jmp	short cblt_4009
;
cblt_4006:
	shr	cx, 1
	shr	cx, 1
	mov	bx, cx
	and	bx, wptr 0Ch
	mov	ax, I_NOT_AL		;Generate a negate
	jz	cblt_4009
	ror	si, 1
	ror	si, 1
	mov	ax, si
	and	ax, 3
	jnz	cblt_4007
	xor	dh, 4
	test	dh, 4
	jz	cblt_4007
	mov	ax, I_MOV_BL_AL
	stosw
	shl	cx, 1
	shl	cx, 1
	ror	si, 1
	ror	si, 1
	inc	dl
	jmp	short cblt_4004
;
cblt_4007:
	or	bx, ax
	cmp	ax, 2
	jnz	cblt_4008
	test	dh, 2
	jnz	cblt_4008
	mov	al, I_ES_OVERRIDE
	stosb	
	shr	bx, 1
	shr	bx, 1
cblt_4008:
	add	bx, bx
	mov	ax, word ptr cs:win1_roptable[bx]
cblt_4009:
	or	dh, 1
cblt_4010:
	stosw
cblt_4011:
	dec	dl
	jge	cblt_4006
cblt_4012:
	mov	gl_end_fl,di	;End of fetch / logic operation
	test	dh, 2
	jnz	cblt_4280

	subttl	Compile - Mask And Save
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Generate code to mask and save the result.  If the destination
;	isn't in a register, it will be loaded from ES:[DI] first.  The
;	mask operation will then be performed, and the result stored.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

	mov	al,I_ES_OVERRIDE 	;Load destination in AH
	stosb
	mov	ax,I_MOV_AH_DEST
	stosw

cblt_4280:
	mov	ax, cs
	mov	ds, ax
	mov	si,CodeOFFSET masked_store ;Move rest of masked store template
	movsw
	movsw
	movsw
	errnz	MASKED_STORE_LEN-6	;Must be six bytes long
	mov	ax,gl_start_mask	;Stuff start mask into
	xchg	ah,al			;  the template
	mov	es:MASKED_STORE_MASK[di],ax
	mov	gl_end_fls,di		;Save end of fetch/logic/store operation

	assumes ds,nothing



	subttl	Compile - Inner Loop Generation
	page

;	Now for the hard stuff; The inner loop (said with a "gasp!").
;
;	If there is no innerloop, then no code will be generated
;	(now that's fast!).

cblt_5000:
	mov	ax,es			;Set ds: to es: since code will be
	mov	ds,ax			;  copied from/to the stack
	mov	dx,gl_inner_loop_count 	;Get the loop count
	or	dx,dx			;If the count is null
;	jz	cblt_6000
	jz	cblt_5140		;  don't generate any code.



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	We have something for a loop count.  If this just happens to be
;	a source copy (S) with a phase of zero, then the innerloop degenerates
;	to a repeated MOVSB instruction.  This little special case is
;	worth checking for and handling!
;
;	Also, if this is one of the special cases {P, Pn, DDx, DDxn}, then it
;	will also be special cased since these are all pattern fills (pattern,
;	not pattern, 0, 1).
;
;	The same code can be shared for these routines, with the exception
;	that patterns use a STOSx instruction instead of a MOVSx instruction
;	and need a value loaded in AX
;
;
ifdef	GEN_COLOR_BLT
;	So we lied a little.  If a color conversion is going on, then the
;	REP MOVSB might not be usable.	If the F1_REP_OK flag has been set, then
;	we can use it.	The F1_REP_OK flag will be set for a mono ==> color
;	conversion where the background color is white and the foreground
;	color is black, or for a color ==> mono conversion with the screen
;	as the source (the color compare register will be used).
;
;	For the special cases {P, Pn, DDx, DDxn}, color conversion is
;	not possible, so ignore it for them.
endif
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

	mov	bl,bptr (Rop)		;Get the raster op
	test	bl,EPS_INDEX		;Can this be special cased?
	jnz	cblt_5500		;  No
	errnz	<HIGH EPS_INDEX>
	errnz	SPEC_PARSE_STR_INDEX	;The special case index must be 0

	test	bl,EPS_OFF		;Is this a source copy
	jz	cblt_5040		;  Yes
	errnz	<SOURCE_COPY AND 11b>	;Offset for source copy must be 0



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	We should have one of the following fill operations:
;
;		P	- Pattern
;		Pn	- NOT pattern
;		DDx	- 0 fill
;		DDxn	- 1 fill
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

	mov	ax,I_MOV_AL_0FFH 	;Assume this is a 0 or 1 fill
	test	bl,01h			;Is it 0 or 1 fill?
	jz	cblt_5020		;  Yes, initialize AX with 0FFh
	mov	ax,I_MOV_AL_DH		;  No,	initialize AX with pattern

	errnz	   PAT_COPY-0000000000100001b
	errnz	NOTPAT_COPY-0000000000000001b
	errnz	 FILL_BLACK-0000000001000010b
	errnz	 FILL_WHITE-0000000001100010b

cblt_5020:
	stosw
	mov	ax,I_MOV_AH_AL
	stosw
	mov	si,I_STOSB		;Set up for repeated code processor
	test	bl,LogPar		;If Pn or 0, then complement pattern
	jnz	cblt_5060		;  Is just P or 1
	errnz	<HIGH LogPar>
	mov	ax,I_NOT_AX		;  Is Pn or 0, complement AX
	stosw
	jmp	short cblt_5060

	errnz	   PAT_COPY-00100001b
	errnz	NOTPAT_COPY-00000001b
	errnz	 FILL_BLACK-01000010b
	errnz	 FILL_WHITE-01100010b




;	This is a source copy.	The phase must be zero for a source copy
;	to be condensed into a REP MOVSx.

cblt_5040:
	test	gl_phase_h,0FFh		;Is horizontal phase zero?
	jnz	cblt_5500		;  No, can't condense source copy
	mov	si,I_MOVSB		;Set register for moving bytes

ifdef	GEN_COLOR_BLT
;	For a color conversion, F1_REP_OK must be set.

	test	gl_the_flags,F0_GAG_CHOKE ;Color conversion?
	jz	cblt_5060		;  No, rep is OK to use
	test	dl_moore_flags,F1_REP_OK;  Yes, can we rep it?
	jz	cblt_5500		;    No, do it the hard way
endif



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	This is a source copy or pattern fill.	Process an odd byte with
;	a MOVSB or STOSB, then process the rest of the bytes with a REP
;	MOVSW or a REP STOSW.  If the REP isn't needed, leave it out.
;
;	Don't get caught on this like I did!  If the direction of the
;	BLT is from right to left (decrementing addresses), then both
;	the source and destination pointers must be decremented by one
;	so that the next two bytes are processed, not the next byte and
;	the byte just processed.  Also, after all words have been processed,
;	the source and destination pointers must be incremented by one to
;	point to the last byte (since the last MOVSW or STOSW would have
;	decremented both pointers by 2).
;
;	If the target machine is an 8086, then it would be well worth the
;	extra logic to align the fields on word boundaries before the MOVSxs
;	if at all possible.
;
;	The generated code should look something like:
;
;	WARP8:				     ;This code for moving left to right
;		movsb			     ;Process an odd byte
;		ld	cx,gl_inner_loop_count/2 ;Set word count
;		rep			     ;If a count, then repeat is needed
;		movsw			     ;Move words until done
;
;
;	WARP8:				     ;This code for moving left to right
;		movsb			     ;Process an odd byte
;		dec	si		     ;adjust pointer for moving words
;		dec	di
;		ld	cx,gl_inner_loop_count/2 ;Set word count
;		rep			     ;If a count, then repeat is needed
;		movsw			     ;Move words until done
;		inc	si		     ;adjust since words were moved
;		inc	di
;
;
;	Of course, if any part of the above routine isn't needed, it isn't
;	generated (i.e. the generated code might just be a single MOVSB)
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

cblt_5060:
	shr	dx,1			;Byte count / 2 for words
	jnc	cblt_5080		;  No odd byte to move
	mov	ax,si			;  Odd byte, move it
	stosb

cblt_5080:
	jz	cblt_5140		;No more bytes to move
	xor	bx,bx			;Flag as stepping from left to right
	cmp	bl,gl_step_direction	;Moving from the right to the left?
	errnz	STEPLEFT		;  (left direction must be zero)
	jnz	cblt_5100		;  No
	mov	ax,I_DEC_SI_DEC_DI	;  Yes, decrement both pointers
	stosw
	mov	bx,I_INC_SI_INC_DI	;Set up to increment the pointers later

cblt_5100:
	cmp	dx,1			;Move one word or many words?
	jz	cblt_5120		;  Only one word
	mov	al,I_MOV_CX_WORD_I 	;  Many words, load count
	mov	ah,dl
	stosw
	mov	al,dh			;Set MSB of count
	mov	ah,I_REP		;  and a repeat instruction
	stosw

cblt_5120:
	mov	ax,si			;Set the word instruction
	inc	ax
	stosb
	errnz	I_MOVSW-I_MOVSB-1	;The word form of the instruction
	errnz	I_STOSW-I_STOSB-1	;  must be the byte form + 1

	or	bx,bx			;Need to increment the pointers?
	jz	cblt_5140		;  No
	mov	ax,bx			;  Yes, increment both pointers
	stosw

cblt_5140:
	jmp	short cblt_6000		;Done setting up the innerloop
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	There is some count for the innerloop of the BLT.  Generate the
;	required BLT. Two or four copies of the BLT will be placed on the
;	stack.	 This allows the LOOP instruction at the end to be distributed
;	over two or four bytes instead of 1, saving 11 or 12 clocks for each
;	byte (for 4).  Multiply 12 clocks by ~ 16K and you save a lot of
;	clocks!
;
;	If there are less than four (two) bytes to be BLTed, then no looping
;	instructions will be generated.  If there are more than four (two)
;	bytes, then there is the possibility of an initial jump instruction
;	to enter the loop to handle the modulo n result of the loop count.
;
;	The innerloop code will look something like:
;
;
;	<	mov	cx,loopcount/n> ;load count if >n innerloop bytes
;	<	jmp	short ???     > ;If a first jump is needed, do one
;
;	BLTloop:
;		replicate initial byte BLT code up to n times
;
;	<	loop	BLTloop >	;Loop until all bytes processed
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


cblt_5500:
	mov	bx,gl_end_fl		;Compute size of the fetch code
	sub	bx,gl_start_fl
	inc	bx			;A stosb will be appended
	mov	si,4			;Assume replication 4 times
	mov	cl,2			;  (shift count two bits left)
	cmp	bx,32			;Small enough for 4 times?
	jc	cblt_5520		;  Yes, replicate 4 times
	shr	si,1			;  No,	replicate 2 times
	dec	cx

cblt_5520:
	cmp	dx,si			;Generate a loop?
	jle	cblt_5540		;  No, just copy code
	mov	al,I_MOV_CX_WORD_I
	stosb				;mov cx,loopcount/n
	mov	ax,dx			;Compute loop count
	shr	ax,cl
	stosw
	shl	ax,cl			;See if loopcount MOD n is 0
	sub	ax,dx
	jz	cblt_5540		;Zero, no odd count to handle

	page
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	There is an odd portion of bytes to be processed.  Increment
;	the loop counter for the odd pass through the loop and then
;	compute the displacement for entering the loop.
;
;	To compute the displacement, subtract the number of odd bytes
;	from the modulus being used  (i.e. 4-3=1).  This gives the
;	number of bytes to skip over the first time through the loop.
;
;	Multiply this by the number of bytes for a logic sequence,
;	and the result will be the displacement for the jump.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


	inc	wptr es:-2[di]		;Not zero, adjust for partial loop
	add	ax,si			;Compute where to enter the loop at
	mul	bl
	mov	cx,ax
	mov	al,I_JMP_NEAR		;Stuff jump instruction
	stosb
	mov	ax,cx			;Stuff displacement for jump
	stosw



;	Currently:	DX = loop count
;			SI = loop modulus
;			BX = size of one logic operation
;			DI --> next location in the loop

cblt_5540:
	mov	cx,bx			;Set move count
	mov	bx,dx			;Set maximum for move
	cmp	bx,si			;Is the max > what's left?
	jle	cblt_5560		;  No, just use what's left
	mov	bx,si			;  Yes, copy the max

cblt_5560:
	sub	dx,si			;If dx > 0, then loop logic needed
	mov	si,gl_start_fl		;--> fetch code to copy
	mov	ax,cx			;Save a copy of fetch length
	rep	movsb			;Move fetch code and stuff stosb
	mov	si,di			;--> new source (and top of loop)
	sub	si,ax
	mov	bptr es:-1[di],I_STOSB
	dec	bl			;One copy has been made
	mul	bl			;Compute # bytes left to move
	mov	cx,ax			;Set move count
	rep	movsb			;Move the fetches
	sub	si,ax			;Restore pointer to start of loop

	page
;	The innermost BLT code has been created and needs the looping
;	logic added to it.  If there is any looping to be done, then
;	generate the loop code.  The code within the innerloop may be
;	greater than 126 bytes, so a LOOP instruction may not be used
;	in this case.

cblt_5580:
	or	dx,dx			;Need a loop?
	jle	cblt_6000		;  No, don't generate one

	mov	ax,si			;Compute offset of loop
	sub	ax,di
	cmp	ax,-125 		;Can this be a short label?
	jc	cblt_5600		;  No, must make it a near jmp

	sub	al,2			;Bias offset by length of LOOP inst.
	mov	ah,al
	mov	al,I_LOOP
	stosw				;Set the loop instruction
	jmp	short cblt_6000		;Go process the last byte code


cblt_5600:
	mov	si,CodeOFFSET jmp_cx_nz ;Move in the dec CX jnz code
	movs	wptr es:[di],wptr cs:[si]
	movs	wptr es:[di],wptr cs:[si]
	errnz	JMP_CX_NZ_LEN-4		;Must be four bytes long
	sub	ax,6			;Adjust jump bias
	stosw				;  and store it into jump



	subttl	Compile - Last Byte Processing
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	All the innerloop stuff has been processed.  Now generate the code for
;	the final byte if there is one.  This code is almost identical to the
;	code for the first byte except there will only be one fetch (if a
;	fetch is needed at all).
;
;	The code generated will look something like:
;
;	<	fetch		>	;Get source byte
;	<	align		>	;Align source if needed
;		action			;Perform desired action
;		mask and store
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

cblt_6000:
	mov	dx,gl_last_mask		;Get last byte mask
	or	dh,dh			;Is there a last byte to be processed?
	jz	cblt_6100		;  No.

	mov	cx,gl_end_fls		;Get end of fetch/logic/store operation
	mov	si,gl_start_fl		;Get start of fetch/logic sequence
	sub	cx,si			;Compute length of the code
	rep	movsb			;Copy the fetch/action/store code
	xchg	dh,dl
	mov	MASKED_STORE_MASK[di],dx ;Stuff last byte mask into the code


	subttl	Compile - Looping Logic
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Looping logic.
;
;	The looping logic must handle monochrome bitmaps, color bitmaps,
;	huge bitmaps, the device, the presence or absence of a source
;	or pattern, and mono <==> color interactions.
;
;	The type of looping logic is always based on the destination.
;
;
ifdef	GEN_COLOR_BLT
;	Plane Update Facts:
;
;	1)  If the destination device is color, then there will be
;	    logic for plane selection.	Plane selection is performed
;	    at the start of the loop for the display.  Plane selection
;	    for bitmaps is performed at the end of the loop in anticipation
;	    of the next plane.
;
;
;	    The following applies when the destination is color:
;
;
;	    a)	The destination update consists of:
;
;		1)  If the destination is the display, the next plane will
;		    be selected by the plane selection code at the start
;		    of the scan line loop.
;
;		2)  If not the display, then the PDevice must a bitmap.
;		    The next plane will be selected by updating the
;		    destination offset by the plane_w value.
;
;
;	    b)	If F0_GAG_CHOKE isn't specified, then there may be a source.
;		If there is a source, it must be color, and the update
;		consists of:
;
;		1)  If the source is the display, the next plane will be
;		    selected by the plane selection code at the start of
;		    the loop.
;
;		2)  If not the display, then the PDevice must a bitmap.
;		    The next plane will be selected by updating the
;		    destination offset by the plane_w value.
;
;
;	    c)	If F0_GAG_CHOKE is specified, then the source must be a
;		monochrome bitmap which is undergoing mono to color
;		conversion.  The AND & XOR mask table which is used
;		for the conversion will have to be updated, unless
;		the F1_NO_MUNGE flag is set indicating that the color
;		conversion really wasn't needed.
;
;		The source's pointer will not be updated.  It will
;		remain pointing to the same scan of the source until
;		all planes of the destination have been processed.
;
;
;	    d)	In all cases, the plane mask rotation code will be
;		generated.  If the plane indicator doesn't overflow,
;		then start at the top of the scan line loop for the
;		next plane.
;
;		If the plane indicator overflows, then:
;
;		    1)	If there is a pattern present, it's a color
;			pattern fetch.	The index of which scan of
;			the brush to use will have to be updated.
;
;		    2)	Enter the scan line update routine
;
;
;	2)	If the destination is monochrome, then there will be no
;		plane selection logic.
;
;		If F0_GAG_CHOKE is specified, then color ==> mono conversion
;		is taking place.  Any plane selection logic is internal
;		to the ROP byte fetch code.  Any color brush was pre-
;		processed into a monochrome brush, so no brush updating
;		need be done
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;



	subttl	Looping Logic - Plane Selection
	page
endif	;GEN_COLOR_BLT

;	Get saved parameters off of the stack.
;
;	<	pop	bx	      > ;Get plane indicator
;	<	pop	si	      > ;Get source pointer
;		pop	di		;Get destination pointer
;		pop	cx		;Get loop count


cblt_6100:
	mov	ax,cs			;Reset ds: back to cs:
	mov	ds,ax
	mov	bh,gl_the_flags		;These flags will be used a lot
ifdef	GEN_COLOR_BLT
	test	bh,F0_DEST_IS_COLOR	;Is the destination color?
	jz	cblt_6120		;  No
	mov	al,I_POP_BX		;Restore plane index
	stosb

cblt_6120:
endif
	test	bh,F0_SRC_PRESENT	;Is a source needed?
	jz	cblt_6140		;  No
	mov	al,I_POP_SI		;  Yes, get source pointer
	stosb

cblt_6140:
	mov	ax,I_POP_DI_POP_CX	;Get destination pointer
	stosw				;Get loop count
ifdef	GEN_COLOR_BLT
	test	bh,F0_DEST_IS_COLOR	;Color scanline update?
	jnz	cblt_6160		;  Yes
	jmp	cblt_6300		;  No, just do the mono scanline update




;	The scanline update is for color.  Generate the logic to update
;	a brush, perform plane selection, process mono ==> color conversion,
;	and test for plane overflow.


cblt_6160:
	or	bh,bh			;Color conversion?
	jns	cblt_6180		;  No
	errnz	F0_GAG_CHOKE-10000000b


	page
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	The source is monochrome.  Handle mono ==> color conversion.
;	The AND & XOR mask table will need to be rotated for the next
;	pass over the source.
;
;	The source scanline pointer will not be updated until all planes
;	have been processed for the current scan.
;
;	If F1_NO_MUNGE has been specified, then the color conversion table
;	and the color conversion code was not generated, and no update
;	code will be needed.
;
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


	test	dl_moore_flags,F1_NO_MUNGE ;Is there really a conversion table?
	jnz	short cblt_6200		;  No, so skip the code

	mov	al,I_MOV_BP_WORD_I 	;lea bp,cl_a_brush
	stosb
	lea	ax,cl_a_brush		;Get address of table
	stosw
	lea	si,rot_and_xor		;--> rotate code
	mov	cx,LEN_ROT_AND_XOR/2
	rep	movsw
if	LEN_ROT_AND_XOR AND 1
	movsb
endif
	jmp	short cblt_6200



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	If there is a source, it must be color.  If it is a memory
;	bitmap, then the next plane must be selected, else it is
;	the display and the next plane will be selected through
;	the hardware registers.
;
;	<	add	si,plane_w>
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


cblt_6180:
	test	bh,F0_SRC_PRESENT	;Is there really a source?
	jz	cblt_6200		;No source.
	test	bh,F0_SRC_IS_DEV	;Is the source the display?
	jnz	cblt_6200		;  Yes, use hardware plane selection
	mov	ax,I_ADD_SI_WORD_I 	;  No, generate plane update
	stosw				;Add si,plane_w
	mov	ax,gl_plane_w
	stosw




; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	If the destination isn't the device, then it must be a color
;	memory bitamp, and it's pointer will have to be updated by
;	bmWidthPlanes.	If it is the display, then the next plane
;	will be selected through the hardware registers.
;
;	<	add	di,plane_w>
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

cblt_6200:
	test	bh,F0_DEST_IS_DEV	;Is the destination the display
	jnz	cblt_6220		;  Yes, don't generate update code
	mov	ax,I_ADD_DI_WORD_I 	;  No, update bitmap to the next plane
	stosw
	mov	ax,gl_dest_plane_w
	stosw





; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	The source and destination pointers have been updated.
;	Now generate the plane looping logic.
;
;	<	shl	bl,1	      > ;Select next plane
;	<	jc	$+5	      > ;  No, reset to first
;	<	jmp	StartOfLoop   > ;  Yes, go process next
;	<	mov	bl,PLANE_1     > ;Reset plane indicator
;
;	or
;
;	<	shl	bl,1	      > ;Select next plane
;	<	jnc	StartOfLoop   > ;  Yes, go process next
;	<	mov	bl,PLANE_1     > ;Reset plane indicator
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

cblt_6220:
	mov	ax,I_SHL_BL_1		;Stuff plane looping logic
	stosw

	mov	dx,off_gl_blt_addr	;Compute relative offset of
	sub	dx,di			;  start of loop
ifdef	GEN_COLOR_BLT
;;;	add	dx,2			;account for init of plane indicator
endif
	cmp	dx,-125 		;Can this be a short label?
	jc	cblt_6240		;  No, must make it a near jmp
	sub	dl,2			;Bias offset by length of jz inst.
	mov	ah,dl
	mov	al,I_JNC
	stosw				;jnc StartOfLoop
	jmp	short cblt_6260

cblt_6240:
	mov	ax,I_JC_P5H		;jc $+5
	stosw
	mov	al,I_JMP_NEAR		;jmp near
	stosb
	sub	dx,5			;Adjust jump bias
	mov	ax,dx
	stosw				;Store jmp displacement

cblt_6260:
	mov	ax,(PLANE_1*256)+I_MOV_BL_BYTE_I
	stosw



	subttl	Looping Logic - Color Brush Update
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	The plane update logic has been copied.  If a pattern was
;	involved for a color BLT, then the pattern index will need
;	to be updated to the next scanline for three plane mode.
;
;	This will involve subtracting off 3*SIZE_PATTERN (MonoPlane),
;	and adding in the increment.  The result must be masked with
;	00000111b to select the correct source.  Note that the update
;	can be done with an add instruction and a mask operation.
;
;	inc   index+MonoPlane	inc-MonoPlane	result	 AND 07h
;
;	 1	 0+24 = 24	  1-24 = -23	   1	     1
;	 1	 7+24 = 31	  1-24 = -23	   8	     0
;	-1	 0+24 = 24	 -1-24 = -25	  FF	     7
;	-1	 7+24 = 31	 -1-24 = -25	   6	     6
;
;	<	mov	al,ss:[1234]  > ;Get brush index
;	<	add	al,n	      > ;Add displacement to next byte
;	<	and	al,00000111b  > ;Keep it in range
;	<	mov	ss:[1234],al  > ;Store displacement to next byte
;
;
;	For four plane mode, the AND 00011111b automatically wraps the
;	pattern at the correct location, so no code is generated.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

if	NUMBER_PLANES eq 3

	test	bh,F0_PAT_PRESENT	;Is a pattern involved?
	jz	cblt_6300		;  No
	mov	ax,I_CS_OVERRIDE+(I_MOV_AL_MEM*256)
	stosw				;mov al,ss:[xxxx]
	mov	dx,dl_addr_brush_index
	mov	ax,dx
	stosw
	mov	al,I_ADD_AL_BYTE_I
	mov	ah,gl_direction		;add al,bais
	sub	ah,oem_brush_mono	;Anybody ever fly one of these things?
	errnz	INCREASE-1		;Must be a 1
	errnz	DECREASE+1		;Must be a -1
	stosw
	mov	ax,0700h+I_AND_AL_BYTE_I	;and al,00000111b
	stosw
	mov	ax,I_CS_OVERRIDE+(I_MOV_MEM_AL*256)
	stosw				;mov ss:[xxxx],al
	mov	ax,dx
	stosw
endif
endif	;GEN_COLOR_BLT

	subttl	Looping Logic - Scan Line Update
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	Generate the next scanline code.  The next scan line code must
;	handle monochrome bitmaps, the device, huge bitmaps, the presence
;	or absence of a source.
;
ifdef	GEN_COLOR_BLT
;	Also color bitmaps, and mono <==> color interactions.
endif
;
;	<	add si,gl_src.next_scan> ;Normal source scan line update
;	<	Huge Bitmap Update    > ;>64K source update code
;		add di,gl_dest.next_scan ;Normal destination scan line update
;	<	Huge Bitmap Update    > ;>64K destination update code
;
;
;	All updates will at least consist of the add IndexReg,plane_w.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;


cblt_6300:
;;;	mov	ch,gl_direction		;Load this for YUpdate code
	test	bh,F0_SRC_PRESENT	;Is there a source?
	jz	cblt_6340		;  No, skip source processing
	mov	ax,I_ADD_SI_WORD_I	;add si,increment
;
; Win2 calls y_update here to generate the Y update code. Win1 does something
; much simpler.
;
	stosw
	mov	ax, gl_src_increment
	mov	bl, bh
	and	bl, 0Dh
	xor	bl, 5
	jnz	cblt_6320
	mov	dx, gl_plane_w
	sub	ax, dx
	shl	dx, 1
	sub	ax, dx
cblt_6320:
	stosw
cblt_6340:
	mov	ax,I_ADD_DI_WORD_I 	;add reg,increment
	stosw
	mov	ax,gl_dest_increment
	mov	bl, bh
	and	bl, 3
	xor	bl, 1
	jnz	cblt_6360
	mov	dx,gl_dest_plane_w
	sub	ax, dx
	shl	dx, 1
	sub	ax, dx
cblt_6360:
	stosw

;	Compile the scan line loop.  The code simply jumps to the start
;	of the outer loop if more scans exist to be processed.


cblt_6380:
	mov	ax,off_gl_blt_addr	;Compute relative offset of
	sub	ax,di			;  start of loop
ifdef	GEN_COLOR_BLT
;;;	add	dx,2			;account for init of plane indicator
endif
	cmp	ax,-125 		;Can this be a short label?
	jc	cblt_6400		;  No, must make it a near jmp
	sub	al,2			;Bias offset by length of LOOP inst.
	mov	ah,al
	mov	al,I_LOOP
	stosw				;Set the loop instruction
	jmp	short cblt_6420

cblt_6400:
	mov	si,CodeOFFSET jmp_cx_nz ;Move in the dec CX jnz code
	movsw
	movsw
	errnz	JMP_CX_NZ_LEN-4		;Must be four bytes long
	sub	ax,6			;Adjust jump bias
	stosw				;  and store it into jump

cblt_6420:
	mov	al,I_RET_FAR		;Stuff the far return instruction
	stosb


	subttl	Invocation and Exit
	page

; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	If the debug flag has been set, save the size of the created BLT
;	so it may be returned to the caller.
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

call_blt:

;;;ifdef	DEBUG
	sub	di,off_gl_blt_addr	;Compute the length
	push	di			;  and save it
;;;endif


;	The BLT has been created on the stack.	Set up the initial registers,
;	set the direction flag as needed, and execute the BLT.


	test	bh,F0_SRC_PRESENT ;Is there a source?
	jz	call_blt_get_dest_bits	;  No, don't load its pointer
	lds	si,lpSrcDev		;--> source device's first byte

call_blt_get_dest_bits:
	les	di,lpDestDev		;--> destination device's first byte
	mov	cx,yExt 		;Get count of lines to BLT
	cld				;Assume this is the direction
	cmp	gl_step_direction,STEPRIGHT ;Stepping to the right?
	jz	call_blt_do_it		;  Yes
	std

call_blt_do_it:
	mov	bl, 21h
	push	bp			;MUST SAVE THIS

ifdef	TEFTI
	timer_begin
endif
	call	gl_blt_addr 		;Call the FAR process

ifdef	TEFTI
	timer_end
endif
	pop	bp

;;;ifdef	DEBUG
	pop	bx			;Get length of created BLT code
;;;endif
	add	sp,MAX_BLT_SIZE		;Return BLT space



; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	exit - leave BitBLT
;
;	Well, the BLT has been processed.  Restore the stack to its
;	original status, restore the saved user registers, show no
;	error, and return to the caller.
;
;	Entry:	None
;
;	Exit:	AX = 1
;
;	Uses:	All
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

bitblt_exit:

ifdef	TEFTI_WHOLE
	timer_end
endif

;;;	call	clean_up_before_exit

	mov	ax,1			;Clear out error register (good exit)
;	jmp	bitblt_exit_fail
	errn$	bitblt_exit_fail


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;
;	bitblt_exit_fail - exit because of failure
;
;	The BLT is exited.
;
;	Entry:	AX = error code (0 if error)
; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

bitblt_exit_fail:

	cld				;Leave direction cleared
	mov	byte ptr cs:ega_saved, ah

ifdef	EXCLUSION
	call	unexclude		;Remove any exclusion area
endif

bitblt_stack_ov:
;;; XXX cEnd
	pop	di
	pop	si
	sub	bp, 2
	mov	sp, bp
	pop	ds
	pop	bp
	dec	bp
	retf	20h	
cEnd <nogen>



;-----------------------------------------------------------------------;
;	Subroutines.  These have been included with the aim of
;	segregating device dependent code from independent code,
;	while cleanly preserving the local variable frame.
;-----------------------------------------------------------------------;

	include	      SPECIAL.BLT	;non-compiled BLT subroutines
;;;	include	      PDEVICE.BLT	;PDevice processing
;;; Inlined in Win1
;;;	include	      PATTERN.BLT	;pattern preprocessing
;;;	include	      COPYDEV.BLT	;copy_dev procedure
;;;	include	      COMPUTEY.BLT	;compute_y procedure
;;;	include	      EXIT.BLT		;device-specific cleanup before exit

sEnd	Code


ifdef	PUBDEFS
	include                 BITBLT.PUB
endif

end
