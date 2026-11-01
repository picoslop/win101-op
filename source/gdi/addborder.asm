;	Static Name Aliases
;
	TITLE   ADDBORDER.C
	NAME    ADDBORDER

	.8087
ADDBORDER_TEXT	SEGMENT  WORD PUBLIC 'CODE'
ADDBORDER_TEXT	ENDS
_DATA	SEGMENT  WORD PUBLIC 'DATA'
_DATA	ENDS
CONST	SEGMENT  WORD PUBLIC 'CONST'
CONST	ENDS
_BSS	SEGMENT  WORD PUBLIC 'BSS'
_BSS	ENDS
DGROUP	GROUP	CONST, _BSS, _DATA
	ASSUME  CS: ADDBORDER_TEXT, DS: DGROUP, SS: DGROUP
EXTRN	__acrtused:ABS
EXTRN	CREATENEWLIST:NEAR
ADDBORDER_TEXT      SEGMENT
	ASSUME	CS: ADDBORDER_TEXT
; Line 69
	PUBLIC	ADDBORDER
ADDBORDER	PROC NEAR
	push	bp
	mov	bp,sp
	sub	sp,58
	push	si
;	stride = 6
;	block = 4
;	a = -10
;	b = -12
;	i = -24
;	j = -42
;	tag = -44
;	x = -22
;	found = -48
;	c1 = -14
;	c2 = -16
;	tag1 = -46
;	tag2 = -50
;	x2 = -40
;	nsize = -38
;	node = -20
;	p = -4
;	q = -8
;	rec = -36
;	alist = 26
;	e1 = 22
;	n1 = 20
;	e2 = 16
;	n2 = 14
;	style = 12
;	pool = 8
; Line 83
	mov	WORD PTR [bp-24],0	;i
	jmp	$F149
$FC155:
	inc	WORD PTR [bp-42]	;j
$F154:
	mov	ax,WORD PTR [bp+14]	;n2
	cmp	WORD PTR [bp-42],ax	;j
	jb	$JCC24
	jmp	$FC150
$JCC24:
	cmp	WORD PTR [bp-48],0	;found
	je	$JCC33
	jmp	$FC150
$JCC33:
; Line 94
	mov	ax,6
	imul	WORD PTR [bp-42]	;j
	mov	si,ax
	les	bx,DWORD PTR [bp+16]	;e2
	mov	ax,WORD PTR [bp-44]	;tag
	cmp	es:[bx+4][si],ax
	jne	$FC155
; Line 95
	mov	WORD PTR [bp-48],1	;found
; Line 98
	mov	bx,ax
	shl	bx,1
	shl	bx,1
	les	si,DWORD PTR [bp+26]	;alist
	mov	ax,es:[bx][si]
	mov	dx,es:[bx+2][si]
	mov	WORD PTR [bp-20],ax	;node
	mov	WORD PTR [bp-18],dx
; Line 100
	les	bx,DWORD PTR [bp-20]	;node
	mov	ax,10
	imul	WORD PTR es:[bx+4]
	add	ax,bx
	mov	dx,es
	mov	WORD PTR [bp-4],ax	;p
	mov	WORD PTR [bp-2],dx
; Line 101
	mov	ax,WORD PTR [bp-22]	;x
	cwd	
	les	bx,DWORD PTR [bp-4]	;p
	mov	WORD PTR es:[bx],ax
	mov	WORD PTR es:[bx+2],dx
; Line 102
	les	bx,DWORD PTR [bp-4]	;p
	mov	ax,WORD PTR [bp+12]	;style
	mov	WORD PTR es:[bx+4],ax
; Line 104
	mov	ax,6
	imul	WORD PTR [bp-24]	;i
	add	ax,WORD PTR [bp+22]	;e1
	mov	dx,WORD PTR [bp+24]
	add	ax,4
	mov	WORD PTR [bp-54],ax
	mov	WORD PTR [bp-52],dx
	les	bx,DWORD PTR [bp-54]
	mov	ax,WORD PTR es:[bx]
	neg	ax
	mov	WORD PTR es:[bx],ax
