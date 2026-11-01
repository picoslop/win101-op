        page    ,132
;-----------------------------Module-Header-----------------------------;
; Module Name:	OUTPUT.ASM
;
;   This module contains the dispatch routine for the Output function.
;
; Created: 22-Feb-1987
; Author:  **** ***** [*****]
;
; Copyright (c) 1984-1987 Microsoft Corporation
;
; Exported Functions:	Output
;
; Public Functions:	none
;
; Public Data:		none
;
; General Description:
;
;   Those functions of output which are supported by this driver
;   are dispatched to.
;
; Restrictions:
;
;-----------------------------------------------------------------------;


	??_out	output

incLogical	= 1			;Include GDI Logical object definitions
incOutput	= 1			;Include control for gdidefs.inc
incDrawMode	= 1			;Include GDI DrawMode definitions

Y_MAJOR		equ	1		;Y is the major axis
STEP_LEFT	equ	2		;The DDA is stepping right
STEP_UP		equ	4		;The DDA is stepping up

?CHKSTK	= 1
?CHKSTKPROC	macro
		endm

	.xlist
	include cmacros.inc
	include gdidefs.inc
	include ega.inc
	include macros.mac
	include display.inc
	include genconst.blt
	.list


sBegin	Code
assumes cs,Code
page

	externB dm_flags
	externB dm_pen_and
	externB dm_pen_xor
	externB dm_data_r
	externW	ega_saved
	externW	ega_state_rot
	externW	ega_state_mask
	externW	ega_state_mode
	externW	ega_state_graf
	externW sniptab
	externB snipdata
	externB sniplen
	externB rot_bit_tbl
	externB	bitmask_tbl1
	externB	bitmask_tbl2
	externW	rop_indexes
	externB	rop_lengths
	externA MAX_STYLE_ERR

	externNP ega_set_op
	externNP exclude
	externNP unexclude

; List of line styles	
style_table	label	 byte
	db	11111111B		;Solid line
	db	11100111B		;Dashed
	db	10101010B		;Dotted
	db	11100100B		;Dot-dash
	db	11101010B		;Dash-dot-dot
	db	00000000B		;No line

X18FF:	mov	bp, si
	inc	si
	shr	si, 1
	mov	ah, [di]
	mov	al, bh
;
X1908:	or	ch, ch
	js	X1910
	mov	al, ss:byte ptr [1234h]
;
X1910:	or	ch, ch
	jns	X191C
X1914:	xor	al, ah
	and	al, bl
	xor	al, ah
	mov	[di], al
X191C:	xor	ax, ax

X191E:	jns	X1925
	add	cl, MAX_STYLE_ERR
	rol	ch, 1
X1925:	dec	bp
X1926:	jg	X1926
	retf
;
X1929:	ror	bl, 1
	jc	X1931
	dec	bp
	jg	X1929
X1930:	retf
;
X1931:	inc	di
	dec	bp
	jle	X1930
X1935:	cmp	bp, 8
	jl	X1929
	mov	ah, [di]
	mov	al, bh
X193E:	mov	[di], al
	inc	di
	sub	bp, 8
	jg	X1935
	retf
;
X1947:	ror	bl, 1
	jc	X194F
	dec	bp
	jg	X1947
X194E:	retf
;
X194F:	inc	di
	dec	bp
	jle	X194E
;
X1953:	cmp	bp, 8
	jl	X1947
	mov	ax, 0FF00h + GRAF_BIT_MASK
	mov	dx, EGA_BASE + GRAF_ADDR
	cli
	out	dx, ax
	mov	al, [di]
	mov	[di], bh
	sti
	inc	di
	sub	bp, 8
	jg	X1953
	retf
;
X196C:	or	ch,ch
	jns	X1984
X1970:	push	dx
	mov	dx, EGA_BASE + GRAF_ADDR
	mov	ah, bl
	mov	bl, al
	mov	al, GRAF_BIT_MASK
	cli
	out	dx, ax
	mov	al, [di]
	mov	[di], bl
	sti
	mov	bl, ah
	pop	dx
X1984:	xor	ax, ax

;--------------------------Exported-Routine-----------------------------;
; Output
;
;   Output is the entry point for output functions such as lines,
;   scanlines, arcs, etc.  Those functions which are supported
;   will be dispatched to.  If the function is not supported, an
;   error code will be returned.
;
; Entry:
;	None
; Return:
;	Per sub-function
; Error Returns:
;	Per sub-function
;	AX = 0 if sub-function not supported
; Registers Preserved:
;	SI,DI,DS,BP
; Registers Destroyed:
;	AX,BX,CX,DX,ES,FLAGS
; Calls:
;	scanlines
;	lines
; History:
;	Wed 04-Mar-1987 12:25:32 -by-  **** ***** [*****]
;	Created.
;-----------------------------------------------------------------------;


;------------------------------Pseudo-Code------------------------------;
; {
; }
;-----------------------------------------------------------------------;


	assumes ds,Data
	assumes es,nothing


cProc	Output,<FAR,PUBLIC,WIN,PASCAL>,<si,di>

	parmD	lp_dst_dev		;--> to the destination
	parmW	style			;Output operation
	parmW	count			;# of points
	parmD	lp_points		;--> to a set of points
	parmD	lp_phys_pen		;--> to physical pen
	parmD	lp_phys_brush		;--> to physical brush
	parmD	lp_draw_mode		;--> to a Drawing mode
	parmD	lp_clip_rect		;--> to a clipping rectange if <> 0

	localW	bp04			; [bp-4] 
	localD	bp08			; [bp-8] 
	localW	CurStyle		; [bp-0A] 
	localD	CurByte			; [bp-0E] Destination address
	localW	gl_scan_inc		; [bp-10] Increment to next scanline
	localW	gl_rop			; [bp-12] Rop
	localW	gl_bitmap_width_bytes	; [bp-14] Bitmap width, bytes
	localB	bp17			; [bp-15]
	localB	RotBitMask		; [bp-16]
	localB	gl_jumptype		; [bp-17]
	localB	bp1A			; [bp-18]
	localB	gl_planereg		; [bp-19]
	localB	bp1C			; [bp-1A]
	localB	gl_bkMode		; [bp-1B] bkMode
	localB	bp1E			; [bp-1C]
	localW	gl_width_planes		; [bp-1E]
	localW	bp22			; [bp-20]
	localD	gl_bkColor		; [bp-24] background colour
	localD	gl_pen_pcol		; [bp-28] pen colour
	localV	bpBC,%96h
cBegin	
	jnc	output_begin
	jmp	output_end
output_begin:
	cld
	mov	bp17, 0FFh
	lds	si, lp_draw_mode
	mov	ax, wptr [si].bkColor
	mov	wptr gl_bkColor, ax
	mov	ax, wptr [si].bkColor+2
	mov	wptr gl_bkColor+2, ax	
	mov	ax, [si].bkMode
	mov	gl_bkMode, al
	mov	bx, [si].Rop2
	dec	bx
	and	bx, word ptr 0Fh
	mov	gl_rop, bx
	lds	si, lp_points
	mov	ax,[si].ycoord
	lds	si, lp_dst_dev
	les	di,[si].bmBits
	mov	cx,wptr [si].bmPlanes
	cmp	cx, 101h	;Mono?
	jz	output_10
	cmp	cx, 103h
	jnz	output_return_error
	or	bh, 2
