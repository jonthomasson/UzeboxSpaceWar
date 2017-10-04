/*
 *  Uzebox Kernel - Mode 6
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 *  Uzebox is a reserved trade mark
*/
;***************************************************
; Video Mode 6 Cunning Fellows Modifications
; 256x224
; Monochrome
; Use Ram tiles 256
;***************************************************	

.global DisplayLogo
.global VideoModeVsync
.global InitializeVideoMode
.global ClearBuffer
.global ClearBufferLastLine
.global ClearBufferLastLineTileOnly
.global SetBackgroundColor
.global SetForegroundColor
.global SetHsyncCallback
.global OutCharXYFastC
.global GetRamTileFastC
.global SetPixelFastC
.global bresh_line_asm
.global DefaultCallback
.global mycallback
.global OutHex8XYFastC
.global OutDec8XYFastC
.global	OutStringXYProgmemFastC
.global nextFreeRamTile
.global renderCount
.global	ClearVramFlags
.global StatusTiles

.section .bss
.align 3								; NOTE. .p2align <#bits> or .balign <bytes> is prefered
	shift_tbl_ram:			.space 8	; Fast lookup table for 0x80, 0x40,...0x02,0x01
.align 0
	nextFreeRamTile:		.byte 1
	fg_color:				.byte 1		; Foreground Colour
	renderCount:			.byte 1		; Number of frames rendered since clear
	ClearVramFlags:			.byte 1		; Flags to indicate type of clear to do 
											; b0 = Clear This Frame  1=Y 				0=N
											; b1 = Clear Type		 1=ramTileOnly 		0=vram&RamTile
	StatusTiles:			.space 11

.align 1
	hsync_user_callback:  	.word 1 	; pointer to function
	

.section .text