; Line 105
	mov	ax,6
	imul	WORD PTR [bp-24]	;i
	add	ax,WORD PTR [bp+22]	;e1
	mov	dx,WORD PTR [bp+24]
	add	ax,4
	mov	WORD PTR [bp-58],ax
	mov	WORD PTR [bp-56],dx
	les	bx,DWORD PTR [bp-58]
	cmp	WORD PTR es:[bx],0
	jne	$I158
; Line 106
	mov	WORD PTR es:[bx],-32767
; Line 107
$I158:
	mov	ax,6
	imul	WORD PTR [bp-42]	;j
	add	ax,WORD PTR [bp+16]	;e2
	mov	dx,WORD PTR [bp+18]
	add	ax,4
	mov	WORD PTR [bp-58],ax
	mov	WORD PTR [bp-56],dx
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx]
	neg	ax
	mov	WORD PTR es:[bx],ax
; Line 108
	mov	ax,6
	imul	WORD PTR [bp-42]	;j
	add	ax,WORD PTR [bp+16]	;e2
	mov	dx,WORD PTR [bp+18]
	add	ax,4
	mov	WORD PTR [bp-54],ax
	mov	WORD PTR [bp-52],dx
	les	bx,DWORD PTR [bp-54]
	cmp	WORD PTR es:[bx],0
	je	$JCC256
	jmp	$FC155
$JCC256:
; Line 109
	mov	WORD PTR es:[bx],-32767
; Line 110
	jmp	$FC155
$FC150:
	inc	WORD PTR [bp-24]	;i
$F149:
	mov	ax,WORD PTR [bp+20]	;n1
	cmp	WORD PTR [bp-24],ax	;i
	jae	$FB151
; Line 84
	mov	ax,6
	imul	WORD PTR [bp-24]	;i
	add	ax,WORD PTR [bp+22]	;e1
	mov	dx,WORD PTR [bp+24]
	add	ax,4
	mov	WORD PTR [bp-54],ax
	mov	WORD PTR [bp-52],dx
	les	bx,DWORD PTR [bp-54]
	cmp	WORD PTR es:[bx],-32767
	jne	$I152
; Line 85
	mov	WORD PTR es:[bx],0
; Line 86
$I152:
	mov	ax,6
	imul	WORD PTR [bp-24]	;i
	add	ax,WORD PTR [bp+22]	;e1
	mov	dx,WORD PTR [bp+24]
	add	ax,4
	mov	WORD PTR [bp-54],ax
	mov	WORD PTR [bp-52],dx
	les	bx,DWORD PTR [bp-54]
	mov	si,WORD PTR es:[bx]
	or	si,si
	jge	$I153
; Line 87
	mov	ax,si
	neg	ax
	mov	WORD PTR es:[bx],ax
; Line 89
$I153:
	mov	ax,6
	imul	WORD PTR [bp-24]	;i
	add	ax,WORD PTR [bp+22]	;e1
	mov	dx,WORD PTR [bp+24]
	mov	WORD PTR [bp-54],ax
	mov	WORD PTR [bp-52],dx
	les	bx,DWORD PTR [bp-54]
	mov	ax,WORD PTR es:[bx+4]
	mov	WORD PTR [bp-44],ax	;tag
; Line 90
	mov	ax,WORD PTR es:[bx]
	mov	WORD PTR [bp-22],ax	;x
; Line 91
	mov	WORD PTR [bp-48],0	;found
; Line 93
	mov	WORD PTR [bp-42],0	;j
	jmp	$F154
$FB151:
; Line 118
	mov	WORD PTR [bp-10],0	;a
; Line 119
	mov	WORD PTR [bp-12],0	;b
; Line 120
$FC161:
; Line 121
	mov	ax,WORD PTR [bp+20]	;n1
	cmp	WORD PTR [bp-10],ax	;a
	jb	$L20000
	mov	ax,WORD PTR [bp+14]	;n2
	cmp	WORD PTR [bp-12],ax	;b
	jb	$L20000
; Line 122
	mov	ax,WORD PTR [bp+4]	;block
	jmp	$EX131
