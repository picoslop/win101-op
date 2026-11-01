	page	,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	ROBJECT.ASM
;
; This module contains the code which realizes the objects required
; by GDI.
;
; Created: 19-Feb-1987
; Author:  **** ***** [*****]
;
; Copyright (c) 1983-1987 Microsoft Corporation
;
; Exported Functions:	RealizeObejct
;
; Public Functions:	sum_RGB_colors_alt
;
; Public Data:		none
;
; General Description:
;
; Restrictions:
;
;-----------------------------------------------------------------------;


incLogical	=	1		;Include control for gdidefs.inc


	.xlist
	include cmacros.inc
	include gdidefs.inc
	include display.inc
	include macros.mac
	.list


	??_out	robject


sBegin	Code
assumes cs,Code

	public	sum_RGB_colors_alt	;Alternate entry point
;	public	sum_RGB_alt_far		;Alternate far entry point

	externNP dither 		;Brush dithering code
	externA  BW_THRESHOLD		;Where black becomes white


;	The following are the definitions for the hatch patterns.
;	They are defined by each individual driver base on its
;	resolution.

	externA < H_HATCH_BR_0, H_HATCH_BR_1, H_HATCH_BR_2, H_HATCH_BR_3>
	externA < H_HATCH_BR_4, H_HATCH_BR_5, H_HATCH_BR_6, H_HATCH_BR_7>
	externA < V_HATCH_BR_0, V_HATCH_BR_1, V_HATCH_BR_2, V_HATCH_BR_3>
	externA < V_HATCH_BR_4, V_HATCH_BR_5, V_HATCH_BR_6, V_HATCH_BR_7>
	externA <D1_HATCH_BR_0,D1_HATCH_BR_1,D1_HATCH_BR_2,D1_HATCH_BR_3>
	externA <D1_HATCH_BR_4,D1_HATCH_BR_5,D1_HATCH_BR_6,D1_HATCH_BR_7>
	externA <D2_HATCH_BR_0,D2_HATCH_BR_1,D2_HATCH_BR_2,D2_HATCH_BR_3>
	externA <D2_HATCH_BR_4,D2_HATCH_BR_5,D2_HATCH_BR_6,D2_HATCH_BR_7>
	externA <CR_HATCH_BR_0,CR_HATCH_BR_1,CR_HATCH_BR_2,CR_HATCH_BR_3>
	externA <CR_HATCH_BR_4,CR_HATCH_BR_5,CR_HATCH_BR_6,CR_HATCH_BR_7>
	externA <DC_HATCH_BR_0,DC_HATCH_BR_1,DC_HATCH_BR_2,DC_HATCH_BR_3>
	externA <DC_HATCH_BR_4,DC_HATCH_BR_5,DC_HATCH_BR_6,DC_HATCH_BR_7>
page
;--------------------------Exported-Routine-----------------------------;
; RealizeObject
;
;   RealizeObject - Logical to Physical Object Realization
;
;   RealizeObject performs the task of converting logical objects
;   into physical objects that this driver can manipulate to per-
;   form the various functions requested of it.
;
;   The size needed to realize an object will be returned if the
;   pointer to where the physical realization is to be stored is
;   NULL.
;
;   In some cases where the driver cannot realize the requested object,
;   a solid color pen must be realized which GDI will use when it
;   performs the nessacary simulations.  In other cases, punt.
;
; Entry:
;	None
; Returns:
;	AX = object size if ok
; Error Returns:
;	AX = 0	if error or object unrealizable
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;
; History:
;	Mon 16-Feb-1987 18:09:09 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,Data
assumes es,nothing


cProc	RealizeObject,<FAR,PUBLIC,WIN,PASCAL>,<si,di>

	parmD	lp_device		;Pointer to Device structure
	parmW	style			;Style of realization
	parmD	lp_in_obj		;Pointer to input (logical) object
	parmD	lp_out_obj		;Pointer to output (physical) object
	parmD	lp_text_xform		;Pointer to a text transformation
					;  or (x,y) for brush realization
					;  Segment = y, Offset = x

	localW	plane_start
	localB	brush_accel		;Temp brush accelerator
	localB	prev_dither		;Brush dither value
	localW	bw_sum			;Black & white sum for a brush
	localV	l_brush,%(size oem_brush_def)

cBegin

	cld				;Following code assumes this