sub_video_mode6:					; At this point R0..R29 have all been saved to the stack
									; So all can be trashed.

	lds 	r16,render_lines_count	; total scanlines to draw
	andi	r16, 0b11111000			; must be multiple of 8 (because of my updated "clear while render"
	mov		r10, r16				; routines


	ldi		r17, (28*8)
	sub		r17, r16			;

	ldi		r16, 0x04				; 32x = already x8 because pixel rather than CHAR x4 here
	mul		r17, r16

	movw	r28, r0
	subi	r29, hi8(-(vram))			; Add VRAM offset


//	ldi 	YL,lo8(vram)			; Get the base address of the VRAM
//	ldi 	YH,hi8(vram)			; for the first row of CHARs to render



	clr 	r22						; Line within Char is 0 of 7

	movw	r14, YL					; Copy address of VRAM into R14:15 


	clr		r5						; CF.. Use R5 as ZERO during these bits
	lds		r4, ClearVramFlags		

	sbrc	r4, 0					; Test Bit0 of ClearVRAMFlags and is SET
	rjmp	clear_this_frame		; We need to clear VRAM

dont_clear_this_frame:				; Otherwise don't clear VRAM
	lds		r21, renderCount		
	inc		r21						; INC the variable keeping a copy of how many frames
	sts		renderCount, r21		; since last clear happened.

	ldi		r21, 0xFF				; How Many Rows to wait before clearing VRAM 0xFF = never
	rjmp	clear_this_frame_common

clear_this_frame:
	sts		renderCount, r5
	ldi		r21, 0x07				; How Many Rows to wait before clearing VRAM 0x07 = normal

	rjmp	.
	rjmp	.

clear_this_frame_common:
	WAIT r19,1327					; waste cycles to align with next
									; hsync that is first rendered line


next_text_line:	
	rcall hsync_pulse 

	lds ZL,hsync_user_callback+0	; process user hsync callback
	lds ZH,hsync_user_callback+1
	icall							; callback must take exactly 32 cycles

	WAIT r19,213 - AUDIO_OUT_HSYNC_CYCLES


; This bit draws the status info in the top left corner EVERY frame
;
; PPPPP
; LLL
; WWW
;
; where P is 5 chars for Points
;       L is 3 chars for Lives
;       W is 3 chars for Wave/Level
;
; These chars are stored as 11 bytes in RAM and are permanently allocated 11 ramTiles (0x01..0x11)
;

Draw_Score_Lives_Level:
	ldi		r19, 0x0C						; If we have made it to the 12th last render line
	cp		r10, r19
	brlo	Draw_Score_Lives_Level_Start	; then we can start drawing the status chars


	WAIT r19,74								; Other wise waste some time and go to the next bit
	rjmp	Draw_Score_Lives_Level_Skip

Draw_Score_Lives_Level_Start:


	mov		r30, r10						; Get a copy of the Status# to print (11..1)
	dec		r30								; subract one from it as we actually want (10..0)

	clr		r31
	subi	r30, lo8(-(StatusTiles))		; Add the base address of the table in ram
	sbci	r31, hi8(-(StatusTiles))		; holding the CHAR to print.
	ld		r19, Z							; and read the CHAR we are going to print

	ldi		r17, 0x08
	mul		r19, r17						; Multiply the Char_Number *8
											; and leave in R0:1

	mov		r30, r10							; Get a copy of the Status# to print again
	dec		r30									; subract one from it as we actually want (10..0)
	clr		r31
	subi	r30, lo8(-(StatusPositionTable))	; add to the BASE address in flash of the 
	sbci	r31, hi8(-(StatusPositionTable))	; position table

	lpm		r26, Z							; Read the lower byte of the VRAM address from
	ldi		r27, hi8(vram)					; the position table and LDI the upper address byte

	mov		r19, r10						; Get Status# again
	st		X, r19							; save the tile# to VRAM

	movw	r30, r0							; Move the result of (CHAR*8) to the Z_Register
	subi 	r30, lo8(-(FontTable))			; Add the offset to the FontTable[] array to Z_Register
    sbci 	r31, hi8(-(FontTable))			; 		(Must be 16 bit add as FontTable is not aligned)

	mul		r19, r17						; Multiple the ramTile# *8
	movw	r26, r0							; move the resutl of ramTile*8 to X
	ldi		r27, hi8(ramTiles)				; Add the offset of the ramTiles


	lpm		r19, Z+							; Copy the 8 bytes of FONT data to ramTile space
	st		X+, r19
	lpm		r19, Z+
	st		X+, r19
	lpm		r19, Z+
	st		X+, r19
	lpm		r19, Z+
	st		X+, r19
	lpm		r19, Z+
	st		X+, r19
	lpm		r19, Z+
	st		X+, r19
	lpm		r19, Z+
	st		X+, r19
	lpm		r19, Z+
	st		X+, r19

	rjmp	.			; 5 nops
	rjmp	.
	rjmp	.

Draw_Score_Lives_Level_Skip:

	call render_tile_line_hires 	; render_tile_line
	

	cpi	 r21, 0x00					; See if we have already skipped the first 7 lines
	breq  clear_vram_this_line

	dec	r21

	WAIT r19,133					; Extra Cycles becuase 256 pixels	

	rjmp	clear_vram_com_end

clear_vram_this_line:

	movw	r30, r14				; Move the VRAM Clear Address Counter into Z
	ld		r16, Z					; Get the # of the tile pointed to

	clr		r3						; ZERO out a temp reg
	sbrc	r4, 1					; test to see if we should be clearing VRAM
	mov		r3, r16					; if we are NOT clearing VRAM then UN-ZERO R3 with the current tile

	st		Z+, r3					; Store R3 to the VRAM address
	movw	r14, r30				; Save VRAM address counter as render_line trashes Z

	ldi		r17, 0x08				; Multiply the Tile# by 8 to get the ram location - 0x0800
	mul		r16,r17

	movw	r30, r0					; Move the 16 bit value into Z and add 0x0400 to it
	subi	r31, hi8(-(ramTiles))	; to get the actual RAM address of the first byte of tile

	st		Z+, r5					; Clear 8 consecutive bytes
	st		Z+, r5
	st		Z+, r5
	st		Z+, r5
	st		Z+, r5
	st		Z+, r5
	st		Z+, r5
	st		Z+, r5

	mov		r17, r14
	andi	r17, 0b00000011
	brne	clear_vram_this_line

clear_vram_com_end:
 	dec r10							; Check to see if all lines rendered
	breq text_frame_end
	
	inc r22

	cpi r22,8 						; if 8 rows have been rendered 
	breq next_text_row 				; then we are on a new char row
	
									; Make sure this path take same number
									; of clocks as next_text_row path
	lpm ;3 nop
	lpm ;3 nop
	lpm ;3 nop
	nop

	rjmp next_text_line	

next_text_row:
	clr r22							; Reset Line within Char counter to 0

	clr r0							; Get the base address of the VRAM
	ldi r19,VRAM_TILES_H			; for the NEXT row of CHARs to render
	add YL,r19
	adc YH,r0

	lpm
	nop

	rjmp next_text_line

text_frame_end:

	WAIT r19,17

	rcall hsync_pulse ;145
	
text_end2:

	;set vsync flag & flip field
	lds ZL,sync_flags
	ldi r20,SYNC_FLAG_FIELD
	ori ZL,SYNC_FLAG_VSYNC
	eor ZL,r20
	sts sync_flags,ZL

	;clear any pending timer int
	ldi ZL,(1<<OCF1A)
	sts _SFR_MEM_ADDR(TIFR1),ZL

	ret

;*************************************************
; RENDER TILE LINE
;
; r10     = render_lines_count
; r22     = Y offset in tiles
; Y       = VRAM adress to draw from (must not be modified)
;
; Must preserve: r10,r22,Y
; 
; cycles  = 1495
;*************************************************


//high resolution
render_tile_line_hires:

	movw XL,YL						; Save Y (Y pointer R28:R29)

	ldi r23,8						; Bytes per tile for the MUL

	clr r0
	ldi r24,lo8(ramTiles)			; Get the base address of the RAM Tiles
	ldi r25,hi8(ramTiles)
	add r24,r22						; add Line within Char offset
	adc r25,r0

	;load the first 8 pixels

	ld	r20,X+						; load TILE from VRAM
	mul r20,r23						; Multiply loaded TILE value by 8
	movw ZL,r24						; Copy address of BASE+Line_within_Char to Z
	add ZL,r0						; Add TILE*8 to BASE+Line_within_Char
	adc ZH,r1
	ld r17,Z						; Load the 8 pixels into r17

	ldi r18,SCREEN_TILES_H			; Load TILE_PER_LINE_COUNTER

	rjmp .							; Waste 4 clock cycles
	rjmp .

1:

; For each Pixel 0..7 
;
; rol r1{7|9} = rotate the next pixel into CARRY
; sbc r2,r2   = subtract r2 from itself with carry.
;               r2-r2       always = 0x00
;               r2-r2-CARRY        = 0x00 if carry = 0
;               r2-r2-CARRY        = 0xFF if carry = 1
;
; as DDRC has been loaded with the foreground colour
; loading 0x00 or 0xFF into PORT switches between BLACK and foreground
;
; finally 2 clocks EACH pixel (16 clocks total) to get the NEXT 8 pixels

									; Pixel 0
	rol r17							
	sbc r2,r2						
	out _SFR_IO_ADDR(DATA_PORT),r2	
	ld r16,X+						; load next TILE from VRAM into R16


									; Pixel 1
	rol r17
	sbc r2,r2
	out _SFR_IO_ADDR(DATA_PORT),r2
	mul r16,23						; Multiply loaded TILE value by 8

									; Pixel 2
	rol r17
	sbc r2,r2
	out _SFR_IO_ADDR(DATA_PORT),r2
	add r0,r24						; Add TILE*8 to BASE+Line_within_Char
	adc r1,r25						; leaving result in R0:R1

									; Pixel 3
	rol r17
	sbc r2,r2
	out _SFR_IO_ADDR(DATA_PORT),r2
	movw ZL,r0						; Move result to Z
	mov r19,r17						; shuffle current pixel into r19

									; Pixel 4
	rol r19							; {Using R19 for last 3 pixels)
	sbc r2,r2
	out _SFR_IO_ADDR(DATA_PORT),r2
	ld r17,Z						; load next 8 pixels into R17

									; Pixel 5
	rol r19
	sbc r2,r2
	out _SFR_IO_ADDR(DATA_PORT),r2
	rjmp .							; 2 cycle NOP

									; Pixel 6
	rol r19
	sbc r2,r2
	out _SFR_IO_ADDR(DATA_PORT),r2
	nop								; only one NOP here as Pixel 7 has the Dec R18

									; Pixel 7
	rol r19
	sbc r2,r2
	dec r18							; Dec the TILE_PER_LINE_COUNTER
	out _SFR_IO_ADDR(DATA_PORT),r2
	brne 1b							; If line not finished go back

	lpm 							; 2 cycle NOP
	clr r0
	out _SFR_IO_ADDR(DATA_PORT),r0	; Colour out = black after visable region.


	ret


; void ClearBuffer(void)
;
; Clears the video buffer and the ramTiles
; This is a dumb routine that clears all 1920 ram locations regardless
; It is only called once during "init" so does not need to be smart.
; Normal clearing of VRAM / ramTiles is done during render to save time
;
; Inputs
;		void
;
; Returns 
;		void
;
; Modified RAM
;		clears entire contents of ramTiles and VRAM to ZERO
;		nextFreeRamTile = 12 (1 for <ZERO> and 11 more for score/lives/level
;
; Trashed
;		R24
;		R26:27

ClearBuffer:

	ldi 	XL,lo8(ramTiles)		; Get base address of ramTiles
	ldi 	XH,hi8(ramTiles)
	ldi		r24, 0xB8				; there are 0xB8 (184) * 16 = 2944 bytes of ramTile + VRAM to clear

ClearBufferLoop:
	st		X+, r1					; clear 16 bytes
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1
	st		X+, r1

	dec		r24						; if 1920 have not been cleared yet then keep going
	brne	ClearBufferLoop

	ldi 	r24,12					; set the first free ramTile as 1 (tile 0 = blank)
	sts 	nextFreeRamTile,r24
	ret



; void ClearBufferLastLine(void)
;
; Clears the last line of the video buffer
; The first 23 lines of VRAM and all the ramTile they point to get
; cleared during screen render.
;
; The 28th line of the VRAM must be cleared seperately
;
; Inputs
;		void
;
; Returns 
;		void
;
; Modified RAM
;		clears the last 32 bytes of VRAM to ZERO
;		clears any ramTiles pointed to by last 32 bytes of VRAM to ZERO
;		nextFreeRamTile = 12 (1 for <ZERO> and 11 more for score/lives/level
;
; Trashed
;		R0
;		R1
;		R23
;		R24
;		R26:27
;		R30:31

ClearBufferLastLine:

	ldi 	XL, 0x60							; Get the address of the last line of the VRAM
	ldi 	XH, 0x0F
	ldi		r23, 0x08							; We have to (ramTile# * 8) + 0x0800 to get ramTile address

ClearBufferLastLineLoop:
	
	ld		r24, X								; get the ramTile# at location n
	st		X+, r1								; erase location n

	cp		r24, r1								; if location n was ramTile# 0 then we don't
	breq	ClearBufferLastLineNoRamTile		; need to clear that tile


	mul		r24,r23								; (ramTile# * 8) + 0x0400
	movw	ZL, r0
	clr		r1
	subi	r31, hi8(-(ramTiles))
	
	st 		Z+,r1								; clear all 8 bytes of the ramTile
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	
ClearBufferLastLineNoRamTile:
	cpi		XL, 0x80							; Check to see if we are at location 0x0F80
	brne	ClearBufferLastLineLoop				; if we are not we still have more work to do

	ldi 	r24,12								; Reset nextFreeRamTile to 1
	sts 	nextFreeRamTile,r24
	ret

; void ClearBufferLastLineTileOnly(void)
;
; Clears the last lines worth of ramtiles in the video buffer
; The first 23 lines of ramTiles pointed to by VRAM are
; cleared during screen render.
;
; The 28th line must be cleared seperately
;
; DOES NOT change the value of "NextFreeRamTile"
;
; Inputs
;		void
;
; Returns 
;		void
;
; Modified RAM
;		clears any ramTiles pointed to by last 32 bytes of VRAM to ZERO
;
; Trashed
;		R0
;		R1
;		R23
;		R24
;		R26:27
;		R30:31

ClearBufferLastLineTileOnly:

	ldi 	XL, 0x60							; Get the address of the last line of the VRAM
	ldi 	XH, 0x0F
	ldi		r23, 0x08							; We have to (ramTile# * 8) + 0x0800 to get ramTile address

ClearBufferLastLineTileOnlyLoop:
	
	ld		r24, X+								; get the ramTile# at location n

	cp		r24, r1								; if location n was ramTile# 0 then we don't
	breq	ClearBufferLastLineTileOnlyNoRamTile		; need to clear that tile

	mul		r24,r23								; (ramTile# * 8) + 0x0400
	movw	ZL, r0
	clr		r1
	subi	r31, hi8(-(ramTiles))
	
	st 		Z+,r1								; clear all 8 bytes of the ramTile
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	st 		Z+,r1
	
ClearBufferLastLineTileOnlyNoRamTile:
	cpi		XL, 0x80							; Check to see if we are at location 0x0F80
	brne	ClearBufferLastLineTileOnlyLoop		; if we are not we still have more work to do

	ret


;Nothing to do in this mode
DisplayLogo:
VideoModeVsync:
	ret


InitializeVideoMode:

	ldi 	r24,lo8(pm(DefaultCallback))		; Point HSyncCallBack to something so it does not jump
	sts 	hsync_user_callback+0,r24			; to somewhere undefined before a user callback is set
	ldi 	r24,hi8(pm(DefaultCallback))
	sts 	hsync_user_callback+1,r24

	rcall	ClearBuffer							; Clear the VRAM and tile ram and set nextFreeRamTile to 12

	ldi 	r24,0xff							; Set the foreground colour to white
	sts 	fg_color,r24

	ldi 	XL,lo8(shift_tbl_ram)				; Make a shift table in RAM 
	ldi 	XH,hi8(shift_tbl_ram)
	ldi 	r24,0b10000000
init_ram_table_loop:
	st 		X+,r24
	lsr 	r24
	brcc 	init_ram_table_loop


	ldi 	ZL,lo8(SinCosTable)
	ldi 	ZH,hi8(SinCosTable)

	ldi 	XL,lo8(trigtable)
	ldi 	XH,hi8(trigtable)

	ldi		r24, 0x00

init_sin_table_loop:
	lpm		r25, Z+
	st		X+, 25
	
	dec		r24
	brne	init_sin_table_loop

	ret


.section .text.SetForegroundColor
SetForegroundColor:
	sts 	fg_color,r24
	ret

;****************************
; Sets a callback that will be invoked during HBLANK 
; before rendering each line.
; C callable
; r25:r24 - pointer to C function: void ptr*(void)
;****************************
.section .text.SetHsyncCallback
SetHsyncCallback:
	sts 	hsync_user_callback+0,r24
	sts 	hsync_user_callback+1,r25
	ret

;must take exactly 32 cycles including the ret
DefaultCallback:

	WAIT r24,28
	ret


;C-callable
;must take exactly 32 cycles including the ret
mycallback:

	ldi		r24, 0xFF				; Set the ForeGround colour to White
	out 	_SFR_IO_ADDR(DDRC),r24	; On every single line
	WAIT r24,26
	ret


OutStringXYProgmemFastC:

	movw	r30, r20
OutStringXYProgmemFastCLoop:
	lpm		r20, Z+
	tst		r20
	breq	OutStringXYProgmemFastCEnd
	movw	r18, r30
	rcall	OutCharXYFastC		; Put the low nibble to the screen
	movw	r30, r18
	inc		r24
	rjmp	OutStringXYProgmemFastCLoop
OutStringXYProgmemFastCEnd:
	ret

.global LineMode7FastC
LineMode7FastC:
	cp		r22, r18
	breq	LineMode7FastC_HLine

	ldi		r23, 0x04		
	mul		r22, r23		; Mul y0 x4
	
	movw	r30, r0

	subi	r30, lo8(-(Mode7LookupTable))
	sbci	r31, hi8(-(Mode7LookupTable))

	lpm		r22, Z+		// New y0
	lpm		r26, Z+		// X Off
	lpm		r27, Z+		// X MUL

	mul		r24, r27
	mov		r24, r1
	add		r24, r26

	mul		r18, r23		; Mul y0 x4
	
	movw	r30, r0

	subi	r30, lo8(-(Mode7LookupTable))
	sbci	r31, hi8(-(Mode7LookupTable))

	lpm		r18, Z+		// New y0
	lpm		r26, Z+		// X Off
	lpm		r27, Z+		// X MUL

	mul		r20, r27
	mov		r20, r1
	add		r20, r26

	rjmp 	bresh_line_asm

LineMode7FastC_HLine:

	ldi		r23, 0x04		
	mul		r22, r23		; Mul y0 x4
	
	movw	r30, r0

	subi	r30, lo8(-(Mode7LookupTable))
	sbci	r31, hi8(-(Mode7LookupTable))

	lpm		r22, Z+		// New y0
	mov		r18, r22	// Copy into Y2 as is the same

	lpm		r26, Z+		// X Off
	lpm		r27, Z+		// X MUL

	mul		r24, r27
	mov		r24, r1
	add		r24, r26


	mul		r20, r27
	mov		r20, r1
	add		r20, r26

	rjmp 	bresh_line_asm


; void OutDec8XYFastC(uint8_t, x_char, uint8_t y_char; uint8_t dec_num)
;
; Prints an 8 bit decimal value to the screen (3 chars long right aligned no zero padding)
;
; Inputs
; 		x_char in R24
; 		y_char in R22
;		hex_num in R20
; Returns 
;		void

OutDec8XYFastC:

	ldi		r23, 0x04
	mul		r20, r23
	movw	r30, r0
	subi 	r30, lo8(-(Bin2AscTable))		; Add the offset to the FontTable[] array to Z_Register
    sbci 	r31, hi8(-(Bin2AscTable))		; (Must be 16 bit add as FontTable is not aligned)

	lpm		r20, Z+
	movw	r18, r30
	rcall	OutCharXYFastC		; Put the low nibble to the screen

	movw	r30, r18
	lpm		r20, Z+
	movw	r18, r30
	inc		r24
	rcall	OutCharXYFastC		; Put the low nibble to the screen

	movw	r30, r18
	lpm		r20, Z+
	inc		r24
	rcall	OutCharXYFastC		; Put the low nibble to the screen


	ret

; void OutHex8XYFastC(uint8_t, x_char, uint8_t y_char; uint8_t hex_num)
;
; Prints an 8 bit hex value to the screen
;
; Inputs
; 		x_char in R24
; 		y_char in R22
;		hex_num in R20
; Returns 
;		void
; Trashes
;		R0
;		R1
;		R23
;		R30:31


OutHex8XYFastC:

	mov		r19, r20			; Save a copy of the HEX byte we are printing to R19
	swap	r20					; swap high and low nibble
	andi	r20, 0b00001111		; clear out the high nibble
	subi	r20, (-(0x30))		; Add 0x30 to low nibble (0..9 + 0x30 = "0".."9" ASCII)
	cpi		r20, 0x3A			; See if the result is > "9" ASCII
	brlo	OutHex8XYFastCSkip1
	subi	r20, (-(0x07))		; and if it is > "9" then add 7 more to it to get to "A".."F"

OutHex8XYFastCSkip1:
	rcall	OutCharXYFastC		; Put the low nibble to the screen

	inc		r24					; move to the next char right to print second nibble

	mov		r20, r19			; restore the copy of the HEX byte we are printing to R20
	andi	r20, 0b00001111		; clear out the high nibble
	subi	r20, (-(0x30))		; Add 0x30 to low nibble (0..9 + 0x30 = "0".."9" ASCII)
	cpi		r20, 0x3A			; See if the result is > "9" ASCII
	brlo	OutHex8XYFastCSkip2
	subi	r20, (-(0x07))		; and if it is > "9" then add 7 more to it to get to "A".."F"

OutHex8XYFastCSkip2:
	rcall	OutCharXYFastC		; Put the low nibble to the screen

	ret


; void OutCharXYFastC(uint8_t, x_char, uint8_t y_char; uint8_t char_num)
;
; C-Callable version of OutCharXY
;
; Does not used "GetRamTileFastC" as that routine returns value in R24
; This will trash/kill R24 which contains X and would otherwise need to
; be saved.
;
; NOTE:  This routine will only work with ramTiles and VRAM on 1K boundaries
;
; Inputs
; 		x_char in R24
; 		y_char in R22
;		char num in R20 (ascii char)
; Returns 
;		void
;
; Modified RAM
; 		on success 
;				May modify both ramTile array and vram aray.  Read description
;		on fail
;			   	Nill
; Trashed
;		R0
;		R1
;		R21
;		R23
;		R26:27
;		R30:31
;
; NOTE:	 Other ASM routines rely on this routine only trashing the above Regs
; 		 Modify this behaviour and you are on your own.

OutCharXYFastC:
	cpi		r24, 32						; Make Sure X is not out of bounds
	brge	OutCharXYFastCFail1			; Fail if it is
	cpi		r22, 28						; Make Sure X is not out of bounds
	brge	OutCharXYFastCFail1			; Fail if it is
	ldi		r23, 0x20
	mul		r22, r23					; Multiply Y*32
	movw	r26, r0
	add		r26, r24					; Add X
	subi	r27, hi8(-(vram))			; Add VRAM offset

	ld		r21, X						; Load R21 = vram[X+Y*32]
	tst		r21
	brne	OutCharXYFastCAllocated		; if R24 <> 0 then exit

    lds     r21,nextFreeRamTile         ; If not allocated then we need to get # of the next free tile
    cpi     r21,(RAM_TILES_COUNT-1)     ; make sure we have not run out of ram tiles
    breq    OutCharXYFastCFail2			; If we have run out then FAIL

    st		X, r21						; Save the newly allocated tile to vram[X+Y*32]

	inc     r21                         ; Save the new value of "next free" into
    sts     nextFreeRamTile, r21
    dec     r21                         ; undo the INC two lines above because we want to know THIS not next

OutCharXYFastCAllocated:

	ldi		r23, 0x08					; Multiply the ramTileNumber *8
	mul		r21, r23
	movw	r26, r0						; Save that result into the X_Register
	subi	r27, hi8(-(ramTiles))		; Add the offset to the ramTile[] array to X_Register

	mul		r20, r23					; Multiply the Char_Number *8
	movw	r30, r0						; and move the result to the Z_Register
	subi 	r30, lo8(-(FontTable))		; Add the offset to the FontTable[] array to Z_Register
    sbci 	r31, hi8(-(FontTable))		;		(Must be 16 bit add as FontTable is not aligned)

	lpm		r0, Z+						; copy 8 bytes from program memory to ram
	st		X+, r0 
	lpm		r0, Z+
	st		X+, r0 
	lpm		r0, Z+
	st		X+, r0 
	lpm		r0, Z+
	st		X+, r0 
	lpm		r0, Z+
	st		X+, r0 
	lpm		r0, Z+
	st		X+, r0 
	lpm		r0, Z+
	st		X+, r0 
	lpm		r0, Z+
	st		X+, r0 

OutCharXYFastCFail2:
	clr		r1							; restore (zero) for C after it was trashed by MUL
OutCharXYFastCFail1:
	ret



; uint8_t GetRamTileFastC(uint8_t, x_char, uint8_t y_char)
;
; C-Callable version of GetRamTile (27 clks worst vs C version 58)
;
; NOTE:  This routine will only work with ramTiles and VRAM on 1K boundaries
;
; Inputs
; 		x_char in R24
; 		y_char in R22
; Returns 
; 		on success 
;				R24 = ramTileNum
;		on fail
;			   	R24 = 0
; Modified RAM
; 		on success 
;				(uint8_t) VRAM[X + Y*32]   = nextFreeRamTile
;				(uint8_t) nextFreeRamTile = nextFreeRamTile + 1
;		on fail
;			   	Nill
; Trashed
;		R0
;		R1
;		R23
;		R24
;		R26:27
;

GetRamTileFastC:
	cpi		r24, 32						; Make Sure X is not out of bounds
	brge	GetRamTileFastCFail			; Fail if it is
	cpi		r22, 28						; Make Sure X is not out of bounds
	brge	GetRamTileFastCFail			; Fail if it is
	ldi		r23, 0x20
	mul		r22, r23					; Multiply Y*32 (0x20)
	movw	r26, r0						; Move the result of (Y*32) into Z-Register
	add		r26, r24					; Add c_char to the Z-Register
	subi	r27, hi8(-(vram))			; Add VRAM offset to the high byte of Z-Register
	clr		r1
	ld		r24, X						; Load R24 = vram[X + Y*32]
	tst		r24
	brne	GetRamTileFastCAllocated	; if R24 <> 0 then return R24 (exit as success)

    lds     r24,nextFreeRamTile         ; If not allocated then we need to get # of the next free tile
    cpi     r24,(RAM_TILES_COUNT-1)     ; make sure we have not run out of ram tiles
    breq    GetRamTileFastCFail			; If we have run out then FAIL

    st		X, r24						; Save the newly allocated tile to vram[X+Y*32]

	inc     r24                         ; Save the new value of "next free" into variable
    sts     nextFreeRamTile, r24
    dec     r24                         ; undo the INC two lines above because we want to know THIS not next
GetRamTileFastCAllocated:
	ret
GetRamTileFastCFail:
	ldi		r24, 0
	ret


; void SetPixelFastC(uint8_t, x_char, uint8_t y_char)
;
; C-Callable version of SetPixel
;
; NOTE:  This routine will only work with ramTiles and VRAM on 1K boundaries
;
; Inputs
; 		x_pixel in R24
; 		y_pixel in R22
;
; Returns 
; 		void
;
; Modified RAM
; 		on success 
;				May modify both ramTile array and vram aray.  Read description
;		on fail
;			   	Nill
; Trashed
;		R1
;		R0
;		R19
;		R21
;		R22
;		R23
;		R24
;		R25
;		R26:27


SetPixelFastC:

	cpi		r22, 224			; Make sure we are not trying to plot a pixel out out bounds
	brsh	SPF_Fail			; if so fail

    mov     r25,r22             ; Mov Y from r22 to r25 so they are in consecutive regs R24/25

    movw    r26,r24             ; Mov X/Y in to Y-Register (can be trashed). Y is now "VRAM address Hi/Lo"

                                ;                                   r27              r26                Carry
                                ;                                   y7y6y5y4y3y2y1y0 x7x6x5x4x3x2x1x0   -
    lsr     r27                 ;                                   0 y7y6y5y4y3y2y1 x7x6x5x4x3x2x1x0   y0
    lsr     r27                 ;                                   0 0 y7y6y5y4y3y2 x7x6x5x4x3x2x1x0   y1
    lsr     r27                 ;                                   0 0 0 y7y6y5y4y3 x7x6x5x4x3x2x1x0   y2

    lsr     r27                 ;                                   0 0 0 0 y7y6y5y4 x7x6x5x4x3x2x1x0   y3
    ror     r26                 ;                                   0 0 0 0 y7y6y5y4 y3x7x6x5x4x3x2x1   y3

    lsr     r27                 ;                                   0 0 0 0 0 y7y6y5 x7x6x5x4x3x2x1x0   y4
    ror     r26                 ;                                   0 0 0 0 0 y7y6y5 y4y3x7x6x5x4x3x2   y4

    lsr     r27                 ;                                   0 0 0 0 0 0 y7y6 y4y3x7x6x5x4x3x2   y5
    ror     r26                 ;                                   0 0 0 0 0 0 y7y6 y5y4y3x7x6x5x4x3   y5

    ori     r27, hi8(vram)      ; Fixed in linker to 0x0C00         0 0 0 0 1 1 y7y6 y5y4y3x7x6x5x4x3   y5
	
    ld      r22, X              ; Get the Tile to use from VRAM address. r22 is now Tile#

    cpi     r22, 0x00           ; See if there is already a tile allocated at this X/Y address
    brne    SPF_Allocated

    lds     r22,nextFreeRamTile         ; If not allocated then we need to get # of the next free tile
    cpi     r22,(RAM_TILES_COUNT-1)     ; make sure we have not run out of ram tiles
    breq    SPF_Fail

    st      X, r22                      ; After alloacting new tile save the # in the VRAM location X/Y

    inc     r22                         ; Save the new value of "next free" into
    sts     nextFreeRamTile, r22
    dec     r22                         ; undo the INC two lines above because we want to know THIS not next

SPF_Allocated:
                                ;                                   R23 / R1         R22 / R0           Carry
                                ;                                   - - - - - - - -  0 t6t5t4t3t2t1t0   -
    ldi     r19, 0x08           ;
    mul     r22, r19            ; x8 and leave result in r0/r1      0 0 0 0 0 0 t6t5 t4t3t2t1t0- - -    -
    andi    r25, 0x07           ; clear r25 to 0 0 0 0 0 y2y1y0
    or      r0, r25             ;                                   0 0 0 0 0 0 t6t5 t4t3t2t1t0y2y1y0   -

;   NEXT LINE IS DEFERED TILL BELOW Duplicated for comment clarity
;   subi    r27, hi8(-(ramTiles))   ; Fixed in linker at 0x0400


                                    ;                               R25              R24                Carry
                                    ;                               0 0 0 0 0 y2y1y0 x7x6x5x4x3x2x1x0   -
    andi    r24, 0b00000111         ;                               0 0 0 0 0 y2y1y0 0 0 0 0 0 x2x1x0   -
    ori     r24, lo8(shift_tbl_ram) ;                               0 0 0 0 0 y2y1y0 t7t6t5t4t3x2x1x0   -
    ldi     r25, hi8(shift_tbl_ram) ;                               T7T6T5T4T3T2T1T0 t7t6t5t4t3x2x1x0   -
	
    movw    r26, r24                ; Get pixel mask			
    ld      r20, X

    movw    r26, r0             	; Move Tile_Row_Byte_Address into Y from r0/r1 where it was left from MUL
	
;   NEXT LINE IS DEFERED FROM ABOVE
    subi    r27, hi8(-(ramTiles))
    ld      r21, X              	; Get TileRowByte
    or      r21, r20            	; OR TileRowByte with the pixel mask
    st      X, r21              	; write TileRowByte back to memory

    clr     r1                 		; clear r1 back to zero after the MUL trashing.
	
SPF_Fail:

    ret


; fast_line_enty
;
; Saves trashed "call saved" registers to the stack
; and loads three frequently used literals into R25, R28 and R29


.macro fast_line_entry
	push	r15						; Save register used by "err"
	push	r16						; Save register used by "dummy"
	push	r17						; Save register used by ramTilePixelByte
	push	r28						; Save register used by 0x04 to be used repeatedly by MUL
	push	r29						; Save register used by 0x20 to be used repeatedly by MUL
	ldi		r25, 0x08
	ldi		r28, 0x04
	ldi		r29, 0x20
.endm

; fast_line_exit
;
; Saves the currently held local copy of the pixels in ramTilePixelByte
; and restores trashed registers and the stack

.macro fast_line_exit
	st		Z, r17					; save ramTilePixelByte into the location pointed to by ramTileByteAddress
	pop		r29
	pop		r28
	pop		r17
	pop		r16
	pop		r15
	clr		r1
.endm

; fast_line_convert_x0_y0_into_VRAM_address
;
; converts the X0 and Y0 address passed in r24 and r22 into a VRAM memory
; location and leaves this result in R26:27 (VRAM_Address)
;
; Inputs 
; 			Y0 address = R22
;			X0 address = R24
; Outputs
;			VRAM_Address = R26:27 (X)
; 
; Requires that the constants 4 and 32 are in R28, R29
;
; Trashes R0:1

.macro fast_line_convert_x0_y0_into_VRAM_address
	mul		r22, r28				; Multiply Y0 by 4   y7y6y5y4y3y2y1y0 		=> .0.0.0.0.0.0y7y6:y5y4y3y2y1y0.0.0
	movw	r26, r0					; move the 16 bit result into VRAM_Address
	andi	r26, 0b11100000			; clear out the bits that are used for Xn	   .0.0.0.0.0.0y7y6:y5y4y3.0.0.0.0.0
	mul		r24, r29				; Multiply X0 by 32  x7x6x5x4x3x2x1x0 		=> .0.0.0x7x6x5x4x3:x2x1x0.0.0.0.0.0
	or		r26, r1					; OR X7..3 into low byte of VRAM_Address	   .0.0.0.0.0.0y7y6:y5y4y3x7x6x5x4x3
	subi	r27, hi8(-(vram))		; Add the base address of VRAM				   .0.0.0.0.1.1y7y6:y5y4y3x7x6x5x4x3
.endm

; fast_line_update_Xn_in_VRAM_address
;
; updates the X0 address part of the pointer held in R26:27 (VRAM_Address)
; This is done constantly in Horizontal lines and often in shallow diagonal lines 
; Updating only the X part of the address takes 4 clocks cycles rather than
; 8 clk for "fast_line_convert_x0_y0_into_VRAM_address"
;
; Note: there is no equivelant "update Y only" routine as updating Y takes 8 clks
;
; Inputs 
;			X0 address = R24
; Outputs
;			VRAM_Address = R26:27 (X)
; 
; Requires that the constant 32 be in R29
;
; Trashes R0:1

.macro fast_line_update_Xn_in_VRAM_address
	andi	r26, 0b11100000			; clear out the old Xn bits 			  X => .0.0.0.0.1.1y7y6:y5y4y3.0.0.0.0.0
	mul		r24, r29				; Multiply X0 by 32  x7x6x5x4x3x2x1x0 	 R0 => .0.0.0x7x6x5x4x3:x2x1x0.0.0.0.0.0
	or		r26, r1					; OR X7..3 into low byte of VRAM_Address  X => .0.0.0.0.0.0y7y6:y5y4y3x7x6x5x4x3
.endm

; fast_line_convert_ramTileNo_into_ramTileByteAddress
; 
; Takes a 8 bit value in R30 (ramTileNumber) and the Y0 address (R22) and converts
; this into the the 16 bit pointer in R30:31 (ramTileByteAddress)
;
; Inputs
;			Y0 address  = R22
;			ramTileNumber = R30
; Outputs
;			ramTileByteAddress = R30:31 (Z)
;
; Requires that the constant 4 be in R28
;
; Trashes R0:1

.macro fast_line_convert_ramTileNo_into_ramTileByteAddress
	mul		r30, r25				; Mul ramTileNo x8 with line above)		R0  => .0.0.0.0.0.0t6t5:t4t3t2t1t0.0.0.0
	mov		r30, r22				; mov Y0 into R30 (that is now free because result of MUL is safe in R0:1)
	andi	r30, 0b00000111			; save only the lower 3bit of Y0		  Z => .?.?.?.?.?.?.?.?:.0.0.0.0.0y2y1y0
	mov		r31, r1					; move HI byte of 16bit result into ZH    Z => .0.0.0.0.0.0t6t5:.0.0.0.0.0y2y1y0
	or		r30, r0					; or IN the lower 5 bits of t		      Z => .0.0.0.0.0.0t6t5:t4t3t2t1t0y2y1y0
	subi	r31, hi8(-(ramTiles))	; add the base address of RamTles to
.endm

; fast_line_get_ramTilePixelByte
;
; Gets a local copy of the 8bits (representing 8 pixels) pointed to by
; R30:31 (ramTileByteAddress)
;
; Inputs
;			ramTileByteAddress = R30:31 (Z)
; Outputs
;			ramTilePixelByte = R17

.macro fast_line_get_ramTilePixelByte
	ld		r17, Z					; get local copy of 8 pixels at the ramTileByteAddress into ramTilePixelByte
.endm

; fast_line_get_pixel_mask
;
; Turns the lower 3 bits of R24 (X0 Address) into a pixelMask used to OR
; on a pixel within the pixelByte
;
; Inputs
;			X0 address = R24
; Outputs
;			pixelMask = R23
;
; Requires an 8 byte long 8 byte aligned table in RAM 
; 
; 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01
;
; Trashes R30:31

.macro fast_line_get_pixel_mask		; This routine trashes Z so must be done before "ramTileAddress"
	mov		r30, r24				; Copy X0 into ZL						  Z => .?.?.?.?.?.?.?.?:x7x6x5x4x3x2x1x0
	andi	r30, 0b00000111			; only keep lower 3 bits				  Z => .?.?.?.?.?.?.?.?:.0.0.0.0.0x2x1x0
	ori		r30, lo8(shift_tbl_ram)	; OR in the shift table ram address	LO8	  Z => .?.?.?.?.?.?.?.?:t7t6t5t4t3x2x1x0
	ldi		r31, hi8(shift_tbl_ram)	; load in the shift table ram HI8		  Z => T7T6T5T4T3T2T1T0:t7t6t5t4t3x2x1x0
	ld		r23, Z					; Get the pixelMask from the table
.endm

; fast_line_OR_pixel_mask
;
; OR R23 (pixelMask) with R17 (the local copy of the pixelByte)
;
; Inputs
;			pixelMask = R23
;			ramTilePixelByte = R17
; Outputs
;			ramTilePixelByte = R17

.macro fast_line_OR_pixel_mask
	or		r17, r23				; OR the local copy of ramTilePixelByte with pixelMask
.endm

; fast_line_write_ramTilePixelByte
;
; Saves R17 (Local copy of ramTilePixelByte) into the RAM location pointed to by
; R30:31 (ramTileByteAddress)
;
; Inputs
;			ramTilePixelByte = R17
;			ramTileByteAddress = R30:31 (Z)
; Outputs
;			RAM Location pointed to by Z

.macro fast_line_write_ramTilePixelByte
	st		Z, r17					; save ramTilePixelByte into the location pointed to by ramTileByteAddress
.endm

; fast_line_get_ramTileNo
;
; Get the ramTileNumber pointed to by VRAM_Address
; If the VRAM_Address is currently pointing to ramTileNumber = 0 then
; try allocate a new ramTile and save it in that VRAM_Address Location.
; If no more ramTiles are free then FAIL and exit the line draw routine
;
; NOTE: "FAIL" is a jump to the exit location of the routine.  This
; means you can NOT RCALL/CALL any of these routines. They all must
; be inlined
;
; Inputs
;		VRAM_Address = R26:27 (X)
;		nextFreeRamTile = 8 bit Variable in RAM
; Outputs
; 		ramTileNumber = R30
;		nextFreeRamTile = 8 bit Variable in RAM
;		RAM Location pointed to by Z
; Trashes
;		R30:31 (ramTileByteAddress)

.macro fast_line_get_ramTileNo
	ld		r30, X					; get ramTileNo from VRAM_address
	cpi		r30, 0x00				; see if there is already a ramTile allocated
	brne	.Lfast_line_get_ramTileNo_allocated\@
									; if ramTileNO != 0 then there is already a tile allocated at this address
	lds		r30,nextFreeRamTile 	; otherwise get the next free tile number to allocate
	cpi     r30,(RAM_TILES_COUNT-1)	; compare this with the maximum number of tiles available
	brne	.Lfast_line_get_ramTileNo_continue\@
									; if there are more free tiles available then continue
	rjmp	bresh_pixel_fail		; otherwise FAIL

.Lfast_line_get_ramTileNo_continue\@:	; continue (no "out of ramTiles error")
	st		X, r30					; save the newly allocated ramTileNo into VRAM at VRAM_address
	inc		r30						; inc "nextFreeRamTile"
	sts		nextFreeRamTile, r30	; Save it to variable in RAM
	dec		r30						; undo the inc. above as we need to know CURRENT ramTileNo NOT nextFreeRamTile		
.Lfast_line_get_ramTileNo_allocated\@:	; allocated
.endm

; fast_line_X_plus
; fast_line_X_minus
; fast_line_Y_plus
; fast_line_Y_minus
; fast_line_XP_YP (X plus  Y plus )
; fast_line_XM_YP (X minus Y plus )
; fast_line_XM_YM (X minus Y minus)
; fast_line_XP_YM (X plus  Y minus)
;
; Eight inline routines to quickly put a pixel in the 8 locations
; next to the last pixel that was plotted
;
; +------+------+------+
; |XM_YM |YM    |XP_YM |
; |      |      |      |
; |      |      |      |
; +------+------+------+
; |XM    |      |XP    |
; |      |      |      |
; |      |      |      |
; +------+------+------+
; |XM_YP |YM    |XP_YP |
; |      |      |      |
; |      |      |      |
; +------+------+------+
;
; During Bresenham linedraw routine all the pixels being plotted (except the first)
; are in the one of eight locations on the screen next to the last pixel.
;
; Due to that fact we will already know most of the information needed to plot
; the current pixel and do not need to recalculate it.
;
; Example - for an X_Plus pixel plot we already know the Y address and we have a
; 7 in 8 chance of already knowing the pixelByte.  We also know what the last
; pixelMask was and can calculate it with an logical shift right (LSR)
;
; Also in the 1/8 chance that we need a NEW pixel byte, we can also save some time
; by not calculating the full X/Y address as we already know the Y address
;
; 7/8th of the time fast_line_X_plus will run in 4 CLKs 
; 1/8th of the time fast_line_X_plus will run in 25/34 CLKs (existing/new ramTile)
;
; This is opposed to 37/47 CLKs for a routine that blindly calls "PutPixel"

.macro fast_line_X_plus
	lsr		r23								; rotate the pixel mask
	brcc	.Lfast_line_X_plus_same_byte\@	; if there is no carry then we dont need to :
	ror		r23								; rotate the carry bit back into the other side
	
	fast_line_write_ramTilePixelByte		; save the current pixel byte before getting new one
	fast_line_update_Xn_in_VRAM_address		; update the X part of VRAM_address (Y has not changed)
	fast_line_get_ramTileNo					; get the new ramTileNumber
	fast_line_convert_ramTileNo_into_ramTileByteAddress
	fast_line_get_ramTilePixelByte

.Lfast_line_X_plus_same_byte\@:  			; Still on the same ramTilePixelByte
	fast_line_OR_pixel_mask
.endm

.macro fast_line_X_minus
	lsl		r23								; rotate the pixel mask
	brcc	.Lfast_line_X_minus_same_byte\@	; if there is no carry then we dont need to :
	rol		r23								; rotate the carry bit back into the other side
	
	fast_line_write_ramTilePixelByte		; save the current pixel byte before getting new one
	fast_line_update_Xn_in_VRAM_address		; update the X part of VRAM_address (Y has not changed)
	fast_line_get_ramTileNo					; get the new ramTileNumber
	fast_line_convert_ramTileNo_into_ramTileByteAddress
	fast_line_get_ramTilePixelByte

.Lfast_line_X_minus_same_byte\@:  			; Still on the same ramTilePixelByte
	fast_line_OR_pixel_mask
.endm

.macro fast_line_Y_plus
	fast_line_write_ramTilePixelByte	; save the current pixel byte before getting new one
	inc		r30							; Inc ramTileByteAddress ~~ INC Y0.  Dont need 16 bit as an overflow will be a fail
	mov		r16, r30					; save a copy of the lo8 byte of ramTileByteAddress
	andi	r16, 0b00000111				; test to see if the bottom 3 bits are clear
	brne	.Lfast_line_Y_plus_no_3bit_rollover\@	; if not we are still on the same ramTile
	
												; otherwise we have to
	fast_line_convert_x0_y0_into_VRAM_address	; get the new vram_address (only Y was changed but update_X/Y is as fast)
	fast_line_get_ramTileNo						; get the new ramTileNumber
	fast_line_convert_ramTileNo_into_ramTileByteAddress

.Lfast_line_Y_plus_no_3bit_rollover\@:

	fast_line_get_ramTilePixelByte
	fast_line_OR_pixel_mask

.endm

.macro fast_line_Y_minus
	fast_line_write_ramTilePixelByte	; save the current pixel byte before getting new one
	mov		r16, r30					; save a copy of the lo8 byte of ramTileByteAddress
	andi	r16, 0b00000111				; test to see if the bottom 3 bits are clear
	brne	.Lfast_line_Y_minus_no_3bit_rollover\@	; if not we will still be on the same ramTile after the DEC
	
												; otherwise we have to
	fast_line_convert_x0_y0_into_VRAM_address	; get the new vram_address (only Y was changed but update_X/Y is as fast)
	fast_line_get_ramTileNo						; get the new ramTileNumber
	fast_line_convert_ramTileNo_into_ramTileByteAddress
	rjmp	.Lfast_line_Y_minus_common\@

.Lfast_line_Y_minus_no_3bit_rollover\@:
	dec		r30							; DEC ramTileByteAddress ~~ DEC Y0.  Dont need 16 bit as an overflow will be a fail

.Lfast_line_Y_minus_common\@:

	fast_line_get_ramTilePixelByte
	fast_line_OR_pixel_mask

.endm

.macro fast_line_XP_YP
	fast_line_write_ramTilePixelByte		; save the current pixel byte before getting new one
	lsr		r23								; rotate the pixel mask
	brcc	.Lfast_line_XP_YP_no_wrap\@		; if there is no carry then we dont need to :
	ror		r23								; rotate the carry bit back into the other side

	fast_line_convert_x0_y0_into_VRAM_address	; get the new vram_address (only Y was changed but update_X/Y is as fast)
	fast_line_get_ramTileNo						; get the new ramTileNumber
	fast_line_convert_ramTileNo_into_ramTileByteAddress
	fast_line_get_ramTilePixelByte
	fast_line_OR_pixel_mask
	rjmp 	.Lfast_line_XP_YP_end\@

.Lfast_line_XP_YP_no_wrap\@:
	fast_line_Y_plus
.Lfast_line_XP_YP_end\@:
.endm

.macro fast_line_XM_YP
	fast_line_write_ramTilePixelByte		; save the current pixel byte before getting new one
	lsl		r23								; rotate the pixel mask
	brcc	.Lfast_line_XM_YP_no_wrap\@		; if there is no carry then we dont need to :
	rol		r23								; rotate the carry bit back into the other side

	fast_line_convert_x0_y0_into_VRAM_address	; get the new vram_address (only Y was changed but update_X/Y is as fast)
	fast_line_get_ramTileNo						; get the new ramTileNumber
	fast_line_convert_ramTileNo_into_ramTileByteAddress
	fast_line_get_ramTilePixelByte
	fast_line_OR_pixel_mask
	rjmp	.Lfast_line_XM_YP_exit\@

.Lfast_line_XM_YP_no_wrap\@:
	fast_line_Y_plus
.Lfast_line_XM_YP_exit\@:
.endm


.macro fast_line_XP_YM
	fast_line_write_ramTilePixelByte		; save the current pixel byte before getting new one
	lsr		r23								; rotate the pixel mask
	brcc	.Lfast_line_XP_YM_no_wrap\@		; if there is no carry then we dont need to :
	ror		r23								; rotate the carry bit back into the other side

	fast_line_convert_x0_y0_into_VRAM_address	; get the new vram_address (only Y was changed but update_X/Y is as fast)
	fast_line_get_ramTileNo						; get the new ramTileNumber
	fast_line_convert_ramTileNo_into_ramTileByteAddress
	fast_line_get_ramTilePixelByte
	fast_line_OR_pixel_mask
	rjmp	.Lfast_line_XP_YM_exit\@

.Lfast_line_XP_YM_no_wrap\@:
	fast_line_Y_minus
.Lfast_line_XP_YM_exit\@:
.endm

.macro fast_line_XM_YM
	fast_line_write_ramTilePixelByte		; save the current pixel byte before getting new one
	lsl		r23								; rotate the pixel mask
	brcc	.Lfast_line_XM_YM_no_wrap\@		; if there is no carry then we dont need to :
	rol		r23								; rotate the carry bit back into the other side

	fast_line_convert_x0_y0_into_VRAM_address	; get the new vram_address (only Y was changed but update_X/Y is as fast)
	fast_line_get_ramTileNo						; get the new ramTileNumber
	fast_line_convert_ramTileNo_into_ramTileByteAddress
	fast_line_get_ramTilePixelByte
	fast_line_OR_pixel_mask
	rjmp	.Lfast_line_XM_YM_exit\@

.Lfast_line_XM_YM_no_wrap\@:
	fast_line_Y_minus
.Lfast_line_XM_YM_exit\@:
.endm

; bresh_q1_asm
; bresh_q2_asm
; bresh_q3_asm
; bresh_q4_asm
;
; Four routines to cover the four quadrants in Bresenhams line draw algo.
;
; Q1 = X+Y+
; Q2 = X-Y+
; Q3 = X-Y-
; Q4 = X+Y-
;
; Although it is normal to cover the quadrants with "Step_X" and "Step"Y"
; variables with only one set of decisions to be made before the two main
; loops.  In this case (for speed) we also need to run (inline) routines
; that are specific to X+/X-/Y+/Y-.  It would be too expensive to make
; decision/branch each itteration of the inner loop.  So after our first
; quadrant decision, we just JUMP to one of four routines that are hard
; coded for "Step_X", "Step_Y" and the special case pixel plotting
; routines.
;
; Apart from that they are bog-standard Bresenham and should not need
; any indepth explanation

bresh_q1_asm:
	; dx = gx1 - gx0
	mov		r21, r20				; Copy gx1 into dx
	sub		r21, r24				; subtract (without carry)  gx0 from dx (contains gx1)

	; dy = gy1 - gy0
	mov		r19, r18				; copy gy1 into dy
	sub		r19, r22				; subtract (without carry) gy0 from dy (contains gy1)

	; if (dx < dy)
	cp		r21, r19
	brge	bresh_q1_shallow		; (not_true) -> ELSE
	rjmp	bresh_q1_steep

bresh_q1_shallow:
	; err = dx >> 1
	mov		r15, r21				; copy dx into err
	asr		r15						; dx >> 1

bresh_q1_shallow_loop:
	; err = err - dy
	sub		r15, r19
	; gx0++
	inc		r24

	; if (err < 0)
	sbrs	r15, 7						; if bit7 is 1 the result is negative
	rjmp	bresh_q1_shallow_no_minor	; (not_true) -> continue

bresh_q1_shallow_minor:
	; err = err + dx
	add		r15, r21
	; gy0++
	inc		r22
	; SetPixelFastC(gx0, gy0)
	fast_line_XP_YP
	; while (gx0 != gx1)
	cp		r24, r20
	breq	bresh_q1_shallow_exit
	rjmp	bresh_q1_shallow_loop	


bresh_q1_shallow_no_minor:
	; SetPixelFastC(gx0, gy0)
	fast_line_X_plus


	; while (gx0 != gx1)
	cp		r24, r20
	breq	bresh_q1_shallow_exit
	rjmp	bresh_q1_shallow_loop	
bresh_q1_shallow_exit:
	fast_line_exit
	ret



bresh_q1_steep:
	; err = dy >> 1
	mov		r15, r19				; copy dy into err
	asr		r15						; dy >> 1

bresh_q1_steep_loop:
	; err = err - dx
	sub		r15, r21

	; gy0++
	inc		r22

	; if (err < 0)
	sbrs	r15, 7					; if bit7 is 1 the result is negative
	rjmp	bresh_q1_steep_no_minor	; (not_true) -> continue

bresh_q1_steep_minor:
	; err = err + dy
	add		r15, r19
	; gx0++
	inc		r24
	; SetPixelFastC(gx0, gy0)
	fast_line_XP_YP
	; while (gy0 != gy1)
	cp		r22, r18
	breq	bresh_q1_steep_exit
	rjmp	bresh_q1_steep_loop


bresh_q1_steep_no_minor:
	; SetPixelFastC(gx0, gy0)
	fast_line_Y_plus


	; while (gy0 != gy1)
	cp		r22, r18
	breq	bresh_q1_steep_exit
	rjmp	bresh_q1_steep_loop	

bresh_q1_steep_exit:
	fast_line_exit
	ret


bresh_q2_asm:
	; dx = gx0 - gx1
	mov		r21, r24				; Copy gx0 into dx
	sub		r21, r20				; subtract (without carry)  gx1 from dx (contains gx0)

	; dy = gy1 - gy0
	mov		r19, r18				; copy gy1 into dy
	sub		r19, r22				; subtract (without carry) gy0 from dy (contains gy1)

	; if (dx < dy)
	cp		r21, r19
	brge	bresh_q2_shallow		; (not_true) -> ELSE
	rjmp	bresh_q2_steep

bresh_q2_shallow:
	; err = dx >> 1
	mov		r15, r21				; copy dx into err
	asr		r15						; dx >> 1

bresh_q2_shallow_loop:
	; err = err - dy
	sub		r15, r19
	; gx0--
	dec		r24

	; if (err < 0)
	sbrs	r15, 7						; if bit7 is 1 the result is negative
	rjmp	bresh_q2_shallow_no_minor	; (not_true) -> continue

bresh_q2_shallow_minor:
	; err = err + dx
	add		r15, r21
	; gy0++
	inc		r22
	; SetPixelFastC(gx0, gy0)
	fast_line_XM_YP
	; while (gx0 != gx1)
	cp		r24, r20
	breq	bresh_q2_shallow_exit
	rjmp	bresh_q2_shallow_loop	


bresh_q2_shallow_no_minor:
	; SetPixelFastC(gx0, gy0)
	fast_line_X_minus
	; while (gx0 != gx1)
	cp		r24, r20
	breq	bresh_q2_shallow_exit
	rjmp	bresh_q2_shallow_loop	
bresh_q2_shallow_exit:
	fast_line_exit
	ret


bresh_q2_steep:
	; err = dy >> 1
	mov		r15, r19				; copy dy into err
	asr		r15						; dy >> 1

bresh_q2_steep_loop:
	; err = err - dx
	sub		r15, r21
	; gy0++
	inc		r22

	; if (err < 0)
	sbrs	r15, 7					; if bit7 is 1 the result is negative
	rjmp	bresh_q2_steep_no_minor	; (not_true) -> continue

bresh_q2_steep_minor:
	; err = err + dy
	add		r15, r19
	; gx0--
	dec		r24
	; SetPixelFastC(gx0, gy0)
	fast_line_XM_YP
	; while (gy0 != gy1)
	cp		r22, r18
	breq	bresh_q2_steep_exit
	rjmp	bresh_q2_steep_loop	


bresh_q2_steep_no_minor:
	; SetPixelFastC(gx0, gy0)
	fast_line_Y_plus
	; while (gy0 != gy1)
	cp		r22, r18
	breq	bresh_q2_steep_exit
	rjmp	bresh_q2_steep_loop	
bresh_q2_steep_exit:
	fast_line_exit
	ret




bresh_q3_asm:
	; dx = gx0 - gx1
	mov		r21, r24				; Copy gx0 into dx
	sub		r21, r20				; subtract (without carry)  gx1 from dx (contains gx0)

	; dy = gy0 - gy1
	mov		r19, r22				; copy gy0 into dy
	sub		r19, r18				; subtract (without carry) gy1 from dy (contains gy0)

	; if (dx < dy)
	cp		r21, r19
	brge	bresh_q3_shallow		; (not_true) -> ELSE
	rjmp	bresh_q3_steep

bresh_q3_shallow:
	; err = dx >> 1
	mov		r15, r21				; copy dx into err
	asr		r15						; dx >> 1

bresh_q3_shallow_loop:
	; err = err - dy
	sub		r15, r19
	; gx0--
	dec		r24

	; if (err < 0)
	sbrs	r15, 7						; if bit7 is 1 the result is negative
	rjmp	bresh_q3_shallow_no_minor	; (not_true) -> continue

bresh_q3_shallow_minor:
	; err = err + dx
	add		r15, r21
	; gy0--
	dec		r22
	; SetPixelFastC(gx0, gy0)
	fast_line_XM_YM
	; while (gx0 != gx1)
	cp		r24, r20
	breq	bresh_q3_shallow_exit
	rjmp	bresh_q3_shallow_loop	


bresh_q3_shallow_no_minor:
	; SetPixelFastC(gx0, gy0)
	fast_line_X_minus
	; while (gx0 != gx1)
	cp		r24, r20
	breq	bresh_q3_shallow_exit
	rjmp	bresh_q3_shallow_loop	
bresh_q3_shallow_exit:
	fast_line_exit
	ret


bresh_q3_steep:
	; err = dy >> 1
	mov		r15, r19				; copy dy into err
	asr		r15						; dy >> 1

bresh_q3_steep_loop:
	; err = err - dx
	sub		r15, r21
	; gy0--
	dec		r22

	; if (err < 0)
	sbrs	r15, 7					; if bit7 is 1 the result is negative
	rjmp	bresh_q3_steep_no_minor	; (not_true) -> continue

bresh_q3_steep_minor:
	; err = err + dy
	add		r15, r19
	; gx0--
	dec		r24
	; SetPixelFastC(gx0, gy0)
	fast_line_XM_YM
	; while (gy0 != gy1)
	cp		r22, r18
	breq	bresh_q3_steep_exit
	rjmp	bresh_q3_steep_loop	


bresh_q3_steep_no_minor:
	; SetPixelFastC(gx0, gy0)
	fast_line_Y_minus
	; while (gy0 != gy1)
	cp		r22, r18
	breq	bresh_q3_steep_exit
	rjmp	bresh_q3_steep_loop	
bresh_q3_steep_exit:
	fast_line_exit
	ret


bresh_q4_asm:
	; dx = gx1 - gx0
	mov		r21, r20				; Copy gx1 into dx
	sub		r21, r24				; subtract (without carry)  gx0 from dx (contains gx1)

	; dy = gy0 - gy1
	mov		r19, r22				; copy gy0 into dy
	sub		r19, r18				; subtract (without carry) gy1 from dy (contains gy0)

	; if (dx < dy)
	cp		r21, r19
	brge	bresh_q4_shallow		; (not_true) -> ELSE
	rjmp	bresh_q4_steep

bresh_q4_shallow:
	; err = dx >> 1
	mov		r15, r21				; copy dx into err
	asr		r15						; dx >> 1

bresh_q4_shallow_loop:
	; err = err - dy
	sub		r15, r19
	; gx0++
	inc		r24

	; if (err < 0)
	sbrs	r15, 7						; if bit7 is 1 the result is negative
	rjmp	bresh_q4_shallow_no_minor	; (not_true) -> continue

bresh_q4_shallow_minor:
	; err = err + dx
	add		r15, r21
	; gy0--
	dec		r22
	; SetPixelFastC(gx0, gy0)
	fast_line_XP_YM
	; while (gx0 != gx1)
	cp		r24, r20
	breq	bresh_q4_shallow_exit
	rjmp	bresh_q4_shallow_loop	

bresh_q4_shallow_no_minor:
	; SetPixelFastC(gx0, gy0)
	fast_line_X_plus
	; while (gx0 != gx1)
	cp		r24, r20
	breq	bresh_q4_shallow_exit
	rjmp	bresh_q4_shallow_loop	
bresh_q4_shallow_exit:
	fast_line_exit
	ret


bresh_q4_steep:
	; err = dy >> 1
	mov		r15, r19				; copy dy into err
	asr		r15						; dy >> 1

bresh_q4_steep_loop:
	; err = err - dx
	sub		r15, r21
	; gy0--
	dec		r22

	; if (err < 0)
	sbrs	r15, 7					; if bit7 is 1 the result is negative
	rjmp	bresh_q4_steep_no_minor	; (not_true) -> continue

bresh_q4_steep_minor:
	; err = err + dy
	add		r15, r19
	; gx0++
	inc		r24
	; SetPixelFastC(gx0, gy0)
	fast_line_XP_YM
	; while (gy0 != gy1)
	cp		r22, r18
	breq	bresh_q4_steep_exit
	rjmp	bresh_q4_steep_loop	


bresh_q4_steep_no_minor:
	; SetPixelFastC(gx0, gy0)
	fast_line_Y_minus
	; while (gy0 != gy1)
	cp		r22, r18
	breq	bresh_q4_steep_exit
	rjmp	bresh_q4_steep_loop	
bresh_q4_steep_exit:
	fast_line_exit
	ret

; bresh_line_hplus_asm_loop:
; bresh_line_hminus_asm_loop:
; bresh_line_vplus_asm_loop:
; bresh_line_vminus_asm_loop:
;
; Four routines to cover the four special cases of lines with
; M = 0 or infinity

bresh_line_hplus_asm_loop:
	inc		r24
	fast_line_X_plus
bresh_line_hplus_asm:
	cp		r20, r24
	brne	bresh_line_hplus_asm_loop
	fast_line_exit
	ret

bresh_line_hminus_asm_loop:
	dec		r24
	fast_line_X_minus
bresh_line_hminus_asm:
	cp		r20, r24
	brne	bresh_line_hminus_asm_loop
	fast_line_exit
	ret

bresh_line_vplus_asm_loop:
	inc		r22
	fast_line_Y_plus
bresh_line_vplus_asm:
	cp		r18, r22
	brne	bresh_line_vplus_asm_loop
	fast_line_exit
	ret

bresh_line_vminus_asm_loop:
	dec		r22
	fast_line_Y_minus
bresh_line_vminus_asm:
	cp		r18, r22
	brne	bresh_line_vminus_asm_loop
	fast_line_exit
	ret

; void bresh_line_asm(uint8_t x0, uint8_t y0, uint8_t x1, uint8_t y1)
;
; Bresenham Line draw Algo
;
; Does housekeeping and sets up the registers for the "FAST" routines
;
; Tests for NINE seperate cases of the line by comparing X0, X1, Y0 and Y1
;
; Case 1: Horizontal + Line
; Case 2: Horizontal - Line
; Case 3: Vertical  + Line
; Case 4: Vertical  - Line
; Case 5: Quadrant 1 (H+V+)
; Case 6: Quadrant 2 (H-V+)
; Case 7: Quadrant 3 (H-V-)
; Case 8: Quadrant 4 (H+V-)
; Case 9: Single Pixel (Zero Length Line)
;
; Does the closing housekeeping and returns to the C calling program
;
; Register usage from this point onwards
;
;R0			MUL Result (temporary)
;R1		#	MUL Result (temporary)
;
;R15	#	err
;R16	#	dummy (for Y+/Y- address test)
;R17	#	ramTilePixelByte
;R18		Y1
;R19		dy
;R20		X1
;R21		dx
;R22		Y0
;R23		pixelMask
;R24		X0
;R25		Literal Constant (0x08)
;R26 XL		VRAM_Address (lo)
;R27 XH		VRAM_Address (hi)	
;R28 YL	#	Literal Constant (0x04)
;R29 YH	#	Literal Constant (0x20)
;R30 ZL		ramTileByteAddress (lo) / ramTileNumber
;R31 ZH		ramTileByteAddress (hi)
;
; (# = Call saved and must not be saved/restored on exit)

bresh_line_asm:

	fast_line_entry
	fast_line_convert_x0_y0_into_VRAM_address
	fast_line_get_pixel_mask
	fast_line_get_ramTileNo
	fast_line_convert_ramTileNo_into_ramTileByteAddress
	fast_line_get_ramTilePixelByte
	fast_line_OR_pixel_mask
	fast_line_write_ramTilePixelByte

	cp		r18, r22				; compare Y1 and Y0
	breq	bresh_h_line			; if Y1 = Y0 are equal we can only be a hoizontal line
	brlo	v_minus_q3_q4			; if Y1 < Y0 we can only be V-, Quadrant 3 or Quadrant 4
									; if Y1 > Y0 we can only be V+, Q1 or Q2
v_plus_q1_q2:
	cp		r20, r24				; comapre X1 and X0
	breq	v_plus					; If X1 = X0 (and Y1 > Y0 from previous) we must be a V+
	brlo	q2						; if X1 < X0 (and Y1 > Y0 from previous) we must be Q2
									; if X1 > X0 (and Y1 > Y0 from previous) we must be Q1
q1:
	rjmp	bresh_q1_asm
q2:
	rjmp	bresh_q2_asm
v_plus:
	rjmp	bresh_line_vplus_asm


v_minus_q3_q4:
	cp		r20, r24				; comapre X1 and X0
	breq	v_minus					; If X1 = X0 (and Y1 < Y0 from previous) we must be a V-
	brlo	q3						; if X1 < X0 (and Y1 < Y0 from previous) we must be Q3
									; if X1 > X0 (and Y1 < Y0 from previous) we must be Q4

q4:
	rjmp	bresh_q4_asm
q3:
	rjmp	bresh_q3_asm
v_minus:
	rjmp	bresh_line_vminus_asm



bresh_h_line:
	cp		r20, r24				; comapre X1 and X0
	breq	bresh_pixel				; If X1 = X0 (and Y1 = Y0 from previous) we must be a single pixel
	brlo	h_minus					; if X1 < X0 (and Y1 = Y0 from previous) we must be H-
									; if X1 > X0 (and Y1 = Y0 from previous) we must be H+

h_plus:
	rjmp	bresh_line_hplus_asm
h_minus:
	rjmp	bresh_line_hminus_asm

bresh_pixel:

bresh_pixel_fail:		; Do not use the normal "fast_line"exit" routine
						; when failing as we dont want to write the local
						; pixel data to a random unknown location.
						
	pop		r29			; We only want to restore trashed registers
	pop		r28			; and leave the stack in the same state as
	pop		r17			; on entry
	pop		r16
	pop		r15
	clr		r1

	ret

; AddBCD
;
; Adds an 8bit (2 digit) BCD number to a 16bit (4 digit) BCD
;
; Input
;		Packed 16 bit BCD Accumulator 	in r24:25
;		Packed  8 bit BCD Add			in r22
; Returns
;		Packed 16 bit BCD Accumulator 	in r24:25

.global AddBCD
AddBCD:

	mov		r23, r22
	andi	r22, 0x0F
	andi	r23, 0xF0

	add		r24, r22
	brhs	AddBCD_Nibble_1_Overflow
	mov		r21, r24
	andi	r21, 0x0F
	cpi		r21, 0x0A
	brlo	AddBCD_No_Nibble_1_Overflow

AddBCD_Nibble_1_Overflow:

	subi	r24, 0x0A
	subi	r23, (-(0x10))

AddBCD_No_Nibble_1_Overflow:	

	add		r24, r23
	ldi		r23, 0x00
	brcs	AddBCD_Nibble_2_Overflow
	mov		r21, r24
	andi	r21, 0xF0
	cpi		r21, 0xA0
	brlo	AddBCD_No_Nibble_2_Overflow

AddBCD_Nibble_2_Overflow:

	subi	r24, 0xA0
	ldi		r23, 0x01

AddBCD_No_Nibble_2_Overflow:	

	add		r25, r23
	ldi		r23, 0x00
	mov		r21, r25
	andi	r21, 0x0F
	cpi		r21, 0x0A
	brlo	AddBCD_No_Nibble_3_Overflow

AddBCD_Nibble_3_Overflow:

	subi	r25, 0x0A
	ldi		r23, 0x10

	add		r25, r23
	ldi		r23, 0x00
	mov		r21, r25
	andi	r21, 0xF0
	cpi		r21, 0xA0
	brlo	AddBCD_No_Nibble_4_Overflow

AddBCD_Nibble_4_Overflow:

	subi	r25, 0xA0

AddBCD_No_Nibble_3_Overflow:	
AddBCD_No_Nibble_4_Overflow:	

	ret

; int8_t CosMulFastC(uint8_t angle, uint8_t distance)
;
; Returns the Cosine of the angle multiplied by the distance/2
;
; Inputs
;		Angle (0..255) in r24
;		Distance (0..127) in r22
; Returns 
;		cos(angle) * distabce as signed 8 bit value in r24
; Trashes
;		R0:1
;		R23
;		R24
;		R26:27

.global CosMulFastC
CosMulFastC:

	subi	r24, (-(64))			; COS is 90 degrees out of phase with SIN

.global SinMulFastC
SinMulFastC:

	clr		r27						
	mov		r26, r24				; Get the offset in the SIN table
	subi	r26, lo8(-(trigtable))	; Add the base address to the offset
    sbci 	r27, hi8(-(trigtable))
	ld		r23, X					; Read value from table into r24

	mulsu	r23, r22				; Multiply signed "sin(angle)" by unsigned "Distance*2"
	mov		r24, r1					; move signed 8 bit result into r24

	clr		r1						; restore "R1:<ZERO>" for C
	ret

; int8_t CosFastC(uint8_t angle)
;
; Returns the cosine of the angle
;
; Inputs
;		Angle (0..255) in r24
; Returns 
;		cos(angle) as signed 8 bit value in r24
; Trashes
;		R24
;		R26:27

.global CosFastC
CosFastC:

	subi	r24, (-(64))			; COS is 90 degrees out of phase with SIN

.global SinFastC
SinFastC:

	clr		r27						
	mov		r26, r24				; Get the offset in the SIN table
	subi	r26, lo8(-(trigtable))	; Add the base address to the offset
    sbci 	r27, hi8(-(trigtable))
	ld		r24, X					; Read value from table into r24
	ret


; r24 x
; r22 y
; r20 CharNo

; Trashes
; 


.global Mode7PutCharFastC
Mode7PutCharFastC:
	push	r28					; Save register used by counter <i>
	push	r14					; 						TempX
	push	r13					; 						TempY
	push	r12					; 						X_Backup
	push	r11					; 						Y_Backup
	push	r9					;						Z_Pointer_Backup_HI
	push	r8					;						Z_Pointer_Backup_LO

	mov		r12, r24			; Save X into X_Backup (r12) for later additions
	mov		r11, r22			; Save Y into Y_Backup (r11) for later additions

	ldi		r28, 0x20			; 32
	mul		r20, r28			; Multiply CharNum by 32

	movw	r30, r0				; Move CharNo*32 into Z

	subi	r30, lo8(-(VectFont))	; Add the base address to the offset
    sbci 	r31, hi8(-(VectFont))

	lpm		r24, Z+					; Get first X0 from flash
	lpm		r22, Z+					; Get first Y0 from flash

Mode7PutCharFastCLoop:

	lpm		r20, Z+					; Get first X1 from flash
	
	cpi		r20, 0xFF				; See if we have reached end of list (0xFF)
	breq	Mode7PutCharFastCEnd

	cpi		r20, 0xFE							; See if we have non consecutive points (0xFE)
	brne	Mode7PutCharFastCDontSkipPoint

	adiw	r30, 1					; and read a whole set of (x0, y0, x1, y1)
	lpm		r24, Z+
	lpm		r22, Z+
	lpm		r20, Z+

Mode7PutCharFastCDontSkipPoint:
	lpm		r18, Z+					; If we didn't have a broken line only need to read (y1)

	mov		r14, r20				; SAVE a copy of x1 and y1 so we don't need to read
	mov		r13, r18				; them from slow flash next loop

	add		r24, r12				; Add X_Backup and X0
	brcs	M7PCFCDontDraw			; if there is an overflow then don't "DrawLine"
	add		r22, r11
	brcs	M7PCFCDontDraw			; Ditto for Y0, X1 and Y1
	add		r20, r12
	brcs	M7PCFCDontDraw
	add		r18, r11
	brcs	M7PCFCDontDraw

	cpi		r22, 224				; Make sure Y0 and Y1 are not out of range
	brsh	M7PCFCDontDraw
	cpi		r18, 224
	brsh	M7PCFCDontDraw

	movw	r8, r30					; Save Z (gets trashed by DrawLine)
	rcall	LineMode7FastC			; Draw the line
	movw	r30, r8					; Restore Z

M7PCFCDontDraw:

	mov		r24, r14				; Copy X_Temp into X0
	mov		r22, r13				; Copy Y_Temp into Y0

	rjmp	Mode7PutCharFastCLoop


Mode7PutCharFastCEnd:
	pop		r8						; restore the trashed registers
	pop		r9
	pop		r11
	pop		r12
	pop		r13
	pop		r14
	pop		r28
	clr		r1
	ret





.macro CosMulFast ang dist result
	subi	\ang, (-(64))			; COS is 90 degrees out of phase with SIN
	SinMulFast \ang \dist \result
.endm

.macro SinMulFast ang dist result

	clr		r27						
	mov		r26, \ang				; Get the offset in the SIN table
	subi	r26, lo8(-(trigtable))	; Add the base address to the offset
    sbci 	r27, hi8(-(trigtable))
	ld		r17, X					; Read value from table into r24

	mulsu	r17, \dist				; Multiply signed "sin(angle)" by unsigned "Distance*2*Scale"
	mov		\result, r1				; move signed 8 bit result into r24
.endm




;r8:9	Z Backup
;r11 	Y_Backup
;r12 	X_Backup
;r13 	X_Temp
;r14 	Y_Temp
;r28 	i
;r30:31 FlashPointer

;r25	D0
;r23	T0
;r21	D1
;r19	T1

;r24 	X0
;r22 	Y0
;r20 	X1
;r18 	Y1

; 
;
;
; Inputs
;		r24 x
;		r22 y
;		r20 CharNo
;		r18 Theta
;		r16 Scale

DrawPolarObjectFastCEnd:
	pop		r8						; restore the trashed registers
	pop		r9
	pop		r11
	pop		r12
	pop		r13
	pop		r14
	pop		r15
	pop		r17
	pop		r28
	clr		r1
	ret

.global DrawPolarObjectFastC
DrawPolarObjectFastC:
	push	r28					; Save register used by counter <i>
	push	r17
	push	r15
	push	r14					; 						TempX
	push	r13					; 						TempY
	push	r12					; 						X_Backup
	push	r11					; 						Y_Backup
	push	r9					;						Z_Pointer_Backup_HI
	push	r8					;						Z_Pointer_Backup_LO

	mov		r12, r24			; Save X into X_Backup (r12) for later additions
	mov		r11, r22			; Save Y into Y_Backup (r11) for later additions
	mov		r15, r18			; Save Theta for later

	ldi		r28, 0x20			; 32
	mul		r20, r28			; Multiply CharNum by 32

	movw	r30, r0				; Move CharNo*32 into Z

	subi	r30, lo8(-(PolarObjects))	; Add the base address to the offset
    sbci 	r31, hi8(-(PolarObjects))

	lpm		r23, Z+					; Get first X0 from flash
	lpm		r25, Z+					; Get first Y0 from flash
	add		r25, r15				; Add on theta

DrawPolarObjectFastCLoop:

	lpm		r19, Z+					; Get first X1 from flash
	
	cpi		r19, 0xFF				; See if we have reached end of list (0xFF)
	breq	DrawPolarObjectFastCEnd

	cpi		r19, 0xFE							; See if we have non consecutive points (0xFE)
	brne	DrawPolarObjectFastCDontSkipPoint

	adiw	r30, 1					; and read a whole set of (x0, y0, x1, y1)
	lpm		r23, Z+
	lpm		r25, Z+
	add		r25, r15				; Add on theta
	lpm		r19, Z+

DrawPolarObjectFastCDontSkipPoint:
	lpm		r21, Z+					; If we didn't have a broken line only need to read (y1)
	add		r21, r15				; Add on theta

	mov		r14, r19				; SAVE a copy of x1 and y1 so we don't need to read
	mov		r13, r21				; them from slow flash next loop

	mul		r23, r16
	mov		r23, r1
	SinMulFast r25, r23, r24
	CosMulFast r25, r23, r22

	mul		r19, r16
	mov		r19, r1
	SinMulFast r21, r19, r20
	CosMulFast r21, r19, r18

	
	add		r24, r12				; Add X_Backup and X0
	add		r22, r11
	add		r20, r12
	add		r18, r11

	mov		r25, r24				; See if the ABS between X0 and X1 is greater than 150
	sub		r25, r20
	brcc	DPOFNoCarryABS
	neg		r25
DPOFNoCarryABS:
	cpi		r25, 150
	brsh	DPOFCDontDraw

	cpi		r22, 224				; Make sure Y0 and Y1 are not out of range
	brsh	DPOFCDontDraw
	cpi		r18, 224
	brsh	DPOFCDontDraw

	movw	r8, r30					; Save Z (gets trashed by DrawLine)
	rcall	bresh_line_asm			; Draw the line
	movw	r30, r8					; Restore Z

DPOFCDontDraw:

	mov		r23, r14				; Copy X_Temp into X0
	mov		r25, r13				; Copy Y_Temp into Y0

	rjmp	DrawPolarObjectFastCLoop