output_10:
	mov	cx, wptr [si].bmWidthPlanes
	mov	gl_width_planes, cx
	cmp	cx, 1
	rcr	bh, 1
	mov	bp1A, bh
	mov	dx, [si].bmWidthBytes
	mov	gl_bitmap_width_bytes, dx
	mul	dx
	add	di, ax
	mov	off_CurByte, di
	mov	seg_CurByte, es
	mov	ax, style		;Get the style parameter
	cmp	ax,OS_POLYLINE		;Is this a polyline
	je	do_polylines		;  Yes
	cmp	ax,OS_SCANLINES 	;Is this a scanline ?
	jne	output_return_error	;  No, return an error

dispatch_scanlines:
	jmp	do_scanlines

output_ret1:
	mov	ax, 1
	jmp	short output_return

output_return_error:
	xor	ax,ax			;Show error
output_return:
	call	unexclude
	mov	byte ptr cs:ega_saved, 0

output_end:

cEnd	<nogen>
	pop	di
	pop	si
	sub	bp, 2
	mov	sp, bp
	pop	ds
	pop	bp
	dec	bp
	retf	1Ch
;
sEnd	Code

;----------------------------Module-Header------------------------------;
; Module Name: polyline.asm
;
; Brief Description: Polyline drawing device driver.
;
; Created: 3/3/87
; Author: **** ******	(******)
;
; Copyright (c) 1983 - 1987  Microsoft Corporation
;
; Given a set of points, draw a set of polylines connecting adjoining
; points.  Depending on whether we are writing to the EGA or a bitmap
; we initialize as necessary.  Solid and styled lines are handled.
; Small (<= 64k bytes) monochrome and color bitmaps and huge monochrome
; and color bitmaps are all supported.  A run length slice algorithm is
; used to determine the pixels used to draw each line.  The algorithm is
; explained later on.  
;
; The line drawing code is slightly different depending on whether
; we are drawing solid lines to the EGA, solid lines to a bitmap, or
; styled lines to either the EGA or a memory bitmap.  For the sake
; of speed, a different set of line drawing routines is called
; for each case.  Only the case we are using will be brought into memory.
; In almost every case, only one of these destinations at a time will 
; be used.  If the user wants to draw lines to the EGA and a bitmap at the
; same time, for example, then they will have both of these sets of 
; routines in memory at the same time, and are hosed on memory.
;
; There are sixteen raster operations (sets of logical operations) performed
; on the data written out.  When writing to the EGA there are four of
; these operations which take two passes of EGA memory.  In each of these
; cases the first passes sets the necessary bits in the necessary planes
; to ones or zeros explicitly.  The second pass then XORs the necessary
; bit in the necessary planes.  The other twelve raster operations can
; be done in one pass of EGA memory.  All raster operations are done in
; one pass of memory for bitmaps.  Depending on the raster operation and
; the color of the pen, it is easily determined whether we set bits to 
; zeros, set bits to ones, invert bits or do nothing.  Bitmaps are written
; to one plane at a time.  In the case of a mono bitmap, only one plane is
; written to.
;
; Styled lines are drawn in two passes.  The first pass draws the line color.
; The second pass draws the gap color.  If we are writing to the EGA and
; have one of the four raster operations which takes two passes of EGA memory,
; then a total of four passes will have to be made.  Two passes to draw
; the line color and two more to draw the gap color.  Styled lines are 
; drawn one pixel at a time.  there is no efficient way around this due
; to the rotating style error term which has to be updated with each bit
; output.  It, unfortunately, depends on the value of the bit, which makes
; outputting a byte at a time expensive to set up.
;
; !!! For the release of Driver 2.0 small bitmaps are stored on a plane !!!
; !!! by plane basis (ie if we have three color planes, then the segment !!!
; !!! is stored as the red color plane, green color plane and then the !!!
; !!! blue color plane).  For the release of Driver 3.0 this will need to !!!
; !!! be changed to match the format of huge bitmaps. !!!
;
; Huge bitmaps are stored on a scan line basis.  For example, if we have
; three color planes, the the bitmap is stored as a red scan line, a green
; scan line, a blue scan line, a red scan line, and so on.  Because of this
; format, there will most likely be some left over bytes at the end of the
; segment.  These will have to be accounted for when crossing segment
; boundaries.  
;
; All lines, except vertical, are drawn from left to right.
;-----------------------------------------------------------------------;


;	This function will perform private stack checking.  In order for
;	private stack checking to occur, two symbols must be defined
;	prior to the inclusion of cmacros.inc.  ?CHKSTK must be defined
;	if the cmacros are to perform stack checking on procedures with
;	local parameters.  ?CHKSTKPROC must be defined if private stack
;	checking will be used.
;
;	The actual macro body for ?CHKSTKPROC will be defined later.
;
;	Since the stack-checking code is designed to work quickly
;	as a near subroutine, and normally resides in segment Code, a
;	duplicate is included in the segment _LINES.  To reach this,
;	the macro ?CHKSTKNAME is defined.


	externA SCREEN_W_BYTES
	externA ScreenSelector
	externA	SCREEN_WIDTH
	externA	SCREEN_HEIGHT
	externA	HYPOTENUSE
	externA	Y_MAJOR_DIST
	externA	X_MAJOR_DIST
	externA	Y_MINOR_DIST
	externA	X_MINOR_DIST
	externA	MAX_STYLE_ERR

	externFP Code_check_stack

ifdef	EXCLUSION
	externNP exclude   		; exclude area from screen.
	externNP unexclude 		; clear excluded area.
endif



sBegin	Code
assumes cs,Code


page