$FC165:
	mov	ax,6
	imul	WORD PTR [bp-10]	;a
	mov	si,ax
	les	bx,DWORD PTR [bp+22]	;e1
	cmp	WORD PTR es:[bx+4][si],0
	jge	$FB166
; Line 125
	inc	WORD PTR [bp-10]	;a
$L20000:
	mov	ax,WORD PTR [bp+20]	;n1
	cmp	WORD PTR [bp-10],ax	;a
	jb	$FC165
$FB166:
; Line 126
	mov	ax,WORD PTR [bp+20]	;n1
	cmp	WORD PTR [bp-10],ax	;a
	jne	$L20001
; Line 127
	mov	ax,6
	imul	WORD PTR [bp-10]	;a
	mov	bx,ax
	les	si,DWORD PTR [bp+22]	;e1
	mov	WORD PTR es:[bx][si],32767
; Line 128
	jmp	SHORT $L20001
$FC169:
	mov	ax,6
	imul	WORD PTR [bp-12]	;b
	mov	si,ax
	les	bx,DWORD PTR [bp+16]	;e2
	cmp	WORD PTR es:[bx+4][si],0
	jge	$FB170
; Line 129
	inc	WORD PTR [bp-12]	;b
$L20001:
	mov	ax,WORD PTR [bp+14]	;n2
	cmp	WORD PTR [bp-12],ax	;b
	jb	$FC169
$FB170:
; Line 130
	mov	ax,WORD PTR [bp+14]	;n2
	cmp	WORD PTR [bp-12],ax	;b
	jne	$I171
; Line 131
	mov	ax,6
	imul	WORD PTR [bp-12]	;b
	mov	bx,ax
	les	si,DWORD PTR [bp+16]	;e2
	mov	WORD PTR es:[bx][si],32767
; Line 133
$I171:
	mov	WORD PTR [bp-14],0	;c1
; Line 134
	mov	WORD PTR [bp-16],0	;c2
; Line 135
	mov	WORD PTR [bp-46],0	;tag1
; Line 136
	mov	WORD PTR [bp-50],0	;tag2
; Line 137
	mov	WORD PTR [bp-40],0	;x2
; Line 139
	mov	ax,WORD PTR [bp+20]	;n1
	cmp	WORD PTR [bp-10],ax	;a
	jb	$I172
	mov	ax,WORD PTR [bp+14]	;n2
	cmp	WORD PTR [bp-12],ax	;b
	jb	$JCC580
	jmp	$FC161
$JCC580:
; Line 140
$I172:
	mov	ax,6
	imul	WORD PTR [bp-12]	;b
	add	ax,WORD PTR [bp+16]	;e2
	mov	dx,WORD PTR [bp+18]
	mov	WORD PTR [bp-58],ax
	mov	WORD PTR [bp-56],dx
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx]
	mov	cx,ax
	mov	ax,6
	imul	WORD PTR [bp-10]	;a
	mov	bx,ax
	les	si,DWORD PTR [bp+22]	;e1
	cmp	es:[bx][si],cx
	jl	$I173
; Line 144
	mov	ax,WORD PTR [bp-14]	;c1
	add	ax,WORD PTR [bp-16]	;c2
	mov	cx,6
	imul	cx
	add	ax,bp
	mov	WORD PTR [bp-54],ax
	mov	WORD PTR [bp-52],ss
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx+4]
	les	bx,DWORD PTR [bp-54]
	mov	WORD PTR es:[bx-32],ax
; Line 145
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx]
	les	bx,DWORD PTR [bp-54]
	mov	WORD PTR es:[bx-36],ax
; Line 146
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx+4]
	mov	WORD PTR [bp-50],ax	;tag2
; Line 147
	mov	ax,WORD PTR es:[bx]
	mov	WORD PTR [bp-40],ax	;x2
; Line 148
	inc	WORD PTR [bp-12]	;b
; Line 149
	inc	WORD PTR [bp-16]	;c2
; Line 150
	jmp	SHORT $L20002