;;;	mov	ax,1			;Assume good exit
	mov	bx,style		;If delete object, nothing to do
	or	bx,bx			;  since we don't keep objects
	jns	realize_10
	jmp	realize_exit1		;This is a delete object
realize_10:
	lds	si,lp_in_obj		;--> logical object
	assumes ds,nothing

;;;	dec	ax			;Assume error (AX = 0 as return code)
	dec	bx			;Determine style of realization.
	cmp	bx,OBJ_FONT-1		;Is it a legal object?
	jg	j_realize_exit0		;  Not by our standards, return error
	shl	bx,1			;Compute index into dispatch table
	mov	ax, wptr lp_out_obj	;If lp_out_obj is NULL, then return
	or	ax, wptr lp_out_obj+2	;  size requirement?
	jz	return_obj_size 	;They want the size
	jmp	cs:realize_dispatch[bx] ;Realize a physical object

return_obj_size:
	mov	ax,cs:realize_sizes[bx] ;Get size for the object
	jmp	realize_exit

j_realize_exit0:
	jmp	realize_exit0

page
;--------------------------Private-Routine------------------------------;
; realize_pen
;
;   Realize Logical Pen Into a Physical Pen
;
;   The given logical pen is realized into a physical pen.
;
;   The pen will be realized regardless of the pen width or
;   style since GDI will need a pen to use for simulations.
;
;   If the width of the pen is >1, then a solid pen will be
;   realized regardless of the pen style.  GDI will use this
;   pen for simulating the wide line.
;
;   If the pen style isn't recognized, then a solid pen of
;   the given color will be realized (this is called punting).
;
; Entry:
;	DS:SI --> logical pen definition
;	ES:DI --> output object
; Returns:
;	AX non-zero to show success
; Error Returns:
;	No error return.
; Registers Preserved:
;	BP,DS,ES
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,FLAGS
; Calls:
;	sum_RGB_colors
; History:
;	Thu 19-Feb-1987 14:06:41 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing


realize_pen:
	mov	cx,[si].lopnStyle	;If a NULL pen, then all that really
	cmp	cx,LS_NOLINE		;  needs to be stored is the pen
	je	realize_pen_30		;  type so it can be recognized
	cmp	[si].lopnWidth,2	;If not a nominal width pen,
	jb	realize_pen_20		;  make a solid pen for simulations
realize_pen_10:
	mov	cx, LS_SOLID
realize_pen_20:
	cmp	cx,MaxLineStyle 	;If the line style is unknown
	jg	realize_pen_10		;  make it a solid pen
realize_pen_30:
	lea	si,[si].lopnColor	;--> RGB color
	call	sum_RGB_colors		;Sum up the color
	les	di,lp_out_obj

	stosw				;Save color of pen
	mov	ax,dx
	stosw
	mov	ax,cx			;Save style
	stosw
	jmp	realize_exit1	

	errnz	oem_pen_pcol		;Must be first field
	errnz	pcol_C0 		;Colors must be in this order
	errnz	pcol_C1-pcol_C0-1
	errnz	pcol_C2-pcol_C1-1
	errnz	pcol_C3-pcol_C2-1
	errnz	oem_pen_style-4 	;Style must be 4 bytes into phys pen

page
;--------------------------Private-Routine------------------------------;
; realize_brush
;
;   Realize Logical Brush Into a Physical Brush
;
;   Four styles of logical brushes may be realized.  These are SOLID,
;   HOLLOW, HATCHED, and PATTERN.
;
;   A SOLID brush is defined with a logical RGB color definition.
;   This color is processed into one of 65 dithers.
;
;   A HATCHED brush is defined with a logical RGB color definition and
;   a hatching type.  The hatch type is mapped to one of the six hatched
;   styles that the driver supports.  All bits in the hatched brush which
;   are 1 are set to the hatch color passed in, and all bits which are
;   0 are set to the background color passed in.
;
;   A PATTERN brush is defined with an 8 X 8 pattern in the form of a
;   physical bitmap.  The bitmap may be monochromw or color.  More
;   discussion on converting is contained under the pattern brush code.
;
;   A HOLLOW brush is one which can never be seen.  The brush style is
;   maintained in the device brush structure so that a check can be
;   made and an abort executed if one is used.	No punting is needed
;   for hollow brushes.
;
;   Brushes will be aligned based at the (x,y) origin passed in via
;   the text transform.
;
; Entry:
;	DS:SI --> logical pen definition
;	ES:DI --> output object
; Returns:
;	None
; Error Returns:
;	None
; Registers Preserved:
;	BP
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,ES,DS,FLAGS
; Calls:
;
; History:
;	Thu 19-Feb-1987 14:06:41 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing


