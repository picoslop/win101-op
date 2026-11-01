	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	PIXEL.ASM
;
; This module contains the Set/Get Pixel routine.
;
; Created: 22-Feb-1987
; Author:  **** ***** [*****]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	Pixel
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
;   Pixel is used to either set a pixel to a given color with the
;   current binary raster operation, or to return the color of the
;   the pixel at the given location.
;
; Restrictions:
;
;-----------------------------------------------------------------------;


	??_out	Pixel

incDrawMode	= 1			;Include control for gdidefs.inc

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include display.inc
	include ega.inc
	include egamem.inc
	include macros.mac
	.list


	externA ScreenSelector		;Selector to the screen
	externA SCREEN_W_BYTES		;Screen width in bytes
	externA COLOR_FORMAT		;Color format (0103h or 0104h)
	externNP ega_set_op

	externNP sum_RGB_colors_alt	;Color mapping routine

	externW	rop_indexes


ifdef	EXCLUSION
	externNP exclude		;Exclude area from screen
	externNP unexclude		;Clear excluded area
endif


;	Define the type flags used to determine which type
;	of scan needs to be performed (color or mono).

COLOR_OP	equ	00000001b
MONO_OP 	equ	MONO_BIT
END_OP		equ	4
;END_OP		equ	MONO_BIT shl 1 + (1 shl (NUMBER_PLANES))


sBegin	Data

	externW ega_state_mode
	externW ega_state_mask
	externW ega_saved
	externW ega_state_graf
	externW ega_state_rot

sEnd	Data
page

sBegin	Code
assumes cs,Code

	externB	 rot_bit_tbl
	externD  Code_color_table	;Index --> RGB mapping

	.xlist
SINGLE_OK	equ	1
	externB dm_flags
	externB dm_pen_and	
	externB dm_pen_xor
	externB dm_data_r
	.list

;;; WIN1 this is now in egahires.asm
;;;
;;;rot_bit_tbl	label	byte
;;;		db	10000000b	;Table to map bit index into
;;;		db	01000000b	;  a bit mask
;;;		db	00100000b
;;;		db	00010000b
;;;		db	00001000b
;;;		db	00000100b
;;;		db	00000010b
;;;		db	00000001b
page

;--------------------------Exported-Routine-----------------------------;
; Pixel
;
;   Set or Get a Given Pixel
;
;   The given pixel is set to the given color or the given pixel's
;   physical color is returned.
;
;   The physical device may be the screen, a monochrome bitmap, or a
;   bitmap in our color format.
;
;   There will not be error checking to see if the bitmap is in our
;   color format.  If it isn't, then we'll treat the bitmap as monochrome.
;
;   If lp_draw_mode is NULL, then the physical color of the pixel is
;   returned.  If lp_draw_mode isn't NULL, then the pixel will be set
;   to the physical color passed in, combined with the pixel already
;   at that location according to the raster-op in lp_draw_mode.  Pixel
;   doesn't pay attention to the background mode.
;
;   No clipping of the input value is required.  GDI clips the
;   coordinate before it is passed in, for both Set and Get.
;
; Entry:
;	EGA registers in default state
; Returns:
;	DX:AX = physical color if get pixel
;	DX:AX = positive if no error and set was OK.
; Error Returns:
;	DX:AX = 8000:0000H if error occured
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	exclude_far	(far version of exclude)
;	unexclude_far	(far version of unexclude)
; History:
;	Sat 31-Oct-1987 00:21:06 -by-  **** ***** [*****]
;	Added clipping of the (X,Y)
;
;	Tue 18-Aug-1987 14:50:37 -by-  **** ***** [*****]
;	Added test of the disabled flag.
;
;	Wed 12-Aug-1987 19:55:20 -by-  **** ***** [*****]
;	Moved to _PIXEL.  Removed stack checking.
;
;	Thu 06-Aug-1987          -by-  ***** ****** [mitchl]
;	Put code into segment _LINES
;
;	Tue 03-Mar-1987 20:42:07 -by-  **** ****** [******]
;	Moved a mov instruction in EGA ROP handling code.
;
;	Sun 22-Feb-1987 16:29:09 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;

;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;

	externNP my_check_stack

	assumes ds,Data
	assumes es,nothing


cProc	Pixel,<FAR,PUBLIC,WIN,PASCAL>,<si,di>

	parmD	lp_device		;Pointer to device
	parmW	x			;X coordinate of pixel
	parmW	y			;Y coordinate of pixel
	parmD	p_color 		;Physical color to set pixel to
	parmD	lp_draw_mode		;Drawing mode to use, or null if Get

;;;	localB	is_device		;set non-zero if the device

cBegin
ife     ???                             ;If no locals
        xor	ax, ax                  ;See if room
	call	my_check_stack
endif
	jnc	pixel_00
	jmp	pixel_exit

pixel_00:
;;;	mov	al,enabled_flag 	;Load this before trashing DS
	lds	si,lp_device		;--> physical device
	assumes ds,nothing
	mov	cx,[si].bmType		;Get device type
	jcxz	pixel_20		;Memory bitmap, skip EGA specific code