$I173:
; Line 151
	mov	ax,6
	imul	WORD PTR [bp-10]	;a
	add	ax,WORD PTR [bp+22]	;e1
	mov	dx,WORD PTR [bp+24]
	mov	WORD PTR [bp-58],ax
	mov	WORD PTR [bp-56],dx
	mov	ax,WORD PTR [bp-14]	;c1
	add	ax,WORD PTR [bp-16]	;c2
	mov	cx,6
	imul	cx
	add	ax,bp
	mov	WORD PTR [bp-54],ax
	mov	WORD PTR [bp-52],ss
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx+4]
	les	bx,DWORD PTR [bp-54]
	mov	WORD PTR es:[bx-32],ax
; Line 152
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx]
	les	bx,DWORD PTR [bp-54]
	mov	WORD PTR es:[bx-36],ax
; Line 153
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx+4]
	mov	WORD PTR [bp-46],ax	;tag1
; Line 154
	inc	WORD PTR [bp-10]	;a
; Line 155
	inc	WORD PTR [bp-14]	;c1
; Line 156
; Line 159
	jmp	SHORT $L20002
$FC176:
	mov	ax,6
	imul	WORD PTR [bp-10]	;a
	mov	si,ax
	les	bx,DWORD PTR [bp+22]	;e1
	cmp	WORD PTR es:[bx+4][si],0
	jge	$FB177
; Line 160
	inc	WORD PTR [bp-10]	;a
$L20002:
	mov	ax,WORD PTR [bp+20]	;n1
	cmp	WORD PTR [bp-10],ax	;a
	jb	$FC176
$FB177:
; Line 161
	mov	ax,WORD PTR [bp+20]	;n1
	cmp	WORD PTR [bp-10],ax	;a
	jne	$L20003
; Line 162
	mov	ax,6
	imul	WORD PTR [bp-10]	;a
	mov	bx,ax
	les	si,DWORD PTR [bp+22]	;e1
	mov	WORD PTR es:[bx][si],32767
; Line 163
	jmp	SHORT $L20003
$FC180:
	mov	ax,6
	imul	WORD PTR [bp-12]	;b
	mov	si,ax
	les	bx,DWORD PTR [bp+16]	;e2
	cmp	WORD PTR es:[bx+4][si],0
	jge	$FB181
; Line 164
	inc	WORD PTR [bp-12]	;b
$L20003:
	mov	ax,WORD PTR [bp+14]	;n2
	cmp	WORD PTR [bp-12],ax	;b
	jb	$FC180
$FB181:
; Line 165
	mov	ax,WORD PTR [bp+14]	;n2
	cmp	WORD PTR [bp-12],ax	;b
	jne	$I182
; Line 166
	mov	ax,6
	imul	WORD PTR [bp-12]	;b
	mov	bx,ax
	les	si,DWORD PTR [bp+16]	;e2
	mov	WORD PTR es:[bx][si],32767
; Line 168
$I182:
	mov	ax,6
	imul	WORD PTR [bp-12]	;b
	add	ax,WORD PTR [bp+16]	;e2
	mov	dx,WORD PTR [bp+18]
	mov	WORD PTR [bp-58],ax
	mov	WORD PTR [bp-56],dx
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx]
	mov	cx,ax
	mov	ax,6
	imul	WORD PTR [bp-10]	;a
	mov	bx,ax
	les	si,DWORD PTR [bp+22]	;e1
	cmp	es:[bx][si],cx
	jl	$I183
; Line 169
	mov	ax,WORD PTR [bp-14]	;c1
	add	ax,WORD PTR [bp-16]	;c2
	mov	cx,6
	imul	cx
	add	ax,bp
	mov	WORD PTR [bp-54],ax
	mov	WORD PTR [bp-52],ss
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx+4]
	les	bx,DWORD PTR [bp-54]
	mov	WORD PTR es:[bx-32],ax
; Line 170
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx]
	les	bx,DWORD PTR [bp-54]
	mov	WORD PTR es:[bx-36],ax
; Line 171
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx+4]
	mov	WORD PTR [bp-50],ax	;tag2
; Line 172
	mov	ax,WORD PTR es:[bx]
	mov	WORD PTR [bp-40],ax	;x2
; Line 173
	inc	WORD PTR [bp-12]	;b