realize_brush:
	mov	di, ss
	mov	es, di
	lea	di, l_brush

	mov	bx,[si].lbStyle 	;Get the brush style.
	cmp	bx,MaxBrushStyle	;If an illegal brush, create
	jle	realize_brush_10	;  a solid brush
	mov	bx, 0

realize_brush_10:
	add	bx,bx			;Call routine which will do the
	jmp	cs:brush_realizations[bx];  actual realization

page
;--------------------------Private-Routine------------------------------;
; realize_hollow
;
;   Realize Hollow Brush
;
;   This is sleazy.  Hollow brushes are implemented by checking
;   the style flag, and ignoring the contents of the oem_brush_def
;   structure
;
; Entry:
;	DS:SI --> logical object
;	ES:DI --> temp brush area
; Returns:
;	DL = oem_brush_accel flags
; Error Returns:
;	None
; Registers Preserved:
;	BP,DI,ES,DS,FLAGS
; Registers Destroyed:
;	BX
; Calls:
;	None
; History:
;	Thu 19-Feb-1987 14:06:41 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


realize_hollow:
	lea	di, [di].oem_brush_style
	mov	bx, BS_HOLLOW
	jmp	realize_common


page
;--------------------------Private-Routine------------------------------;
; realize_solid
;
;   Realize Solid Style Brush
;
;   The given logical solid brush is realized.	Each color for
;   the brush (RGB) is dithered for the color bruhses.
;
;   The sum of all the colors is used to determine the dither
;   to use for monochrome portion of the brush.
;
; Entry:
;	DS:SI --> logical object
;	ES:DI --> output object
; Returns:
;	DL = oem_brush_accel flags
; Error Returns:
;	None
; Registers Preserved:
;	BP,ES,DS,FLAGS
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,FLAGS
; Calls:
;	dither
;	sum_RGB_colors_alt
; History:
;	Thu 19-Feb-1987 14:06:41 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing


realize_solid:
	lea	si, [si].lbColor

;	mov	ax,wptr [si].lbColor	;AL = Red, AH = Green
;	mov	dl,bptr [si].lbColor[2] ;DL = Blue
	xor	cx,cx
	mov	cl,[si+2]
	push	cx			;Save blue for later
	mov	cl,[si+1]
	push	cx			;Save green for later
	mov	cl,[si]			;Save red for later
	call	sum_RGB_colors		;Compute black/white sum
	mov	bw_sum,bx		;Save B/W sum for later
	lea	di, l_brush
	mov	si, ss
	mov	es, si

;	If the brush is solid, then the colors returned by
;	sum_RGB_colors_alt for C0_BIT, C1_BIT, and C2_BIT will
;	be the correct colors for the brush.  ONES_OR_ZEROS
;	will also be valid.  If the brush isn't a solid, then
;	the accelerator for SOLID_BRUSH won't be set and
;	these bits will be ignored.  The MONO_BIT is ignored
;	for brushes.

;;;	and	dh,C0_BIT+C1_BIT+C2_BIT+ONES_OR_ZEROS
;;;	or	dh,GREY_SCALE		;Assume it is a grey scale brush
;;;	mov	brush_accel,dh

	xor	si,si			;Clear "grey" flags
	mov	dx,cx			;Dither the red into C0
	call	dither
;;;	mov	prev_dither,dh		;Save dither index

	pop	dx			;Dither the green into C1
	call	dither
;;;	xor	dh,prev_dither		;Clear GREY_SCALE if not a match
;;;	cmp	dh,1			;  'C' if equal
;;;	sbb	al,al			;  0FF if equal, 00 if non-equal
;;;	or	al,not GREY_SCALE	;  Only want to remove GREY_SCALE
;;;	and	brush_accel,al

	pop	dx			;Dither the blue
	call	dither
;;;	xor	dh,prev_dither
;;;	cmp	dh,1
;;;	sbb	al,al
;;;	or	al,not GREY_SCALE
;;;	and	brush_accel,al