;--------------------------Public-Routine-------------------------------;
; do_polylines(lp_dst_dev,style,count,lp_points,lp_phys_pen,lp_phys_brush,
;	       lp_draw_mode,lp_clip_rect)
;
; DWORD lp_dst_dev 			// pointer to destination.
; short	style				// output operation.
; short count				// number of points.
; DWORD lp_points			// pointer to set of points.
; DWORD lp_phys_pen			// pointer to physical pen.
; DWORD lp_phys_brush			// pointer to physical brush.
; DWORD	lp_draw_mode			// pointer to drawing mode.
; DWORD lp_clip_rect			// pointer to clipping rect if <> 0.
;
; do_polylines initializes things for the line drawing routines.  if
; the lines are being drawn to the EGA, then the EGA is initialized 
; as necessary and the exclusion area is handled.  if the lines are
; being written to a bitmap, information about the bitmap is loaded.
; necessary tables and pointers are set up depending on line style and
; destination device.  When all of the necessary initialization is
; complete, we jump to polyline_loop which does the DDA and the line
; drawing.
;
; Entry: per parameters.
;
; Returns: AX = 1 if polylines drawn.
;
; Error Returns: AX = 0 if polylines not drawn.
;
; Registers Destroyed: AX,BX,CX,DX,DS,flags.
;
; Registers Preserved: DI,SI.
;
; Calls: 
;	 polyline_set_ega_for_one_pass
;	 polyline_set_ega_for_two_pass
;	 exclude_far	(far version of exclude)
;	 unexclude_far	(far version of un_exclude)
;
; History:
;  Tue 18-Aug-1987 14:50:37 -by-	**** *****	    [*****]
; Added test of the disabled flag.
;
;  Thu 30-Apr-1987 13:20:00	-by-	**** ******	    [******]
; Added huge bitmap handling.
;
;  Wed 08-Apr-1987 10:32:33	-by-	**** ******	    [******]
; Modified to draw all lines moving right.
;
;  Mon 23-Feb-1987 12:56:41	-by-	**** ******	    [******]
; Major re-write.
;
;  Tue 28-Oct-1986 16:05:04	-by-    **** ********	    [*****]
; Created.
;-----------------------------------------------------------------------;