; Line 174
	inc	WORD PTR [bp-16]	;c2
; Line 175
	jmp	SHORT $I184
$I183:
; Line 176
	mov	ax,6
	imul	WORD PTR [bp-10]	;a
	add	ax,WORD PTR [bp+22]	;e1
	mov	dx,WORD PTR [bp+24]
	mov	WORD PTR [bp-58],ax
	mov	WORD PTR [bp-56],dx
	mov	ax,WORD PTR [bp-14]	;c1
	add	ax,WORD PTR [bp-16]	;c2
	mov	cx,6
	imul	cx
	add	ax,bp
	mov	WORD PTR [bp-54],ax
	mov	WORD PTR [bp-52],ss
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx+4]
	les	bx,DWORD PTR [bp-54]
	mov	WORD PTR es:[bx-32],ax
; Line 177
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx]
	les	bx,DWORD PTR [bp-54]
	mov	WORD PTR es:[bx-36],ax
; Line 178
	les	bx,DWORD PTR [bp-58]
	mov	ax,WORD PTR es:[bx+4]
	mov	WORD PTR [bp-46],ax	;tag1
; Line 179
	inc	WORD PTR [bp-10]	;a
; Line 180
	inc	WORD PTR [bp-14]	;c1
; Line 181
$I184:
; Line 183
	cmp	WORD PTR [bp-14],2	;c1
	jne	$I185
; Line 185
	mov	bx,WORD PTR [bp-32]
	shl	bx,1
	shl	bx,1
	les	si,DWORD PTR [bp+26]	;alist
	mov	ax,es:[bx][si]
	mov	dx,es:[bx+2][si]
	mov	WORD PTR [bp-4],ax	;p
	mov	WORD PTR [bp-2],dx
; Line 186
	mov	bx,WORD PTR [bp-26]
	shl	bx,1
	shl	bx,1
	mov	ax,es:[bx][si]
	mov	dx,es:[bx+2][si]
	mov	WORD PTR [bp-8],ax	;q
	mov	WORD PTR [bp-6],dx
; Line 187
	les	bx,DWORD PTR [bp-4]	;p
	mov	WORD PTR es:[bx+6],ax
	mov	WORD PTR es:[bx+8],dx
; Line 188
	les	bx,DWORD PTR [bp-8]	;q
	mov	ax,WORD PTR [bp-4]	;p
	mov	dx,WORD PTR [bp-2]
	mov	WORD PTR es:[bx+6],ax
	mov	WORD PTR es:[bx+8],dx
; Line 189
	jmp	$FC161
$I185:
	cmp	WORD PTR [bp-16],2	;c2
	je	$JCC1163
	jmp	$I187
$JCC1163:
; Line 193
	mov	ax,WORD PTR [bp+4]	;block
	imul	WORD PTR [bp+6]	;stride
	mov	cx,10
	imul	cx
	add	ax,WORD PTR [bp+8]	;pool
	mov	dx,WORD PTR [bp+10]
	mov	WORD PTR [bp-4],ax	;p
	mov	WORD PTR [bp-2],dx
; Line 194
	push	WORD PTR [bp-32]
	push	WORD PTR [bp-36]	;rec
	push	WORD PTR [bp+12]	;style
	push	dx
	push	ax
	call	CREATENEWLIST
; Line 196
	mov	ax,10
	imul	WORD PTR [bp+6]	;stride
	mov	WORD PTR [bp-38],ax	;nsize
; Line 197
	les	bx,DWORD PTR [bp-4]	;p
	add	ax,bx
	mov	dx,es
	mov	WORD PTR es:[bx],ax
	mov	WORD PTR es:[bx+2],dx
; Line 198
	mov	bx,WORD PTR [bp-32]
	shl	bx,1
	shl	bx,1
	les	si,DWORD PTR [bp+26]	;alist
	mov	ax,WORD PTR [bp-4]	;p
	mov	dx,WORD PTR [bp-2]
	mov	es:[bx][si],ax
	mov	es:[bx+2][si],dx
