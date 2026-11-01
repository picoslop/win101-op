        page    ,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	SCANLR.ASM
;
;   This module contains the ScanLR routine.
;
; Created: 22-Feb-1987
; Author:  **** ***** [*****]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	ScanLR
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
;   ScanLR is used to search a scanline for a pixel of the given
;   color or one which isn't of the given color.  This is usually
;   used by the floodfill simulation.
;
; Restrictions:
;
;-----------------------------------------------------------------------;


incDrawMode	= 1			;Include control for gdidefs.inc

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include display.inc
	include ega.inc
	include egamem.inc
	include macros.mac
	.list


;	Link time constants describing the size and color format
;	that the EGA will be running in.

	externA ScreenSelector		;Selector to the screen
	externA SCREEN_WIDTH		;Screen width in pixels
	externA SCREEN_W_BYTES		;Screen width in bytes
	externA SCREEN_HEIGHT		;Screen height in scans
	externA COLOR_FORMAT		;Color format (0103h or 0104h)
	externA COLOR_DONT_CARE 	;GRAF_CDC value and register address


ifdef	EXCLUSION
	externNP  exclude		;Exclude area from screen
	externNP  unexclude		;Clear excluded area
endif

	externW	ega_state_mode
	externW	ega_saved


;	Define the flag values which control the direction
;	and type of the scan.

STEP_LEFT	equ	00000010b	;Flag values for DirStyle
STEP_RIGHT	equ	00000000b
FIND_COLOR	equ	00000001b
FIND_NOT_COLOR	equ	00000000b


;	Define the type flags used to determine which type
;	of scan needs to be performed (color or mono).

COLOR_OP	equ	NUMBER_PLANES
MONO_OP 	equ	1


;	Define the error conditions which will be returned

ERROR_CLIPPED	equ	8000h		;Cooridnate was clipped
ERROR_NOT_FOUND equ	-1		;Stop condition not reached

sBegin	Code
assumes cs,Code

	externB rot_bit_tbl
page