;	This is the device.  The cursor must be excluded from the pixel
;	that will be processed.  The innerloop mask for the device will
;	be set for color.  The width of a plane will be set to 1 to flag
;	to the loop code that this is the EGA (odd widths are illegal).


ifdef	EXCLUSION			;If exclusion required
	mov	cx,x			;Set left
	mov	dx,y			;    top
	mov	si,cx			;    right
	mov	di,dx			;    bottom
	call	exclude 		;Exclude the area
	lds	si, lp_device
endif

pixel_20:

;	This is a memory DC.  If this is a monochrome memory DC, set up
;	the inner loop so that it will terminate after one time through
;	and set the color to be equal to the mono bit in the physical
;	color.	If it is color, set up the inner loop for all planes,
;	same as for the display.
;
;	Also handle modifying Y for huge bitmaps is necessary.
;
;
;	Currently:
;		AX     =  Y coordinate
;		DX     =  Segment bias for huge bitmaps
;		DS:SI --> PDevice
;		CH     =  Huge bitmap flag
;			  (0 = small bitmap)

pixel_40:
	mov	cl,COLOR_OP		;Assume mono loop
	cmp	wptr [si].bmPlanes, COLOR_FORMAT
	jz	pixel_60		;Not our color format, treat as mono
	mov	al, bptr p_color+3
	rol	al, 1
	cbw
	mov	bptr p_color,ah
pixel_50:
	mov	cl, END_OP		;Show color loop

pixel_60:
	mov	ax, [si].bmWidthBytes
	mul	y
	mov	dx, wptr [si].bmWidthPlanes
	lds	si, [si].bmBits
	add	si,ax			;DS:SI --> start of scanline byte is in



;	Currently:
;		DS:SI --> the bitmap, start of the correct scan
;		DI = Index to next plane of the scan
;		     1 if the display (odd with illegal)
;		CL = looping flag

pixel_70:				;Display code enters here
	mov	ax,x			;Get X coordinate
	mov	bx,ax
	shiftr	ax,3			;Compute byte offset from start of scan
	add	si,ax			;ds:si --> byte of pixel

	and	bx, wptr 00000111B		;Get bit mask for bit
	mov	ch,rot_bit_tbl[bx]
	mov	di,off_lp_draw_mode	;If a drawmode was given
	mov	bx,seg_lp_draw_mode	;  then set the pixel, else
	mov	ax,bx			;  return it's physical color
	or	ax,di
	jnz	pixel_100		;Given, operation is set pixel
	jmp	pixel_200		;Not given, return pixel color




;	The operation to be performed is SetPixel.  Currently:
;
;		CH    =   bit mask
;		DS:SI --> byte bit is to be set in
;		BX:DI --> physical drawing mode
;		CL    =   loop mask
;		DX    =   Index to next plane
;			  1 if the display


pixel_100:
	mov	es,bx			;ES:DI --> drawmode
	assumes es,nothing

	mov	bx,es:[di].Rop2 	;Get drawing mode to use
	dec	bx			;Make it zero based
	and	bx,wptr 000Fh		;Keep it valid
	or	dx, dx
	jnz	pixel_120

;	This is the EGA.  Regardless of the raster operation being
;	performed in one or two operations, set up the following
;	registers which will be the same:
;
;	BitMask Register     - To the bit to alter
;
	test	cs:dm_flags[bx], SINGLE_OK
	jz	pixel_110
	mov	ah, cs:dm_data_r[bx]
	mov	al, GRAF_DATA_ROT
	mov	dx, EGA_BASE + GRAF_ADDR
	mov	cs:ega_state_rot, ax
	mov	byte ptr cs:ega_saved, 3
	out16	dx, ax
	mov	ax, M_COLOR_WRITE shl 8 + GRAF_MODE
	mov	cs:ega_state_mode, ax
	out	dx, ax
	mov	ah,ch
	mov	al,GRAF_BIT_MASK
	mov	cs:ega_state_graf, ax
	out16	dx,ax
	mov	dl, SEQ_ADDR
	mov	ax, 700h + SEQ_MAP_MASK
	out16	dx, ax

	mov	al,p_color.SPECIAL	;Need color here
	and	al,dm_pen_and[bx]	;Set correct color for the ROP
	xor	al,dm_pen_xor[bx]
	and	al, 7			;Only leave bits of interest
	cli
	mov	ah, [si]
	mov	[si], al
	sti
	jmp	pixel_300
;

;	The ROP cannot be performed in one pass using the
;	EGA hardware.  It can be performed in two seperate
;	operations to the EGA.	This will be done in the
;	following manner:
;
;	    The color will be used for the Write Plane Enable Mask
;	    after possibly being inverted to sync for the output
;	    mode being used (xor or set)
;
;	    A write with 0's or 1's in drSet mode will occur.
;	    This will set bits to either 1's or 0's as needed.
;
;	    After this write occurs, the color will be inverted
;	    for use as the Write Plane Enable Mask for those
;	    planes which must be XORed to get ~dest.  An XOR
;	    will occur to toggle those bits which must be toggled.
;
;		  Color Destination
;
;	    DPon    0	 ~dest	 for color bits which are 0, xor with 1
;		    1	   0	 for color bits which are 1, set to   0
;
;	    PDna    0	   0	 for color bits which are 0, set to   0
;		    1	 ~dest	 for color bits which are 1, xor with 1
;
;	    DPan    0	   1	 for color bits which are 0, set to   1
;		    1	 ~dest	 for color bits which are 1, xor with 1
;
;	    PDno    0	 ~dest	 for color bits which are 0, xor with 1
;		    1	   1	 for color bits which are 1, set to   1


