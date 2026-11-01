        page    ,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	EGAHIRES.ASM
;
; This contains code and data that do not appear to have a direct
; equivalent in the Windows 2.0 EGA driver.
;
; Created: 18-Jul-2014
; Author:  John Elliott
;
; Copyright (c) 1984, 2014 Microsoft Corporation
;
; Exported Functions:	none	
;
; Public Functions:	
;			
;
; Public Data:
;
; General Description:
;
; Restrictions:
;
;-----------------------------------------------------------------------;


incDevice = 1				;Include control for gdidefs.inc

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include ega.inc
	include	egamem.inc
	include display.inc
	include macros.mac
	include	cursor.inc
	.list

	externA	X_MINOR_DIST
	externA X_MAJOR_DIST
	externA Y_MINOR_DIST
	externA Y_MAJOR_DIST

sBegin	Code

assumes cs,Code

brush_colors	label byte
	db	0, 0
	db	40h, 40h
	db	80h, 80h
	db	0C0h, 0C0h
	db	0FFh, 0FFh

snip0:	add	di, dx
	sub	cl, Y_MINOR_DIST
	ror	bl, 1
	adc	di, ax
	sub	cl, X_MAJOR_DIST
;
snip1:	add	di, dx
	sub	cl, Y_MINOR_DIST
;
snip2:	ror	bl, 1
	adc	di, ax
	sub	cl, X_MAJOR_DIST
;
snip3:	add	di, dx
	sub	cl, Y_MINOR_DIST

snip4:	rol	bl, 1
	sbb	di, ax
	sub	cl, X_MAJOR_DIST

snip5:	add	di, dx
	sub	cl, Y_MINOR_DIST
	rol	bl, 1
	sbb	di, ax
	sub	cl, X_MAJOR_DIST

snip6:	ror	bl, 1
	adc	di, ax
	sub	cl, X_MINOR_DIST
	add	di, dx
	sub	cl, Y_MAJOR_DIST

snip7:	ror	bl, 1
	adc	di, ax
	sub	cl, X_MINOR_DIST
	add	di, dx
	sub	cl, Y_MAJOR_DIST

snip8:	rol	bl, 1
	sbb	di, ax
	sub	cl, X_MINOR_DIST

snip9:	add	di, dx
	sub	cl, Y_MAJOR_DIST

snip10:	rol	bl, 1
	sbb	di, ax
	sub	cl, X_MINOR_DIST

snip11:	add	di, dx
	sub	cl, Y_MAJOR_DIST
snip12 label near

sniptab	dw	offset snip0, offset snip1, offset snip3, offset snip5
	dw	offset snip6, offset snip7, offset snip8, offset snip10
	dw	offset snip2, offset snip2, offset snip4, offset snip4
	dw	offset snip9, offset snip11, offset snip9, offset snip11

snipdata db	5, 5, 5, 5, 7, 7, 7, 7

sniplen	db	offset snip1 - offset snip0
	db	offset snip3 - offset snip1
	db	offset snip5 - offset snip3
	db	offset snip6 - offset snip5
	db	offset snip7 - offset snip6
	db	offset snip8 - offset snip7
	db	offset snip10 - offset snip8
	db	offset snip12 - offset snip10
	db	offset snip3 - offset snip2
	db	offset snip3 - offset snip2
	db	offset snip5 - offset snip4
	db	offset snip5 - offset snip4
	db	offset snip10 - offset snip9
	db	offset snip12 - offset snip11
	db	offset snip10 - offset snip9
	db	offset snip12 - offset snip11

	public	snipdata, sniplen, sniptab, brush_colors

sEnd	Code

end