;--------------------------Exported-Routine-----------------------------;
; ScanLR
;
;   ScanLR - Scan left or right
;
;   Starting at the given pixel and proceeding in the choosen direction,
;   the pixels are examined for the given color until one is found that
;   matches (or doesn't match depending on the style).  The X coordinate
;   is returned for the pixel that matched (or didn't match).
;
;   The physical device may be the screen, a monochrome bitmap, or a
;   bitmap in our color format.
;
;   There will be no error checking to see if the bitmap is in our
;   color format.  If it isn't, it will be treated as if it were a
;   monochrome bitmap.
;
; Entry:
;	EGA registers in default state
; Returns:
;	AX = x location of sought pixel
; Error Returns:
;	AX = -1 if nothing found
;	AX = 8000h if clipped
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	exclude
;	unexclude
; History:
;	Fri 01-May-1987 12:30:45 -by-  **** ***** [*****]
;	Output to GRAF_CDC for Win386 support.
;
;	Sun 22-Feb-1987 16:29:09 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


	assumes ds,Data
	assumes es,nothing


cProc	ScanLR,<FAR,PUBLIC,WIN,PASCAL>,<si,di>

	parmD	lp_device		;ptr to a physical device
	parmW	x			;x coordinate of search start
	parmW	y			;y coordinate of search start
	parmD	color			;color for the search
	parmW	dir_style		;control and search style

	localB	planes			;#Planes
	localW	next_plane		;*[bp-6] index to next plane if color

cBegin
;;;	mov	al,enabled_flag 	;Load this before trashing DS
	lds	si,lp_device		;--> physical device
	assumes ds,nothing
	mov	al,[si].bmPlanes
	mov	ah,byte ptr color+3
	mov	cx,[si].bmType		;Get bitmap type
	mov	si,[si].bmWidth
	mov	next_plane, si
	jcxz	scan_30 		;Device is a memory bitmap
;
; This is the screen.
;
	and	ah,7
	mov	al, GRAF_COL_COMP
	mov	dx, EGA_BASE + GRAF_ADDR
	out16	dx, ax
	mov	ax, GRAF_MODE + 8 shl 8
	mov	cs:ega_state_mode, ax
	mov	byte ptr cs:ega_saved, 2
	out16	dx, ax

;	This is the EGA.  Compute and set the exclusion rectangle
;	based on the direction of the search.

ifdef	EXCLUSION
	mov	dx,y			;Set top of exclude area
	mov	di,dx			;Set bottom of exclude area
	dec	si			;Set right
	mov	cx,x			;Assume scanning left to right
	test	bptr dir_style,STEP_LEFT
	jz	scan_10 		;Scanning left to right
	mov	si,cx
	xor	cx,cx			;Scanning right to left

scan_10:
	call	exclude			;Exclude the scan from the screen
endif
	mov	ax, 4001h

scan_30:
	mov	planes, al
	cmp	al, 3
	jz	scan_31
	add	ax, ax
	cwd
	mov	color, dx
scan_31:
	les	di, lp_device
	lds	si, es:[di].bmBits		;Get device bitmap
	mov	ax, y
	mov	di, es:[di].bmWidthBytes	;Get width in bytes
	mul	di
	add	si, ax				;Address of row
	mov	cx, x
scan_80:
	mov	bx,cx
	shiftr	cx,3			;Compute byte offset in scan
	add	si,cx			;DS:SI --> byte with start pixel
	mov	ax,ds			;Will be working off both DS: and ES:
	mov	es,ax
	assumes es,nothing


;	Set cx to be the byte count for searching left.  Must adjust it
;	to include the byte pixel is in.

	inc	cx			;Adjust for partial byte



;	Compute the mask for the first byte (the partial byte).  Since
;	the defaults being set up are for searching left, this can be done
;	by getting the rotating bitmask for the pixel and decrementing it,
;	then using the logical NOT of the mask.  The mask will be used
;	for masking the bits to test in the partial (first) byte.
;
;		Bitmask 	  Mask		NotMask
;
;		10000000	01111111	10000000
;		01000000	00111111	11000000
;		00100000	00011111	11100000
;		00010000	00001111	11110000
;		00001000	00000111	11111000
;		00000100	00000011	11111100
;		00000010	00000001	11111110
;		00000001	00000000	11111111


	and	bx,wptr 00000111B		;Get bit mask for bit
	mov	bl,rot_bit_tbl[bx]	;Assume we're going left.
	dec	bl			;Create mask

;	The assumption has been made that the scan will be right to left.
;	If the scan is left to right, then the first byte mask and the
;	byte count must be adjusted.
;
;	Also set up the correct bias for getting back to the interesting
;	byte for the rep scasb instruction (DI is always updated by one
;	byte too many).


	std				;Assume search left
	mov	dx,1			;(to counter post decrement)
	test	bptr dir_style,STEP_LEFT
	jnz	scan_100		;It is left



	page
;	Compute the first byte mask for the first byte for stepping right.
;
;		Current 	  SHL		  INC		  NOT
;
;		01111111	11111110	11111111	00000000
;		00111111	01111110	01111111	10000000
;		00011111	00111110	00111111	11000000
;		00001111	00011110	00011111	11100000
;		00000111	00001110	00001111	11110000
;		00000011	00000110	00000111	11111000
;		00000001	00000010	00000011	11111100
;		00000000	00000000	00000001	11111110


	cld				;Going right, fix up dir flag
	shl	bl,1			;Fix up first bit mask per above
	inc	bl
	not	bl


;	Compute the number of bytes from current position to end of scanline
;	and set adjustment to counter the rep's post increment

	sub	cx,di			;Fix up byte count
	neg	cx
	inc	cx
	neg	dx			;(to counter post increment)




;	Set the pixel count for the entire scan.  The scanning will actually
;	continue until the end of the scan as given in bmWidthBytes, and
;	the result clipped to bmWidth.

scan_100:
	not	bl			;Need inverse of the first byte mask
	shiftl	di,3			;Set DI = pixel count of entire scan
	cmp	planes,NUMBER_PLANES	;Color scan?
	jne	scan_200		;  No, monochrome




	page
;	For color, all planes will be XORed with the color for that
;	plane, and the results of each XOR will be ORed together.  This
;	will result in all pixels of the given color being a 0, and all
;	pixels not of the color being 1.  Searching for color can be
;	handled with an XOR mask to selectively invert the result.
;
;
;	Currently:	DS:SI --> bitmap or display
;			ES:SI --> bitmap or display
;			BL = first byte mask
;			CX = byte count
;			DX = direction bias
;			DI = bits/scanline


scan_110:
	push	di			;Save bits/scanline
	mov	dx,bx			;DL = first byte mask

if	NUMBER_PLANES eq 4
	mov	ax,wptr color.pcol_C2	;Get C2 and C3 colors
	errnz	pcol_C3-pcol_C2-1
	shiftr	ah,4			;Set 'C' if color is 1
	errnz	C3_BIT-00001000b
	sbb	ah,ah			;AH = FF if 1's, 00 if color 0's
	mov	di,ax			;Set DI to C3, C2
endif

if	NUMBER_PLANES eq 3
	les	di, lp_device
	mov	bx, es:[di].bmWidthPlanes
	mov	dh, bptr color.pcol_C0
	mov	di, wptr color.pcol_C1
	mov	al,[bx+si]	;Value from plane 1
	add	bx, bx
	mov	ah,[bx+si]	;Value from plane 2
	xor	ax, di
	or	ah, al
	lodsb
	xor	al, dh
	or	al, ah
	xor	ah, ah
endif
	test	bptr dir_style, 1	;If searching for the color,
	jz	scan_115		;  want a mask of 1's to be
	dec	ah			;  able to invert the result
	errnz	FIND_NOT_COLOR		;  of the search
	errnz	FIND_COLOR-1
scan_115:
	xor	al,ah			;Adjust the color
	and	al,dl			;Mask out the bits that don't count
	jnz	scan_160		;  Hit.  Check it out
	dec	cx			;Any bytes left?
	jz	scan_160		;  No

	push	bp
	mov	bp, bx
	shr	bx, 1
	mov	dl,ah			;Save final invert mask
;;;	mov	bp,wptr color.pcol_C0	;Set C0 and C1 colors


;	Main loop register usage:
;	    AX	    work
;	    BX	    width of the scan in bytes
;	    CX	    byte count
;	    DH	    intermediate value
;	    DL	    invert mask
;	    BP	    C1 C0 color
;	    DI	    C3 C2 color


scan_140:
;;;	add	si,bx
	mov	al,[si][bx]		;Get C2's byte

if	NUMBER_PLANES eq 4
	shl	bx,1
	mov	ah,[si][bx]		;Get C3's byte
	xor	ax,di			;XOR the colors to mark those different
	or	al,ah			;Combine them
	mov	dh,al			;Save for later
	shr	bx,1
endif

if	NUMBER_PLANES eq 3
	mov	ah, ds:[bp+si]
	xor	ax,di			;XOR the colors to mark those different
	or	ah, al
endif

	lodsb				;Get C0's color, update pointer
	xor	al,dh			;XOR the colors
	or	al,ah			;Combine them
	xor	al,dl			;Invert if needed
	jnz	scan_150		;Hit
	loop	scan_140		;Miss, try next

;	If we fall through here (with 'Z' set), the color (not color)
;	wasn't found.

scan_150:
	pop	bp

scan_160:
	pop	di
	jnz	short scan_230		 ;Found the byte
	jmp	short scan_300		 ;Did not find the byte





;	The desired action of the scan is to be able to do a rep scasb
;	over the scanline until either the color is found or not found.
;	Once the stopping condition is found, it has to be possible to
;	determine which bit was the bit that stopped the scan.
;
;	Monochrome notes:
;
;	    The color will be used as an XOR mask.  If the result of
;	    the XOR is zero, then the byte did not contain any bits of
;	    importance, otherwise we made a hit and need to return the
;	    location of it.
;
;	    If searching for the color, the color must be complemented
;	    so that the XOR will set all bits not of the color to zero,
;	    and leave all bits of the color 1's.  If searching for NOT
;	    the color, then the color can be left as is so that all bits
;	    of the color will be set to zero.  The complement also gives
;	    the compare value for the scasb instruction.
;
;
;	Currently:	DS:SI --> bitmap or display
;			ES:SI --> bitmap or display
;			BL = first byte mask
;			CX = byte count
;			DX = direction bias
;			DI = bits/scanline


scan_200:
	mov	ax,wptr color
	test	bptr dir_style, 1	;If searching for the color,
	jz	scan_210		;  want a mask of 1's to be
	not	ax			;  able to invert the result
	not	bh			;  of the search

;	Check the first byte for a hit or miss.

scan_210:
	lodsb				;Get the first byte
	xor	al,ah			;Adjust the color
	and	al,bl			;Mask out the bits that don't count
	jnz	scan_230		;  Hit.  Check it out

	mov	al,ah			;Otherwise restore register for scan
	dec	cx			;Any bytes left to check?
	jz	scan_300		;  No, show not found

	xchg	si,di			;scasb uses ES:DI
	repe	scasb			;Try for a hit or miss
	jz	scan_300		;Scanned off the end, it's a miss
	inc	cx			;Decremented one time too many
	xchg	si,di
	add	si,dx			;Adjust from post increment/decrement
	lodsb				;Get the byte which we hit on
	xor	al,ah			;Adjust to look for a set bit



;	Had a hit.  Find which pixel it was really in.
;
;	Currently:	CX = byte index pixel is in
;			DI = # pixels in the scan line
;			AL = byte hit was in

scan_230:
	shiftl	cx,3			;Convert byte index to pixel index
	test	bptr dir_style,STEP_LEFT;Scanning Right to left?
	jnz	scan_260		;  yes

scan_240:
	sub	cx,di			;Compute index of first pixel in byte
	neg	cx			;  where hit occured
	dec	cx			;Prepare for loop
;;;	not	cx

scan_250:
	inc	cx			;Show next pixel
	shl	al,1			;Was this the hit?
	jnc	scan_250		;  No, try next
	cmp	cx,next_plane		;Is final x value in range?
	jge	scan_300		;  No, show not found
	jmp	short scan_270		;  Yes, return it

scan_260:
	dec	cx			;Show next pixel
	shr	ax,1			;Was this the hit?
	jnc	scan_260		;  No, try next

scan_270:
	mov	ax,cx			;Return position to caller

scan_280:
	cld


;	If this was for the device, the color read mode must be
;	cleared, both in the register and in the shadow location.
;	The exclusion rectangle must also be cleared.


	mov	byte ptr cs:ega_saved, 0
ifdef	EXCLUSION			;If exclusion
	call	unexclude		;Clear any exclude rectangle
endif


scan_290:

cEnd	<nogen>
	pop	di
	pop	si
	sub	bp, 2
	mov	sp, bp
	pop	ds
	pop	bp
	dec	bp
	retf	0Eh

scan_300:
	mov	ax,ERROR_NOT_FOUND
	jmp	scan_280

sEnd	Code

ifdef	PUBDEFS
	include scanlr.pub
endif

	end