; Line 200
	mov	ax,WORD PTR [bp-38]	;nsize
	add	ax,WORD PTR [bp-4]	;p
	mov	dx,WORD PTR [bp-2]
	mov	WORD PTR [bp-8],ax	;q
	mov	WORD PTR [bp-6],dx
; Line 201
	push	WORD PTR [bp-26]
	push	WORD PTR [bp-30]
	push	WORD PTR [bp+12]	;style
	push	dx
	push	ax
	call	CREATENEWLIST
; Line 202
	les	bx,DWORD PTR [bp-8]	;q
	mov	ax,WORD PTR [bp-4]	;p
	mov	dx,WORD PTR [bp-2]
	mov	WORD PTR es:[bx],ax
	mov	WORD PTR es:[bx+2],dx
; Line 203
	mov	bx,WORD PTR [bp-26]
	shl	bx,1
	shl	bx,1
	les	si,DWORD PTR [bp+26]	;alist
	mov	ax,WORD PTR [bp-8]	;q
	mov	dx,WORD PTR [bp-6]
	mov	es:[bx][si],ax
	mov	es:[bx+2][si],dx
; Line 205
	add	WORD PTR [bp+4],2	;block
; Line 206
	jmp	$FC161
$I187:
; Line 209
	mov	bx,WORD PTR [bp-46]	;tag1
	shl	bx,1
	shl	bx,1
	les	si,DWORD PTR [bp+26]	;alist
	mov	ax,es:[bx][si]
	mov	dx,es:[bx+2][si]
	mov	WORD PTR [bp-20],ax	;node
	mov	WORD PTR [bp-18],dx
; Line 211
	les	bx,DWORD PTR [bp-20]	;node
	mov	ax,10
	imul	WORD PTR es:[bx+4]
	add	ax,bx
	mov	dx,es
	mov	WORD PTR [bp-4],ax	;p
	mov	WORD PTR [bp-2],dx
; Line 212
	mov	ax,WORD PTR [bp-50]	;tag2
	cwd	
	les	bx,DWORD PTR [bp-4]	;p
	mov	WORD PTR es:[bx+6],ax
	mov	WORD PTR es:[bx+8],dx
; Line 213
	les	bx,DWORD PTR [bp-20]	;node
	add	WORD PTR es:[bx+4],2
; Line 215
	mov	ax,WORD PTR [bp-4]	;p
	mov	dx,WORD PTR [bp-2]
	add	ax,10
	mov	WORD PTR [bp-4],ax	;p
; Line 216
	mov	ax,WORD PTR [bp-40]	;x2
	cwd	
	les	bx,DWORD PTR [bp-4]	;p
	mov	WORD PTR es:[bx],ax
	mov	WORD PTR es:[bx+2],dx
; Line 217
	les	bx,DWORD PTR [bp-4]	;p
	mov	ax,WORD PTR [bp+12]	;style
	mov	WORD PTR es:[bx+4],ax
; Line 219
	mov	ax,WORD PTR [bp-4]	;p
	mov	dx,WORD PTR [bp-2]
	add	ax,10
	mov	WORD PTR [bp-4],ax	;p
; Line 220
	mov	ax,WORD PTR [bp-40]	;x2
	cwd	
	les	bx,DWORD PTR [bp-4]	;p
	mov	WORD PTR es:[bx],ax
	mov	WORD PTR es:[bx+2],dx
; Line 221
	les	bx,DWORD PTR [bp-4]	;p
	mov	ax,WORD PTR [bp+12]	;style
	mov	WORD PTR es:[bx+4],ax
; Line 223
	mov	bx,WORD PTR [bp-50]	;tag2
	shl	bx,1
	shl	bx,1
	les	si,DWORD PTR [bp+26]	;alist
	mov	ax,WORD PTR [bp-20]	;node
	mov	dx,WORD PTR [bp-18]
	mov	es:[bx][si],ax
	mov	es:[bx+2][si],dx
; Line 224
; Line 225
	jmp	$FC161
$EX131:
	pop	si
	mov	sp,bp
	pop	bp
	ret	26

ADDBORDER	ENDP
	nop	
ADDBORDER_TEXT	ENDS
END