;	Both the dithering alogrithms may generate an undesirable grey
;	(lores for 808080, hires for 404040 and C0C0C0), so these are
;	special cased to a known grey that will be uniform across the
;	devices, and is known to have a satisfactory apperance.
;
;	Solid brushes (all 0's or all 1's in a plane) must also
;	be checked for and the SOLID_BRUSH accelerator set if
;	needed.

	or	si,si			;Was this one of the greys or solids?
	jz	solid_brush_20		;  No, skip all this special stuff
	cmp	si,010101b		;Dark grey in all three planes?
	jz	solid_brush_10
	cmp	si,101010b		;Grey in all three planes
	jz	solid_brush_10
	cmp	si, 111111b
	jnz	solid_brush_20
solid_brush_10:
	add	si,si			;Fill with desired grey
	and	si,wptr 00000111b
	mov	ax,cs:greys[si][-2]
	mov	cx,SIZE_PATTERN*3
	sub	di,cx			;--> back to start of this plane
	shr	cx,1
	rep	stosw

solid_brush_20:
	mov	ax,bw_sum		;Get monochrome color
	cwd
	mov	si,3
	div	si
	mov	dx,ax
	xor	si,si
	call	dither


;	Both the dithering algorithms may generate an undesirable grey
;	(lores for 808080, hires for 404040 and C0C0C0), so these are
;	special cased to a known grey that will be uniform across the
;	devices, and is known to have a satisfactory apperance.

	or	si,si			;Was this one of the greys?
	jz	solid_brush_30		;  No
;;;	test	si,100b 		;If black or white, ignore it
;;;	jnz	solid_brush_30		;  Was black or white
	add	si,si			;Special case the grey
	mov	ax,cs:greys[si][-2]
	sub	di,SIZE_PATTERN
	stosw
	stosw
	stosw
	stosw
	errnz	SIZE_PATTERN-8

solid_brush_30:
	mov	bx,BS_SOLID		;Set type of brush
	jmp	realize_common

greys	label	word
	db	088h,022h		;Dark grey dither
	db	0AAh,055h		;Grey dither
	db	0DDh,077h		;Light grey dither

page
;--------------------------Private-Routine------------------------------;
; realize_pattern
;
;   Realize Pattern brush
;
;   The given bitmap is copied for use as a 8x8 bit pattern brush.
;   Any information beyond the first 8x8 bits is not required to be
;   maintained as part of the brush, even though GDI does allow
;   you to do this if desire.
;
;   If the bitmap is a monochrome bitmap, it is to be expanded up
;   into a black/white bitmap.	If the bitmap is a color bitmap,
;   then to compute the monochrome portion of the brush, the planes
;   will be ANDed together (this favors a white background).
;
;   This code doesn't correctly handle huge bitmaps as the source
;   for a pattern.
;
; Entry:
;	DS:SI --> logical object
;	ES:DI --> output object
; Returns:
;	DL = oem_brush_accel flags
; Error Returns:
;	None
; Registers Preserved:
;	BP,ES,FLAGS
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,DS,FLAGS
; Calls:
;	None
; History:
;	Thu 19-Feb-1987 14:06:41 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing


realize_pattern:

;;;	mov	brush_accel,0		;No accelerators set for the brush
	lds	si,[si].lbPattern	;Get pointer to the bitmap
	assumes ds,nothing

	mov	dx,[si].bmWidthBytes	;Get physical width of bitmap
	dec	dx			;MOVSB automatically increments
	mov	bx,wptr [si].bmWidthPlanes ;Get width of one plane
	mov	ah,3			;Setup color planes loop count
	cmp	[si].bmPlanes,3		;Set 'Z' if color
	lds	si,[si].bmBits		;--> where the bits are
	assumes ds,nothing

	je	realize_pattern_10	;Handling color source
	xor	bx,bx			;Mono source, zero plane increment
;;;	mov	brush_accel,GREY_SCALE	;This is a grey scale

realize_pattern_10:
	mov	plane_start, si		;Save start of plane
	mov	cx,SIZE_PATTERN 	;Set # bytes to move

realize_pattern_20:
	movsb				;Move one byte of pattern
	add	si,dx			;Skip rest of scanline
	loop	realize_pattern_20	;Until one plane has been moved
	mov	si, plane_start		;Get back start of plane
	add	si,bx			;--> start of next plane

;	dec	ah,1			;(need to test "above" and "below")
	sub	ah,1			;Done all three planes yet?
	ja	realize_pattern_10	;  No
	jb	realize_pattern_40	;  Just handled monochrome source