;---------------------------Pseudo-Code---------------------------------;
; do_polylines(lp_dst_dev,style,count,lp_points,lp_phys_pen,lp_phys_brush,
;	       lp_draw_mode,lp_clip_rect)
;
; DWORD lp_dst_dev 			// pointer to destination.
; short	style				// output operation.
; short count				// number of points.
; DWORD lp_points			// pointer to set of points.
; DWORD lp_phys_pen			// pointer to physical pen.
; DWORD lp_phys_brush			// pointer to physical brush.
; DWORD	lp_draw_mode			// pointer to drawing mode.
; DWORD lp_clip_rect			// pointer to clipping rect if <> 0.
;
; {
;    if (style is not a polyline)
;        return(0);			// return that line is not drawn.
;
;    // for speed considerations EGA specific code is separated from
;    // memory bitmap specific code.
;
;    if (destination is bitmap)
;        jump to get_bitmap_info;
;
;    // handle exclusion area on the screen.
;
;#ifdef EXCLUSION
;    assume exclusion area is entire screen;
;
;    if (passed a clipping rectangle)
;        set exclusion to passed clipping rectangle;
;
;    exclude_far();			// exclude scan from the screen.
;#endif
;
;    jump to load_color_info;
;
;    // get bitmap specific information,  this section is skipped over
;    // if destination is the EGA.
;
;get_bitmap_info:
;    assume monochrome bitmap;
;    get number of color planes;
;    if (number of planes > 1)
;        DeviceFlags = DEST_IS_BITMAP+DEST_IS_COLOR;
;
;    NumPlanes = number of planes;
;
;    // the following group of information is found from the current
;    // bitmap structure.
;
;    BitmapSegment = starting segment of bitmap;
;    NextPlane = index to the next plane;
;    NextScan = index to next scan line;
;    BitmapOffset = starting offset of bitmap;
;
;    // check to see if small or huge bitmap.  if it is huge, this is a
;    // good time to load huge bitmap information.
;
;    if (small bitmap)
;        jump to load_color_info;
;
;    // load huge bitmap information.
;
;    DeviceFlags |= DEST_IS_HUGE;
;
;    SegIndex = index to the next segment;
;    FillBytes = number of fill bytes at end of segment;
;    ScansSeg = scan lines per segment;
;
;    // huge bitmaps are stored in groups of scan lines.  For example, with
;    // three color planes, the bitmap is stored as a scan line of the first
;    // color plane, a scan line of the second color plane, a scan line of the
;    // third color plane, a scan line of the first color plane, and so on.
;    // therefore, when writing to a color plane, a move to the next scan line
;    // actually has to jump over three scan lines.
;
;    NextPlane = NextScan;		// reset index to next plane.
;    NextScan *= Numplanes;		// reset index to next scan line.
;
;    // load the pen and line style information.  this is done for both
;    // EGA and bitmaps.
;
;load_color_info:
;    TmpColor = current pen color;
;    get current line style;
;
;    if (line style > MaxLineStyle)
;        return(0);			// exit with error.
;
;    if (line style == 0)
;        return(1);			// do nothing.
;
;    // get raster operation from draw mode structure.
;
;    DrawModwIndex = raster operation;
;
;    index = current line style;
;    CurStyle = style mask indexed in style_table;
;
;    if (styled line)
;    {
;        // the same style information is needed for both EGA and bitmaps.
;        // get the background mode and store it as the high byte of
;        // StyleFlags and store CurByte as the low byte.  also, get the
;        // gap color and set the rotating style information.
;
;        BackMode = background mode;
;        BackColor.SPECIAL = background color;
;        high byte of StyleFlags = BackMode;
;        low byte of StyleFlags = CurStyle;
;        StyleLength = MAX_STYLE_ERR;
;    }
;
;    // load flag to see if raster op can be done in one pass of EGA memory.
;
;    SingleFlag = dm_flags + DrawModeIndex;
;
;    if (destination is bitmap)
;        jump to set_bitmap_table;	// skip EGA stuff.
;    
;    PenANDFlag = dm_pen_and + DrawModeIndex;
;    PenXORFlag = dm_pen_xor + DrawModeIndex;
;    DataROTFlag = dm_data_r + DrawModeIndex;
;
;    // depending on whether the raster op can be done in one pass of EGA
;    // memory or not, we set up the EGA differently.
;
;    if (raster op can be done in one pass)
;        polyline_set_ega_for_one_pass();
;    else
;        polyline_set_ega_for_two_pass();
;
;    // point to the appropriate set of tables.
;
;    if (solid line)
;    {
;	 DDAstandardProcTable = CodeOFFSET ega_standard_routines;
;	 DDAsimpleProcTable = CodeOFFSET ega_simple_routines;
;    }
;    else
;    {
;        StyledProc => styled_line_pixel;  // ega styled line output routine.
;	 DDAstandardProcTable = CodeOFFSET styled_standard_routines;
;	 DDAsimpleProcTable = CodeOFFSET styled_simple_routines;
;    }
;
;    jump to set_up_loop;		// skip over bitmap stuff.
;
;set_bitmap_table:
;    if (solid line)
;    {
;	 DDAstandardProcTable = CodeOFFSET bitmap_standard_routines;
;	 DDAsimpleProcTable = CodeOFFSET bitmap_simple_routines;
;    }
;    else
;    {
;        StyledProc => styled_bitmap_line_pixel; // bitmap line routine.
;	 DDAstandardProcTable = CodeOFFSET styled_standard_routines;
;	 DDAsimpleProcTable = CodeOFFSET styled_simple_routines;
;    }
;
;set_up_loop:
;    // assume destination is not huge bitmap.
;
;    OverflowProc = CodeOFFSET dont_check_overflow;
;
;    get first polyline point;
;
;    point CurByte at that point;
;    if (destination is huge bitmap)
;    {
;        // we have a huge bitmap.  compute which segment the Y coordinate
;        // is in. set up SegmentNum to show which segment number this
;        // point is in. set SEG_CurByte to the segment which the point is in.
;
;        SegmentNum = current segment number;
;        SEG_CurByte = current segment;
;    }
;
;    index = x coordinate;
;    index &= PARTIAL_BYTE_MASK;	// get bit offset.
;    BL = rot_bit_tbl + index;		// get rotating bitmask in BL.
;
;    jump to polyline loop;
;
;exit_polyline:
;    if (destination is EGA)
;    {
;        restore EGA to default state;
;#ifdef EXCLUSION
;        unexclude_far();		// free up the exclusion area.
;#endif
;
;    return(1);				// indicate success.
; }
;-----------------------------------------------------------------------;

	assumes ds,Data
	assumes es,nothing

do_polylines:
	test	bh, 80h
	jz	load_color_info


; This is the EGA.  For speed considerations on the screen,
; perform the EGA specific calculations seperate from memory
; bitmaps.

; take care of the exclusion area on the screen.  this has to do with the
; mouse pointer, so we will not have to worry about this with a memory bitmap.

ifdef	EXCLUSION
	xor	cx,cx			;Assume entire screen
	xor	dx,dx	
	mov	di, [si].bmHeight
	dec	di
	mov	si, [si].bmWidth
	dec	si

	lds	bx,lp_clip_rect 	;See if there is a clipping rectangle
	assumes ds,nothing
	mov	ax,ds
	or	ax,bx
	jz	polyline_exclude_scan 	;There was no clipping rectangle

	mov	cx,[bx].left		;Set exclusion to passed clipping
	mov	dx,[bx].top		;  rectangle.
	mov	si,[bx].right
	mov	di,[bx].bottom

polyline_exclude_scan:
	call	exclude
endif
	mov	ax, 3
	mov	cs:ega_state_rot, ax
	mov	cs:ega_state_mode, 5
	mov	bptr cs:ega_saved, 4
	call	ega_set_op
	mov	ax, 0FF00h + GRAF_BIT_MASK
	mov	cs:ega_state_graf, ax
	out	dx, ax
; load the pen color and line style information.  this is done for both
; bitmaps and the ega.

load_color_info:
	lds	si,lp_phys_pen		;Get current pen

	mov	ax, wptr [si].oem_pen_pcol
	mov	wptr gl_pen_pcol, ax
	mov	ax, wptr [si].oem_pen_pcol+2
	mov	wptr gl_pen_pcol+2, ax
	mov	bx,[si].oem_pen_style	;Get and save line style
	cmp	bx,MaxLineStyle 	;Legal line style?
	jg	output_return_error	;  No, abort
	jz	output_ret1		;  Null, exit
	errnz	MaxLineStyle-LS_NOLINE
	test	byte ptr bp1A, 1
	jnz	polyline_30
	mov	al, ah			;Colour 'special' byte
	shl	al, 1
	cbw
	mov	bptr gl_pen_pcol, ah
	mov	al, bptr gl_bkColor+3
	shl	al, 1
	cbw
	mov	bptr gl_bkColor, ah
polyline_30:
					; from the line style passed in, get
	mov	ah,cs:style_table[bx]	; a style mask from the table, and
	mov	al, MAX_STYLE_ERR	; save that in CurStyle.
	dec	al
	mov	CurStyle, ax
	call	cpolyline		;X1C1F
;	set up polyline loop (dest byte calculation)

	lds	si,lp_points		;--> first point
	lodsw
	mov	dx,ax			;Save X coordinate
	errnz	xcoord
	lodsw
	mov	cx,ax			;Save Y coordinate
	errnz	ycoord-xcoord-2
	mov	di,dx
	shr	di, 1
	shr	di, 1
	shr	di, 1
	add	di, wptr CurByte	; Add address of bitmap
	mov	bx, dx
	and	bx, word ptr 7
	mov	bl, cs:rot_bit_tbl[bx]
	mov	ax,count		;Set count of line segments

; polyline_loop
;
; polyline_loop contains the run length slice algorithm DDA.
; when this routine is entered, it is passed the coordinates of the first
; point.  it gets the next point and draws the line between them.  the
; first point of the line is drawn and the last point is not.  this is 
; so when raster operations such as XOR are done, the end points do not
; get drawn twice and cancel each other.  different line drawing routines
; are called depending on the destination device and the type of line
; being drawn.
;
; the DDA algorithm used here is based on Jack Bresenham's Run Length
; Algorithm for Incremental Lines.  NATO ASI Series.  Volume F17.
; Fundamental Algorithms for Computer Graphics.  Springer-Verlag
; Berlin Heidelberg  1985.
;
; ALGORITHM
;
; // Given two integer points (x1,y1) and (x2,y2), the following algorithm
; // will calculate run lengths or slices of constant direction movement to 
; // increment a rastered line from (x1,y1) to (x2,y2) under the constraint
; // that unit steps are restricted to those eight axial/diagonal moves in
; // which the x and/or y positions change only by 1, 0, or -1 per step.
;
; HALF OCTANT NORMALIZATION
;
; // Normalize the directed line segment to a standard first partial octant,
; // zero origin form.
;
; delta_x = x2 - x1;
; delta_y = y2 - y1;
; delta_major = max(delta_x, delta_y);
; delta_minor = min(delta_x, delta_y);
; del_b = min(delta_minor, (delta_major - delta_minor));
;
; // Determine true display incremental directions (m11,m12) and (m21,m22) 
; // which correspond to full first octant diagonal and axial unit steps,
; // then re-order as appropriate for pseudo-axial, pseudo-diagonal partial
; // octant movement pairs (s11,s12) and (s21,s22).
;
; m21 = (delta_x >= 0) ? 1 : -1;
; m22 = (delta_y >= 0) ? 1 : -1;
; m11 = (abs(delta_x) >= abs(delta_y)) ? m21 : 0;
; m12 = (abs(delta_x) >= abs(delta_y)) ? 0 : m22;
;
; if (delta_major >= 2 * delta_minor)
; {
;	s11 = m11;
;	s12 = m12;
;	s21 = m21;
;	s22 = m22;
; }
; else
; {
;	s11 = m21;
;	s12 = m22;
;	s21 = m11;
;	s22 = m12;
; }
;
; // Provisionally specifiy HLast to accomodate the degenerate cases of 
; // movement solely in an axial or diagonal direction.
;
; HLast = delta_major;
;
; if (del_b > 0)
; {
;	// PARAMETERS
;
;	// Calculate parameters for the repetitive run length generaton loop.
;
;	BitCount = delta_major / del_b;	// bits per intemediate line segment.
;
;	r = delta_major % del_b;
;
;	m = BitCount / 2;
;
;	n = even(q) ? r : (r + del_b);
; 
;	if ((delta_y >= 0) || (n != 0))
;		HFirst = m;		// bits per first line segment.
;	else
;		HFirst = m -1;		// bits per first line segment.
;
;	if ((delta_y < 0) || (n != 0))
;		HLast = m;		// bits per last line segment.
;	else
;		HLast = m - 1;		// bits per last line segment.
;
;	DDAcount = del_b;		// number of intermediate line segments.
;
;	// Bias the initial decision variable to generate retractable lines.
;	
;	if (delta_y >= 0)
;		ErrTerm = n + 2*r - 2*del_b;
;	else
;		ErrTerm = n + 2*r - 2*del_b - 1;
;
;	// INITIAL RUN LENGTH
;
;	// Output initial run length pair.  First run of length HFirst is
;	// in the direction (s11,s12).  The single diagonal step of length
;	// one is in direction (s21,s22).
;
;	for (i = 0; i < HFirst; i++)
;	{
;		x1 += s11;
;		y1 += s12;
;	}
;
;	x1 += s21;
;	x2 += s22;
;
;	// INTERMEDIATE RUN LENGTH LOOP
;
;	// select appropriate run and output successive intermediate run
;	// length pairs associated with movement directions given by
;	// (s11,s12) and (s21,s22).
;
;	while (-- count)
;	{
;		if (ErrTerm >= 0)
;		{
;			hi = BitCount;	// the ith intermediate segment.
;			ErrTerm += 2*r - 2*del_b;
;		}
;		else
;		{
;			hi = BitCount - 1;
;			ErrTerm += 2*r;
;		}
;
;		for (j = 0; j < hi; j++)
;		{
;			x1 += s12;
;			x2 += s12;
;		}
;
;		x1 += s21;
;		y1 += s22;
;	}
; }
;
; // TERMINATION
;
; // output final single run length in direction (s11,s12).
;
; for (i = 0; i < HLast; i++)
; {
;	x1 += s11;
;	x2 += s12;
; }
;
; // END OF ALGORITHM.
;
;
; Entry: 
;	AX = number of points to process + 1.
;	BL = rotating bit mask.
;	CX = first Y coordinate.
;	DX = first X coordinate.
;	DI = offset of current byte.
;	DS:SI points to next point.
;
; Returns: None.
;
; Error Returns: None.
;
; Registers Destroyed: AX,BX,CX,DX,DI,SI,DS,flags.
;
; Registers Preserved: None.
;
; Calls: 
;	 ega_line_dispatch_routine
;	 bitmap_line_dispatch_routine
;	 polyline_set_ega_for_one_pass
;	 polyline_set_ega_for_two_pass
;
; History:
;  Thu 30-Apr-1987 13:20:00	-by-	**** ******	    [******]
; Added huge bitmap handling.
;  Wed 08-Apr-1987 10:32:33	-by-	**** ******	    [******]
; Modified to draw all lines moving right.
;  Mon 23-Feb-1987 12:56:41	-by-	**** ******	    [******]
; Major re-write.
;  Tue 28-Oct-1986 16:05:04	-by-    **** ********	    [*****]
; Created.
;-----------------------------------------------------------------------;

;---------------------------Pseudo-Code---------------------------------;
; polyline_loop
;
; {
;    number of points--;
;    if (number of points == 0)
;        jump to exit_polyline;		// no more lines to do.
;
;    // set some variables.
;
;    RotBitMask = BL;
;    OFF_CurByte = DI;
;    TmpCurByte = DI;
;
;    get the next point;
;
;    if (destination is huge bitmap)
;    {
;        // compute which 64K block of memory the end point is in.  if 
;        // both points are in the same segment, then we don't need to
;        // check for segment overflow, otherwise we do.
;
;        compute segment end point is in;
;        if (ending segment == starting segment)
;            OverflowProc => dont_check_overflow;
;        else
;            OverflowProc => check_segment_overflow;
;
;        // we have a huge bitmap.  compute which segment the Y coordinate
;        // is in. set up SegmentNum to show which segment number this
;        // point is in. 
;
;        SegmentNum = number of current segment.
;    }
;
;    CaseFlags = 0;
;
;    // depending on whether delta x is positive or negative, we will
;    // set the stepping left or right bit.
; 
;    if (delta x >= 0)
;        jump to x2_ge_x1;		// moving right.
;
;    delta x *= -1;			// make it positive.
;    CaseFlags |= STEPLEFT;		// indicate moving left.
;
;    // the following bunch of ugliness is to set up CurByte when we are
;    // drawing a left moving line.  we will be drawing all lines moving
;    // right.  so when we draw a left moving line, we have to jump CurByte
;    // over to the left side of the line, then draw the line, and then
;    // reset CurByte one last time.
;
;    reset OFF_CurByte to left endpoint of line;
;
;    if (destination is huge bitmap)
;    {
;        // we have a huge bitmap.  compute which segment the Y coordinate
;        // is in. set up SegmentNum to show which segment number this
;        // point is in. set SEG_CurByte to the segment which the point is in.
;
;        SegmentNum = number of current segment;
;        SEG_CurByte = current segment;
;        TmpSegment = current segment; 	// segment reset value.
;    }
;
;    set new RotBitMask;
;    TmpBitMask = RotBitMask;		// save a copy.
;
;    swap Y1 and Y2;			// since we are drawing line backwards.
;
;    // depending on whether delta y is positive or negative, set the 
;    // stepping up or down bit.
;
;x2_ge_x1:
;    AddVertStep = NextScan;		// set up scan line jumping values.
;    SubVertStep = - NextScan;
;
;    if (delta y >= 0)
;        jump to y2_ge_y1;		// moving down.
;
;    delta y *= -1;			// make it positive.
;    CaseFlags |= Y_MAJOR;		// indicate moving up.
;
;    AddVertStep = -NextScan;		// reverse scan line jumping values.
;    SubVertStep = NextScan;
;
;    // depending on the relative values of delta x and delta y we decide
;    // whether the line is x or y major and set the bit accordingly.
;
;y2_ge_y1:
;    if (delta x < delta y)
;        CaseFlags |= Y_MAJOR;		// indicate y major.
;
;    // if delta_major >= 2*delta_minor then the line is axial, else
;    // it is diagonal, and we set the bit accordingly.
;
;    if (delta_major < 2 * delta_minor)
;        CaseFlags |= DIAGONAL;		// indicate diagonal line.
;
;    // now all of the CaseFlags are set to point us to the correct case
;    // if the procedure table.  we now want to check the value of del_b
;    // to see if we have a simple case.  if del_b = 0 then we have a 
;    // simple case.
;    // del_b = min(delta_minor, (delta_major - delta_minor)).
;
;    del_b = min(delta_minor, (delta_major - delta_minor));
;
;    if (del_b == 0)
;    {
;        // we have a simple case.  by simple it is meant that the line is
;        // horizontal, vertical or on a diagonal.  these cases can be 
;        // handled much faster than other cases, so they are broken out
;        // separately.  call the proper routine, depending on whether we 
;        // are writing to a bitmap or the EGA.  by setting up for the call
;        // slightly differently from the standard line case, we are able to
;        // use the same line drawing procedure.  in a simple case, delta_major
;        // is equal to the total number of pixels of the entire line.
;
;        HFirst = delta_major;		// total # of pixels to draw.
;
;        // point to the proper set of routines.
;
;        DDAcurrentProcTable = DDAsimpleProcTable;
;
;        if (writing to the EGA)
;        {
;            ega_line_dispatch_routine();	// go draw the line.
;            jump to polyline_get_return;
;        }
;        else
;        {
;            bitmap_line_dispatch_routine;	// go draw the line.
;            jump to ignore_two_pass_setup;
;        }
;    }
;
;    // if we get here, we do not have one of the simple cases.  the next
;    // thing to do is to calculate the parameters for the repetitive
;    // run length generation loop.
;
;    BitCount = delta_major / del_b; 		// bits per intermediate segment.
;    
;    if (BitCount is even)
;        n = r (remainder from above division);
;    else
;	 n = r + del_b;
;
;    if (delta y < 0 && n == 0)
;        HFirst = m - 1;		// decrement first segment length.
;    else
;        HFirst = m;
;
;    if (delta y >= 0 && n == 0)	
;        HLast = m - 1;			// decrement last segment length.
;    else
;        HLast = m;
;
;    DDAcount = del_b;			// set number of segments.
;    DDAtmpcount = del_b;		// save a copy.
;
;    // now calculate the proper error term.
;
;    if (delta y >= 0)
;        ErrTerm = n + 2*r - 2*del_b;
;    else
;        ErrTerm = n + 2*r - 2*del_b - 1;
;
;    ErrAdj = 2*r;
;    ErrReset = 2*r - 2*del_b;
;
;    DDAcurentProcTable = DDAstandardProcTable;
;
;    if (destination is bitmap)
;    {
;        bitmap_line_dispatch_routine();
;        jump to ignore_two_pass_setup;
;    }
;    else
;        ega_line_dispatch_routine();
;
;polyline_get_return:
;    if (raster op was done in one pass)
;        jump to ignore_two_pass_setup;
;
;    // only do the following if finishing up a line with a raster op which
;    // took two passes of EGA memory, since the EGA would be all screwed
;    // up to start the next line.
;
;    polyline_set_ega_for_two_pass();
;
;ignore_two_pass_setup:
;    if (moving left)
;    {
;        DI = TmpCurByte;		// reset current byte pointer.
;        BL = TmpBitMask;		// reset bitmask.
;    }
;
;    get next point to be processed;
;
;    jump to polyline_loop;		// process the next line.
; }
;-----------------------------------------------------------------------;

polyline_loop:

	dec	ax			; any lines to draw?
	jg	plineloop_10	
	jmp	output_ret1		; no, then exit.

plineloop_10:
	push	ax    	 		; save # of points left to process
	push	ds			; save point pointer
	push	si
	mov	wptr CurByte,di		; save current byte offset
	mov	RotBitMask,bl		; save RotBitMask

	mov	ax,[si].xcoord		; get new X coordinate
	mov	di,[si].ycoord		; get new Y coordinate
	xor	bx,bx			; zero stepping flags


; It will take less time to refetch the (x,y) pair that was just
; fetched at the end of the loop than to push them onto the stack
; and then pop them at the end of the loop.

; AX = x2
; CX = y1
; DX = x1
; SI = y2

;	cmp	CurStyle,0FFh		
;	je	set_for_solid

; assume styled line is not moving left and set up style parameters as such.

;	mov	XMajorDist,X_MAJOR_DIST
;	mov	YMajorDist,Y_MAJOR_DIST
;	mov	XMinorDist,X_MINOR_DIST
;	mov	YMinorDist,Y_MINOR_DIST
;	mov	Hypot,HYPOTENUSE

; depending on whether delta x is positive or negative, we will then
; set the stepping left or right bits.

set_for_solid:
;	mov	bx,ax			; save X2 in BX.
	sub	ax,dx			; AX = delta_x
	jnc	x2_ge_x1
gots_to_be_left:
	mov	bl,STEP_LEFT		; vs stepRight
	neg	ax			; AX = abs(delta_x)
x2_ge_x1:
	mov	dx, ax
	mov	ax, di	
	mov	si, gl_bitmap_width_bytes
	mov	gl_jumptype, 7Dh	;JNL
	mov	byte ptr [bp-0BCh], 90h	;NOP
	sub	ax, cx
	jnc	dx_ge_dy	
	neg	ax
	or	bl, Y_MAJOR
	neg	si
	mov	gl_jumptype, 7Fh	;JG
	mov	byte ptr [bp-0BCh], 46h	;INC SI
dx_ge_dy:
	mov	cx, ax
	cmp	cx, dx
	jc	y2_ge_y1
	or	bl, STEP_UP
	xchg	cx, dx
y2_ge_y1:
	mov	gl_scan_inc, si
	or	dx, dx
	jnz	pline_10
	mov	di, wptr CurByte
	mov	bl, RotBitMask
	jmp	pline_90
;
pline_10:
	mov	ax, cs
	mov	ds, ax
	mov	di, bp04
	or	cx, cx
	jnz	pline_20
	or	bl, 8	;XXX
	test	bl, 4	;XXX
	jnz	pline_20
	cmp	bptr CurStyle+1, 0FFh
	jnz	pline_20
	cmp	bp17, bl
	jz	pline_50
	mov	bp17, bl
	push	dx
	call	X1CEE
	pop	dx
	jmp	short pline_50
;
pline_20:
	test	bl, 8	;XXX
	jnz	pline_30
	mov	ax, I_SUB_SI_WORD_I
	stosw
	mov	ax, cx		;nnnn
	stosw
	mov	ah, cs:snipdata[bx]
	add	ah, 4
	mov	al, gl_jumptype
	stosw
	mov	ax, I_ADD_SI_WORD_I
	stosw
	mov	ax, dx
	stosw
pline_30:
	cmp	bp17, bl
	jz	pline_50
	mov	bp17, bl
	mov	cl, cs:sniplen[bx]
	xor	ch, ch
	add	bx, bx
	mov	si, cs:sniptab[bx]
	mov	bx, di
	rep	movsb
pline_31:
	mov	si, offset X1925
	mov	cl, 4
	cmp	bptr CurStyle+1, 0FFh
	jz	pline_40
	mov	si, offset X191E
	mov	cl, 0Bh
pline_40:
	rep	movsb	
	mov	ax, wptr bp08
	sub	ax, di
	add	ax, 6
	mov	es:[di-2], al
pline_50:	
	mov	bp22, dx
	mov	gl_planereg, 21h
pline_60:
	cmp	bptr bp1A, 81h
	jnz	pline_70
	mov	ah, gl_planereg
	and	ah, 7
	mov	al, SEQ_MAP_MASK
	mov	dx, EGA_BASE + SEQ_ADDR
	mov	cs:ega_state_mask, ax
	out	dx, ax
	shr	ah, 1
	mov	al, GRAF_READ_MAP
	mov	dl, GRAF_ADDR
	out	dx, ax
pline_70:
	lds	di, CurByte
	mov	dx, gl_scan_inc
	mov	bl, RotBitMask
	mov	bh, bptr gl_pen_pcol
	mov	cx, CurStyle
	mov	si, bp22
	push	bp
	call	dword ptr bp08
	pop	bp
	test	bp1A, 1h
	jz	pline_80
	mov	ax, wptr gl_bkColor + 1
	xchg	ax, wptr gl_bkColor
	mov	bptr gl_bkColor+2, al
	mov	ax, wptr gl_pen_pcol+1
	xchg	ax, wptr gl_pen_pcol
	mov	bptr gl_pen_pcol+2,al
	mov	dx, gl_width_planes
	add	wptr CurByte, dx
	rol	gl_planereg, 1	;Next plane
	jnc	pline_60
	shl	dx, 1
	sub	di, dx	
pline_80:
	mov	CurStyle, cx
pline_90:
	pop	si
	pop	ds
	cld
	lodsw
	mov	dx, ax
	lodsw
	mov	cx, ax
	pop	ax
	jmp	polyline_loop	
;
; Generate polyline code
;
cpolyline:
	lea	di, bpBC
	mov	cx, ss
	mov	es, cx
	mov	wptr bp08, di
	mov	wptr bp08+2, cx
	mov	cx, cs
	mov	ds, cx
	mov	si, offset X18FF
	mov	cx, 9
	rep	movsb
	cmp	bptr CurStyle+1, 0FFh
	jz	cpolyline_10
	mov	al, gl_bkMode
	cmp	al, 2
	jnz	cpolyline_10
	mov	si, offset X1908
	mov	cl, 4
	rep	movsw
	lea	si, gl_bkColor
	mov	es:[di-2], si
cpolyline_10:
	mov	bx,gl_rop
	test	bp1A, 80h
	jz	cpolyline_30
	test	cs:dm_flags[bx],1
	jz	cpolyline_30
	mov	al,bptr gl_bkColor+3
	and	al,cs:dm_pen_and[bx]
	xor	al,cs:dm_pen_xor[bx]
	mov	bptr gl_bkColor,al
	mov	al,bptr gl_pen_pcol+3
	and	al,cs:dm_pen_and[bx]
	xor	al,cs:dm_pen_xor[bx]
	mov	bptr gl_pen_pcol,al
	mov	ah, cs:dm_data_r[bx]
	mov	al, GRAF_DATA_ROT
	mov	dx, EGA_BASE + GRAF_ADDR
	mov	cs:ega_state_rot, ax	
	out	dx, ax
	mov	ax, M_COLOR_WRITE shl 8 + GRAF_MODE
	mov	cs:ega_state_mode, ax	
	out	dx, ax
	mov	bp1A, 80h
	mov	dl, SEQ_ADDR
	mov	ax, SEQ_MAP_MASK + 700h
	mov	cs:ega_state_mask, ax
	out	dx, ax
	mov	si, offset X1970
	mov	cx, 16h
	cmp	bptr CurStyle+1, 0FFh
	jz	cpolyline_20
	cmp	gl_bkMode, 2
	jz	cpolyline_20
	mov	si, offset X196C
	mov	cx, 1Ah
cpolyline_20:
	rep	movsb
	jmp	short cpolyline_50

cpolyline_30:
	mov	cl, cs:rop_lengths[bx]
	add	bx, bx
	mov	si, cs:rop_indexes[bx]
	rep	movsb
	mov	si, offset X1914
	mov	cl, 5
	cmp	bptr CurStyle+1, 0FFh
	jz	cpolyline_40
	cmp	al, 2
	jz	cpolyline_40
	mov	si, offset X1910
	mov	cl, 7
cpolyline_40:
	rep	movsw
cpolyline_50:
	mov	bp04, di
	ret
;
X1CEE:
	lea	ax, bpBC+5
	sub	ax, di
	cmp	bp1A, 80h
	jz	cpolyline_130
	mov	si, offset X1929
	mov	cx, 15h
	rep	movsb
	add	es:[di-0Fh], al
	add	es:[di-5], al
	test	bl, 2
	jz	cpolyline_110
	mov	bptr es:[di-14h], I_RET_NEAR
	mov	bptr es:[di-0Dh], 4Fh	;DEC
cpolyline_110:
	mov	ah, bl
	mov	bx, gl_rop
	mov	cl, cs:rop_lengths[bx]
	mov	al, cl
	add	bx, bx
	mov	si, cs:rop_indexes[bx]
	mov	bl, ah
	rep	movsb
	mov	si, offset X193E
	mov	cl, 9
	rep	movsb
	test	bl, 2
	jz	cpolyline_120
	mov	bptr es:[di-7], 4Fh	;DEC
cpolyline_120:
	sub	es:[di-2], al
	ret

cpolyline_130:
	mov	si, offset X1947
	mov	cx, 25h
	rep	movsb
	add	es:[di-1Fh], al
	add	es:[di-15h], al
	test	bl, 2
	jz	cpolyline_140
	mov	byte ptr es:[di-1Dh], 4Fh	;DEC
	mov	byte ptr es:[di-07h], 4Fh	;DEC
	mov	byte ptr es:[di-24h], I_RET_NEAR
cpolyline_140:
	ret
;
X1D6B:	mov	al, GRAF_BIT_MASK
	mov	dx, EGA_BASE + GRAF_ADDR
	cli	
	out	dx, ax
	mov	ah, [di]
	mov	[di], bh
	sti
	inc	di
	jcxz	X1D8A
	mov	ah, bl
	mov	cs:ega_state_graf, ax
	out	dx, ax
	mov	al, bh
X1D83:	cli	
	mov	ah, [di]
	stosb
	sti
	loop	X1D83
X1D8A:	mov	ax, si
	mov	al, GRAF_BIT_MASK
	cli
	out	dx, ax
	mov	ah, [di]
	mov	[di], bh
	sti
	retf
;
X1D96:	mov	dh, ah
	mov	dl, 1
X1D9A:	mov	ah, [di]
	mov	al, bh
X1D9E:	xor	al, ah
	and	al, dh
	xor	al, ah
	stosb
	or	dl, dl
	jnz	X1DAA
	retf
;
X1DAA:	mov	dx, si
	jcxz	X1D9A
X1DAE:	mov	ah, [di]
	mov	al, bh
X1DB2:	xor	al, ah
	and	al, bl
	xor	al, ah
	stosb
	loop	X1DAE
	jmp	short X1DAA
;
do_scanlines:
	test	bh, 80h
	jz	scanlines_10
	lds	bx, lp_points
	mov	dx, [bx].ycoord
	mov	di, dx
	mov	cx, [bx+4].xcoord
	mov	si, count
	dec	si
	jle	j_out_return_err
	shl	si, 1
	shl	si, 1
	mov	si, [bx+si].ycoord
	call	exclude
	mov	ax, DR_SET shl 8 + GRAF_DATA_ROT
	mov	cs:ega_state_rot, ax
	mov	cs:ega_state_mode, M_PROC_WRITE shl 8 + GRAF_MODE
	mov	byte ptr cs:ega_saved, 4
	call	ega_set_op
	mov	ax, 0FFh shl 8 + GRAF_BIT_MASK
	mov	cs:ega_state_graf, ax
	out	dx, ax
scanlines_10:
	mov	di, wptr lp_phys_brush
	mov	ax, wptr lp_phys_brush + 2
	mov	cx, ax
	or	cx, di
	mov	cl, 8
	jnz	scanlines_20
	lds	di, lp_phys_pen
	cmp	[di].oem_pen_style, LS_NOLINE
	jz	j_out_return
	mov	ax, wptr [di].oem_pen_pcol
	mov	dx, wptr [di].oem_pen_pcol + 2
	mov	ch, dh
	or	ch, 80h
	shl	dh, 1
	sar	dh, cl
	jmp	short scanlines_30

j_out_return_err:
	jmp	output_return_error

j_out_return:
	jmp	output_return
;
scanlines_20:
	lds	si, lp_points
	mov	bx, [si].ycoord
	and	bx, word ptr 7	
	mov	ds, ax
	mov	ax, [di].oem_brush_style
	cmp	ax, BS_PATTERN
	ja	j_out_return_err
	cmp	ax, BS_HOLLOW
	jz	j_out_return
	mov	ch, [di].oem_brush_accel
	mov	al, [bx+di]			;C0 plane
	mov	ah, [bx+di+SIZE_PATTERN]	;C1 plane
	mov	dl, [bx+di+2*SIZE_PATTERN]	;C2 plane
	mov	dh, [bx+di+3*SIZE_PATTERN]	;Mono plane
scanlines_30:
	mov	wptr gl_pen_pcol, ax
	mov	wptr gl_pen_pcol+2, dx
	mov	bp1E, ch
	mov	al, 0FFh
	cmp	gl_bkMode, 2
	jz	scanlines_50	
	test	bp1A, 1
	jz	scanlines_40
	mov	al, bptr gl_pen_pcol
	xor	al, bptr gl_bkColor
	xor	ah, bptr gl_bkColor+1
	xor	dl, bptr gl_bkColor+2
	or	al, ah
	or	al, dl
	jz	j_out_return
	jmp	short scanlines_50

scanlines_40:
	mov	al, bptr gl_bkColor+3
	shl	al, 1
	sar	al, cl
	xor	al, dh
	jz	j_out_return
scanlines_50:
	mov	bp1C, al
	mov	bx,gl_rop
	test	bp1A, 80h
	jz	scanlines_60
	test	bp1E, 80h
	jz	scanlines_60
	test	cs:dm_flags[bx], 1
	jz	scanlines_60
	mov	ax, offset X1D6B
	mov	wptr bp08, ax
	mov	wptr bp08+2, cs
	mov	al, bp1E
	and	al, cs:dm_pen_and[bx]
	xor	al, cs:dm_pen_xor[bx]
	mov	bptr gl_pen_pcol+3, al
	mov	ah, cs:dm_data_r[bx]
	mov	al, GRAF_DATA_ROT
	mov	dx, EGA_BASE + GRAF_ADDR
	mov	cs:ega_state_rot, ax
	out	dx, ax
	mov	ax, M_COLOR_WRITE shl 8 + GRAF_MODE
	mov	cs:ega_state_mode, ax
	out	dx, ax
	mov	bp1A, 80h
	mov	dl, SEQ_ADDR
	mov	ax, 700h + SEQ_MAP_MASK
	mov	cs:ega_state_mask, ax
	out	dx, ax
	jmp	short scanlines_70
;
scanlines_60:
	lea	di, [bp-0BEh]
	mov	cx, ss
	mov	es, cx
	mov	wptr bp08, di
	mov	wptr bp08+2, cx
	mov	cx, cs
	mov	ds, cx
	mov	cx, 8
	mov	si, offset X1D96
	rep	movsb
	mov	cl, cs:rop_lengths[bx]
	mov	ax, cx
	add	bx, bx
	mov	si, cs:rop_indexes[bx]
	rep	movsb
	mov	cx, 14h
	mov	si, offset X1D9E
	rep	movsb
	sub	es:[di-5], al
	mov	cx, ax
	mov	si, cs:rop_indexes[bx]
	rep	movsb
	mov	cx, 0Bh
	mov	si, offset X1DB2
	rep	movsb
	sub	es:[di-3], al
	sub	es:[di-1], al
scanlines_70:
	mov	ax, count
	lds	si, lp_points
	add	si, 4
scanlines_80:	
	dec	ax
	jg	scanlines_90
	jmp	output_ret1
;
scanlines_90:
	push	ax
	lodsw
	mov	bx, ax
	lodsw
	push	ds
	push	si
	mov	dx, ax
	sub	dx, bx
	jnz	scanlines_100
	jmp	scanlines_140
;
scanlines_100:
	dec	dx
	mov	di, bx
	shr	di, 1
	shr	di, 1
	shr	di, 1
	add	di, wptr CurByte
	mov	ds, wptr CurByte+2
	mov	es, wptr CurByte+2
	and	bx, word ptr 7
	mov	ch, cs:bitmask_tbl1[bx]
	add	bx, dx
	mov	dx, bx
	and	bx, word ptr 7
	mov	cl, cs:bitmask_tbl2[bx]
	shr	dx, 1	
	shr	dx, 1	
	shr	dx, 1
	jnz	scanlines_110
	and	ch, cl
	xor	cl, cl
	inc	dx
scanlines_110:
	dec	dx
	mov	bl, bp1C
	and	ch, bl
	and	cl, bl
	mov	ah, ch
	mov	ch, cl
	xor	cl, cl
	mov	si, cx
	mov	bh, bptr gl_pen_pcol+3
	mov	cx, dx
	mov	al, 21h
	test	bp1A, 1
	jnz	scanlines_120
	call	dword ptr bp08
	jmp	short scanlines_140
;
scanlines_120:
	push	di
	push	si
	push	ax
	push	bx
	push	cx
	push	ax
	mov	dx, gl_width_planes
	or	dx, dx
	jnz	scanlines_130
	mov	ah, al
	and	ah, 7
	mov	al, SEQ_MAP_MASK
	mov	dx, EGA_BASE + SEQ_ADDR
	mov	cs:ega_state_mask, ax
	out	dx, ax
	shr	ah, 1
	mov	al, GRAF_READ_MAP
	mov	dl, GRAF_ADDR
	out	dx, ax
	mov	al, ah
	shl	al, 1
scanlines_130:
	shr	al, 1
	and	ax, 3
	xchg	ax, si
	mov	bh, bptr gl_pen_pcol[si]
	mov	si, ax
	pop	ax
	call	dword ptr [bp-8]
	pop	cx
	pop	bx
	pop	ax
	pop	si
	pop	di
	add	di, gl_width_planes
	rol	al, 1
	jnc	scanlines_120
scanlines_140:
	pop	si
	pop	ds
	pop	ax
	jmp	scanlines_80





sEnd	Code

ifdef	PUBDEFS
	include output.pub
endif

end