pixel_110:
	mov	ax, GRAF_DATA_ROT + DR_SET shl 8
	mov	cs:ega_state_rot, ax
	mov	cs:ega_state_mode, 5
	mov	byte ptr cs:ega_saved, 4
	call	ega_set_op
	mov	ax, 0FF00h + GRAF_BIT_MASK
	mov	cs:ega_state_graf, ax
	out	dx, ax	
	xor	dx, dx


;	The SetPixel operation is to be performed on a memory bitmap.
;
;	The loop will use the following registers:
;
;	    AH	Inverse of the bitmask
;	    AL	The bitmask
;	    BX	Work
;	    CH	Pen Color
;	    CL	Loop mask
;	    DX	Index to next plane, or 1 if EGA
;	 DS:SI	destination pointer
;	    DI	ROP table address for the rop

pixel_120:
	lea	di, p_color
	push	bp

	shl	bx,1			;Set rop_indexes table address
	mov	bp, cs:rop_indexes[bx]	;  for the given rop
pixel_130:
	or	dx, dx
	jnz	pixel_140
	mov	ah, cl
	mov	al, SEQ_MAP_MASK
	mov	dx, EGA_BASE + SEQ_ADDR
	mov	cs:ega_state_mask, ax
	out16	dx, ax
	mov	al, GRAF_READ_MAP
	mov	dl, GRAF_ADDR
	shr	ah, 1
	out16	dx, ax
	xor	dx, dx
pixel_140:
	mov	al, ss:[di]
	mov	bh, al
	mov	ah, [si]	;Load EGA latches
	call	bp
	xor	al, ah
	and	al, ch
	xor	al, ah
	mov	[si], al
	inc	di
	add	si, dx
	rol	cl, 1
	test	cl, 8
	jz	pixel_130
	pop	bp
	jmp	short pixel_300
	
page

;	The operation to be performed is get pixel.  The color of the
;	pixel will be returned.  The color of the pixel will be composed
;	from all planes if a color bitmap and the result "AND"ed to
;	produce the mono bit in the physical color (this is the same
;	as bitblt when blting from color to monochrome).
;
;	If this is a monochrome bitmap, then the color will simply be
;	black or white.
;
;	Currently:
;
;		CH     =  bit mask
;		CL     =  loop mask
;		DX     =  index to next plane
;			  1 if physical device
;		DS:SI --> byte bit is to be set in


WHITE	equ	C0_BIT+C1_BIT+C2_BIT+C3_BIT+MONO_BIT+ONES_OR_ZEROS
BLACK	equ	ONES_OR_ZEROS


pixel_200:
	cmp	cl,END_OP		;Is this for a mono bitmap?
	jne	pixel_210		;  No, its for color
	xor	dx,dx			;Assume pixel is black
	xor	ax,ax
	test	[si],ch 		;Is pixel black?
	jz	pixel_300		;  It is, return color in AX:DX
	dec	ax			;  No, set AX:DX for white
	mov	dx, 47FFh	;;; WHITE*256+0FFh
	jmp	short pixel_300



;	Counter the first DEC SI which the EGA will throw in
;	if this is for the EGA.  DX will be 1 if it is.  DX
;	cannot be 0 at this point.


pixel_210:
	mov	bl, bh
	mov	bh, al
	or	dx, dx
	jnz	pixel_220
	mov	al,GRAF_READ_MAP	;--> Read Map Select Register
	mov	dx, EGA_BASE + GRAF_ADDR
	mov	ah,cl			;Set read plane mask
	shr	ah,1
	out16	dx,ax
	xor	dx, dx
pixel_220:
	xor	ax, ax
	test	[si], ch
	jz	pixel_240
	dec	ax
pixel_240:
	add	si,dx			;--> next plane
	rol	cl,1			;Select next plane
	test	cl,END_OP shl 1		;Done with all planes?
	jz	pixel_210		;  Not yet
	mov	dx, ax
	mov	ax, bx
	call	sum_RGB_colors_alt 	;Get the real physical color into DX:AX

pixel_300:
ifdef	EXCLUSION
	call	unexclude		;Clear any exclude rectangle
endif
	mov	byte ptr cs:ega_saved, 0
pixel_exit:
	pop	di
	pop	si
	sub	bp, 2
	mov	sp, bp
	pop	ds
	pop	bp
	dec	bp
	retf	10h

cEnd	<nogen>

ifdef	PUBDEFS
	.xlist
	include PIXEL.PUB
	.list
endif

sEnd	Code
	end