;	Handle the monochrome plane of the brush.  If the source is a
;	monochrome bitmap, then just copy it as is.  If the source is
;	a color bitmap, then AND all the colors together to get the
;	color of the destination (favors white background).

	or	bx,bx			;Monochrome?
	jz	realize_pattern_10	;  Yes, just copy mono data again
	mov	cl,SIZE_PATTERN
	errnz	<SIZE_PATTERN AND 0FF00H>


;	Use the bits just copied into the brush area since we know
;	where they are and what the offset between planes is.

realize_pattern_30:
	mov	al,es:[di][-(1*SIZE_PATTERN)]	;Get C2
	and	al,es:[di][-(2*SIZE_PATTERN)]	;AND with C1
	and	al,es:[di][-(3*SIZE_PATTERN)]	;AND with C0
	stosb					;Store mono byte
	loop	realize_pattern_30

realize_pattern_40:
	mov	bx,BS_PATTERN
	jmp	short realize_common
;
page
;--------------------------Private-Routine------------------------------;
; realize_hatch
;
;   Realize a Hatched Brush
;
;   The requested hatched brush is realized.  Two colors are invloved
;   for hatched brushes, the background color, and the hatch color.
;   If these two colors are the same, then the brush will be a
;   solid brush, and the solid brush code will be invoked
;
;   If not, then all 0 bits in the hatch pattern will be set to the
;   background color, and all 1 bits will be set to the foreground
;   color.  Note that hatched colors are solid colors; no dithering
;   takes place for their realization.
;
; Entry:
;	DS:SI --> logical object
;	ES:DI --> output object
; Returns:
;	DL = oem_brush_accel flags
; Error Returns:
;	None
; Registers Preserved:
;	BP,ES,DS,FLAGS
; Registers Destroyed:
;	AX,BX,CX,DX,SI,DI,FLAGS
; Calls:
;	move_hatch
; History:
;	Thu 19-Feb-1987 14:06:41 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing


realize_hatch:

	mov	cx,[si].lbHatch 	;Get hatch style
	cmp	cx,MaxHatchStyle	;Hatch style within range?
	jle	realize_hatch_10	;  Yes
	jmp	realize_solid		;  No, create a solid brush

realize_hatch_10:
	lea	si,[si].lbBkColor	;Compute background color
	call	sum_RGB_colors
	push	dx			;Save background rgb + mono color info

	lea	si,[si].lbColor-lbBkColor	;Compute foreground color
	call	sum_RGB_colors
	pop	ax			;Get background rgb + mono color info
	mov	dl,ah			;dh = forground, dl = background info

	mov	bx,cx			;Compute address of hatch pattern
	shl	bx,1
	shl	bx,1
	shl	bx,1
	lea	bx,hatched_brushes[bx]	;bx --> hatch pattern to use

	errnz	SIZE_PATTERN-8		;Pattern must be this size

	call	move_hatch		;Move C0
	call	move_hatch		;Move C1
	call	move_hatch		;Move C2
	mov	cl, 3
	ror	dh, cl			;Skip over C3 reserved bit
	ror	dl, cl
	call	move_hatch		;Move hatch brush
	mov	bx,BS_HATCHED		;Set brush style
	jmp	short realize_common	

	errnz	  C0_BIT-00000001b
	errnz	  C1_BIT-00000010b
	errnz	  C2_BIT-00000100b
	errnz	  C3_BIT-00001000b
	errnz	MONO_BIT-00010000b
	errnz	oem_brush_C0
	errnz	oem_brush_C1-oem_brush_C0-SIZE_PATTERN
	errnz	oem_brush_C2-oem_brush_C1-SIZE_PATTERN
	errnz	oem_brush_mono-oem_brush_C2-SIZE_PATTERN


