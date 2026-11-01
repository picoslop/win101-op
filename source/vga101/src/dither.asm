        page    ,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	DITHER.ASM
;
; This file contains the brush dithering algorithm for brushes.
;
; Created: 17-Jan-1987
; Author:  **** ***** [*****]
;
; Copyright (c) 1985-1987 Microsoft Corporation
;
; Exported Functions:	none
;
; Public Functions:	dither
;
; Public Data:		none
;
; General Description:
;
;	The dithering algorithm is called to generate the patterns
;       used for brushes.
;
; Restrictions:
;	The dithering algorithm assumes that the size of the brush is
;	8 x 8.
;
;-----------------------------------------------------------------------;


	.xlist
	include cmacros.inc
	.list


sBegin	Code
assumes cs,Code

dither_d1	db	0, 1, 1, 0
dither_d2	db	0, 1, 0, 1

page
;-----------------------------Public-Routine----------------------------;
; dither
;
; Dither(value, lpBrush)
;
;   This function takes value between 0 - 255 and uses it to create
;   an 8x8 pile of bits that can be used as a brush.  It does this
;   by reducing the input value to a number between 0 - 64 and then
;   turns on that many bits in the 8x8 field.  Thus the value 0 leads
;   to brush of all zeros, a 255 value leads to a brush of all 1's,
;   and a value of 128 leads to grey.
;
;   The algorithm is equivalent to turning on bits based on an array:
;
;	 0 32  8 40  2 34 10 42
;	48 16 56 24 50 18 58 26
;	12 44  4 36 14 46  6 38 	This table favors devices like
;       60 28 52 20 62 30 54 22         the EGA & Hercules cards where the
;	 3 35 11 43  1 33  9 41 	aspect ratio is close to 1:1
;	51 19 59 27 49 17 57 25
;	15 47  7 39 13 45  5 37
;	63 31 55 23 61 29 53 21
;
;
;   Where given a value between 0 - 64, turn on the bit if the array
;   value is less then the desired value.
;
;   When dithering for color drivers, where each plane is dither
;   independently, this algorithm has a nice side effect in that
;   for any value n < m, n is a proper subset of m (any bit turned
;   on in n must have been turned on in m!).
;
;   For the table, undesirable patterns are generated for light
;   and dark grey.  These will be flagged when encountered.
;   The brush realization routines can then substitute the correct 
;   grey (we cannot do it because we do not know if the other planes of 
;   a color brush were the same pattern).
;
;   Reference:	A Survey of Techniques for the Display of Continuous
;		Tone Pictures on Bilevel Displays,;
;		Jarvis, Judice, & Ninke;
;		COMPUTER GRAPHICS AND IMAGE PROCESSING 5, pp 13-40, (1976)
;
; Entry:
;	DL     =  value to dither
;	ES:DI --> destination
;	SI     =  previous grey indicator
; Returns:
;	ES:DI --> next destination (ES:DI + SIZE_PATTERN)
;	DH     =  dither value (0-64)
;	SI     =  New grey indicator (SI << 3 || grey_indicator)
;		    D2:D0 = 001b for dark  grey
;		    D2:D0 = 010b for grey
;		    D2:D0 = 011b for light grey
;		    D2:D0 = 100b for black
;		    D2:D0 = 101b for white
;		    D2:D0 = 000b otherwise
; Error Returns:
;       none
; Registers Destroyed:
;	AX,BX,CX,DX,DS,FLAGS
; Registers Preserved:
;	none
; Calls:
;	none
; History:
;	Sun 15-Feb-1987 18:35:01 -by-  **** ***** [*****]
;	Initial version
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


	public	dither
dither	proc	near

	mov	ax,cs
	mov	ds,ax
	assumes ds,Code
	xor	ax,ax			;Initialise to all zeroes
	stosw
	stosw
	stosw
	stosw
	sub	di, 8
	xor	bh,bh			;Need a zero a few times
	shr	dl,1			;Convert value 0-255 into
	adc	dl,al			;  value 0 - 64
	shr	dl,1
	mov	dh,3			;Will be usefull
	mov	al,1
	cmp	dl,10h
	jz	dither_10
	mov	al,3
	cmp	dl,30h
	jz	dither_10
	xor	ax,ax
dither_10:
	shl	si,1
	shl	si,1
	or	si,ax
dither_20:
	dec	dl
	jl	dither_end
	xor	ax,ax
	mov	cl,dh
	mov	ch,dl
dither_30:
	shl	ax,1
	mov	bl,ch
	and	bl,dh
	add	ah,dither_d1[bx]
	add	al,dither_d2[bx]
	shr	ch,1
	shr	ch,1
	loop	dither_30
	mov	bl, al
	mov	cl, ah
	mov	al, 80h
	shr	al, cl
	or	es:[bx+di],al
	jmp	short dither_20
;
dither_end:
	add	di,8
	ret

dither	endp


	ifdef	PUBDEFS
	include dither.pub
	endif

sEnd	Code
end