page
;--------------------------Private-Routine------------------------------;
; move_hatch
;
;   Move Hatch Brush
;
;   The bits for one plane of a hatched brush are moved according
;   to the foreground and background colors passed in.	If the
;   colors are the same, then that color will be moved into the
;   brush.  If the colors are different, then either the pattern
;   or the inverse will be moved into the brush.   The pattern
;   will be moved in if the foreground color is 0, and the inverse
;   will be moved in if the foreground color is 1 (the brushes
;   were defined for a foreground color of 0 and a background
;   color of 1)
;
; Entry:
;	DH:D0  =  foreground color info (0/1)
;	DL:D0  =  background color info (0/1)
;	CS:BX --> hatch pattern to use
;	ES:DI --> next plane of destination brush
; Returns:
;	DH:D0  =  next foreground color info (0/1)
;	DL:D0  =  next background color info (0/1)
;	CS:BX --> hatch pattern to use
;	ES:DI --> next plane of destination brush
; Error Returns:
;	None
; Registers Preserved:
;	BP,DI,ES,DS,FLAGS
; Registers Destroyed:
;	AX,CX,SI,FLAGS
; Calls:
;	None
; History:
;	Thu 19-Feb-1987 14:06:41 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing


move_hatch	proc near

	mov	si, bx
	mov	cx,SIZE_PATTERN		;Set up move for a single plane
	errnz	<SIZE_PATTERN and 1>	;Must be an even number of bytes

	ror	dh,1			;Place next foreground color into D7
	ror	dl,1			;Place next background color into D7
;;;	sbb	si,si			;SI = FFFF if bit was set
	mov	al,dh
	cbw
	xor	al,dl			;Set 'S' if different colors
	js	move_hatch_10		;Colors are different
	mov	si, offset brush_zeroes	;The colors are the same, so just
					;  create a solid plane of the color

move_hatch_10:
move_hatch_20:
	lods	bptr cs:[si]		;Get next word of pattern
	xor	al, ah			;Invert it if needed
	stosb				;Stuff it away
	loop	move_hatch_20
;;;	lea	bx,[si].-SIZE_PATTERN	;Restore hatch pointer
	ret

move_hatch	endp


realize_common:
	lea	si, [di-20h]		;XXX
	les	di,lp_out_obj		;--> back to start of oem_brush_def
	assumes es,nothing
	mov	dx, 7
	mov	cx,off_lp_text_xform	;Get the X origin
	and	cl,dl
	mov	es:[di].oem_brush_style,bx ;Save brush accelerator
	mov	bx,seg_lp_text_xform	;Get the Y origin
	mov	ah,4
realize_common_10:
	mov	ch,8
realize_common_20:
	lods	byte ptr ss:[si]
	ror	al,cl
	and	bx, dx
	mov	es:[bx+di], al
	inc	bx
	dec	ch
	jnz	realize_common_20
	add	di, SIZE_PATTERN
	dec	ah
	jnz	realize_common_10
	lea	si, [si-4*SIZE_PATTERN]	;Restore pattern pointer
	mov	ax, ss
	mov	ds, ax
	push	di
	xor	bx, bx
	xor	dx, dx
	xor	di, di
	mov	cx, 4008h
realize_common_30:
	xor	ax, ax
	mov	al, [si + 2 * SIZE_PATTERN]
	add	bx, ax
	mov	al, [si + SIZE_PATTERN]
	add	dx, ax
	lodsb
	add	di, ax
	mov	ah, 0BFh
	cmp	al, [si + SIZE_PATTERN - 1]
	jnz	realize_common_40
	cmp	al, [si + 2*SIZE_PATTERN - 1]
	jnz	realize_common_40
	not	ah
realize_common_40:
	and	ch, ah
	dec	cl
	jnz	realize_common_30
	mov	ax, 7F8h
	or	bx, bx
	jz	realize_common_50
	cmp	bx, ax
	jnz	realize_common_80
realize_common_50:
	or	dx, dx
	jz	realize_common_60
	cmp	dx, ax
	jnz	realize_common_80
realize_common_60:
	or	di, di
	jz	realize_common_70
	cmp	di, ax
	jnz	realize_common_80
realize_common_70:
	and	di, 100h
	or	cx, di
	and	dh, 2
	or	ch, dh
	and	bh, 4
	or	ch, bh
	or	ch, 80h
realize_common_80:
	pop	di
	mov	es:[di+2],ch

realize_exit1:
	mov	al, 1
	jmp	short realize_exit
;
page
;--------------------------Private-Routine------------------------------;
; realize_font
;
;   Realize a Font
;
;   Realize font is the routine that realizes a logical font into a
;   physical font.  It is possible to punt on this routine and have
;   GDI's font manager realize the desired font, or something close
;   to it, by returning the error code (ax = 0).  That's what I'm
;   going to do.
;
; Entry:
;	AX = 0
; Returns:
;	AX = 0
; Error Returns:
;	AX = 0
; Registers Preserved:
;	BP
; Registers Destroyed:
;	None
; Calls:
;	None
; History:
;	Thu 19-Feb-1987 14:06:41 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing


realize_font:
realize_exit0:	
	xor	ax, ax

realize_exit:
	pop	di
	pop	si
	sub	bp, 2
	mov	sp, bp
	pop	ds
	pop	bp
	dec	bp
	retf	12h	
cEnd <nogen>


page
;--------------------------Public-Routine-------------------------------;
; sum_RGB_colors
; sum_RGB_colors_alt
;
;   Sum Given RGB Color Triplet
;
;   The given RGB color triplet is summed, and the result returned
;   to the caller.  Other useful information is also returned.
;
;   It is this routine which maps the colors to the bit planes
;   of the EGA.
;
;   Ordering of the color in a dword is such that when stored in
;   memory, red is the first byte, green is the second, and blue
;   is the third.  The high order 8 bits may be garbage when passed
;   in, and should be ignored.
;
;   when in a register:     xxxxxxxxBBBBBBBBGGGGGGGGRRRRRRRR
;
;   when in memory:	    db	    red,green,blue
;
;
; Entry:
;	DS:SI --> RGB triplet to sum	    (for sum_RGB_colors)
;	AL     =  Red	value of triplet    (for sum_RGB_colors_alt)
;	AH     =  Green value of triplet    (for sum_RGB_colors_alt)
;	DL     =  Blue	value of triplet    (for sum_RGB_colors_alt)
; Returns:
;	BX		= Sum of the triplet
;	AL		= 0FFh if red	intensity (AL) > 127
;	AL		= 000h if red	intensity (AL) < 128
;	AH		= 0FFh if green intensity (AH) > 127
;	AH		= 000h if green intensity (AH) < 128
;	DL		= 0FFh if blue	intensity (DL) > 127
;	DL		= 000h if blue	intensity (DL) < 128
;	DH:C0		= red	intensity msb
;	DH:C1		= green intensity msb
;	DH:C2		= blue	intensity msb
;	DH:C3		= undefined for three plane mode
;	DH:MONO_BIT	= 0 if BX < BWThreashold
;			= 1 if BX >= BWThreashold
;	DH:ONES_OR_ZERO = 1 if C0:C2 are all 1's or all 0's
;	DH:GREY_SCALE	= 0
;	DH_SOLID_BRUSH	= 0
; Error Returns:
;	None
; Registers Preserved:
;	CX,SI,DI,DS,ES
; Registers Destroyed:
;	CX,FLAGS
; Calls:
;	None
; History:
;	Thu 19-Feb-1987 14:06:41 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


assumes ds,nothing
assumes es,nothing

;;;sum_RGB_alt_far	proc far
;;;	call 	sum_RGB_colors_alt
;;;	ret
;;;sum_RGB_alt_far	   endp

sum_RGB_colors	proc	near

	mov	ax,word ptr [si]	;AH = G, AL = R
	mov	dl,byte ptr [si][2]	;DL = B

sum_RGB_colors_alt proc near

	push	cx			;Don't destroy cx
	xor	dh,dh			;Turn R, G, and B into bytes
	xor	bx,bx
	xor	cx,cx
	xchg	ah,cl
	add	bx,ax			;Sum the colors for the mono bit
	add	bx,dx
	add	bx,cx
;;;	cmp	bx,BW_THRESHOLD 	;Set 'C' if mono color is to be black
;;;	cmc				;Set 'C' if mono color is to be white
;;;	rcl	dh,1			;Move in MONO_BIT
;;;	shl	dh,1			;Skip C3

	mov	ah,cl			;Restore green value
	mov	cl,8			;Compute individual R,G,B values
	sar	dl,cl			;Compute blue
	rcl	dh,1			;Move blue into mono byte
	sar	ah,cl			;Compute green
	rcl	dh,1			;Move green into mono byte
	sar	al,cl			;Compute red
	rcl	dh,1			;Move red into mono byte
	errnz	C0_BIT-00000001b
	errnz	C1_BIT-00000010b
	errnz	C2_BIT-00000100b
	errnz	C3_BIT-00001000b
	errnz	MONO_BIT-00010000b
	cmp	bx,BW_THRESHOLD 	;Set 'C' if mono color is to be black
	jl	sum_RGB_colors_exit
	or	dh, GREY_SCALE

;;;	or	dh,ONES_OR_ZEROS	;Assume color is black or white
;;;	cmp	dh,ONES_OR_ZEROS
;;;	je	sum_RGB_colors_exit
;;;	cmp	dh,ONES_OR_ZEROS+MONO_BIT+C0_BIT+C1_BIT+C2_BIT
;;;	je	sum_RGB_colors_exit
;;;	and	dh,not ONES_OR_ZEROS

sum_RGB_colors_exit:
	pop	cx			;Restore callers CX
	ret

sum_RGB_colors_alt endp
sum_RGB_colors	   endp

assumes ds,nothing
assumes es,nothing


page
;	brush_realizations
;
;	brush_realizations contains the address of the function
;	that performs the realization of the desired type of brush.

brush_realizations label word

	dw	realize_solid
	dw	realize_hollow
	dw	realize_hatch
	dw	realize_pattern

brush_zeroes	label	word
	dw	0,0,0,0

	errnz	BS_SOLID
	errnz	BS_HOLLOW-BS_SOLID-1
	errnz	BS_HATCHED-BS_HOLLOW-1
	errnz	BS_PATTERN-BS_HATCHED-1





;	Predefined Hatched Brushes
;
;	The following brushes are the predefined hatched brushes that
;	this driver knows about.


hatched_brushes label	byte

	db	 H_HATCH_BR_0, H_HATCH_BR_1, H_HATCH_BR_2, H_HATCH_BR_3
	db	 H_HATCH_BR_4, H_HATCH_BR_5, H_HATCH_BR_6, H_HATCH_BR_7
	db	 V_HATCH_BR_0, V_HATCH_BR_1, V_HATCH_BR_2, V_HATCH_BR_3
	db	 V_HATCH_BR_4, V_HATCH_BR_5, V_HATCH_BR_6, V_HATCH_BR_7
	db	D1_HATCH_BR_0,D1_HATCH_BR_1,D1_HATCH_BR_2,D1_HATCH_BR_3
	db	D1_HATCH_BR_4,D1_HATCH_BR_5,D1_HATCH_BR_6,D1_HATCH_BR_7
	db	D2_HATCH_BR_0,D2_HATCH_BR_1,D2_HATCH_BR_2,D2_HATCH_BR_3
	db	D2_HATCH_BR_4,D2_HATCH_BR_5,D2_HATCH_BR_6,D2_HATCH_BR_7
	db	CR_HATCH_BR_0,CR_HATCH_BR_1,CR_HATCH_BR_2,CR_HATCH_BR_3
	db	CR_HATCH_BR_4,CR_HATCH_BR_5,CR_HATCH_BR_6,CR_HATCH_BR_7
	db	DC_HATCH_BR_0,DC_HATCH_BR_1,DC_HATCH_BR_2,DC_HATCH_BR_3
	db	DC_HATCH_BR_4,DC_HATCH_BR_5,DC_HATCH_BR_6,DC_HATCH_BR_7

	errnz	HS_HORIZONTAL
	errnz	HS_VERTICAL-HS_HORIZONTAL-1
	errnz	HS_FDIAGONAL-HS_VERTICAL-1
	errnz	HS_BDIAGONAL-HS_FDIAGONAL-1
	errnz	HS_CROSS-HS_BDIAGONAL-1
	errnz	HS_DIAGCROSS-HS_CROSS-1
	errnz	MaxHatchStyle-HS_DIAGCROSS






;	realize_dispatch
;
;	realize_dispatch contains the address of the procedure which
;	is invoked to realize a given object.

realize_dispatch label	word

	dw	realize_pen
	dw	realize_brush
	dw	realize_font

	errnz	OBJ_PEN-1
	errnz	OBJ_BRUSH-OBJ_PEN-1
	errnz	OBJ_FONT-OBJ_BRUSH-1




;	realize_sizes
;
;	realize_sizes contains the size of the memory required to realize
;	each of the objects.  These sizes will be returned to GDI when it
;	inquires the memory needed far an object.


realize_sizes	label	word

	dw	SIZE oem_pen_def
	dw	SIZE oem_brush_def
	dw	0

	errnz	OBJ_PEN-1
	errnz	OBJ_BRUSH-OBJ_PEN-1
	errnz	OBJ_FONT-OBJ_BRUSH-1

sEnd	Code

	ifdef	PUBDEFS
	include robject.pub
	endif

end
