;****************************************************************************
;*                        BASIC-52 V1.31 enhancements                       *
;*          The following code enhanced BASIC-52 with new commands          *
;*               for I2C communicatin and read / write to SFR               *
;*--------------------------------------------------------------------------*
;* (C) H.-J. Boehling & D. Wulf 14.11.01                                    *
;*     http://home.arcor.de/h.boehling                                      *
;*     H-Boehling@gmx.de                                                    *
;****************************************************************************
;*
;* Four new I2C communication commands as I2C-bus master.
;*
;* The syntax to use is:
;*
;*     I2CSTART           Sends a start condition to I2C bus.
;*                        - Returns with busy, time out or status clear.  
;*     I2CSTOP            Sends a stop condition to I2C bus.
;*                        - Returns with time out or status clear.
;*     I2CPUT [byte]      Sends a byte to the I2C bus.
;*                        - Returns with time out, no acknowledge or clear.
;*     I2CGET [variable]  Reads a byte from I2C to a BASIC variable.
;*                        - Set 18H (status) to 1 to send no acknowledge:
;*                           DBY(18H) = 1 : I2CGET B : I2CSTOP : PRINT B
;*                        - Returns with time out or status clear. 
;*   
;* Register 18H is the I2C communication status register; useage is:
;*
;*     STATUS=DBY(18H)
;*      IF STATUS.AND.2=2 PRINT "Time out error!"
;*      IF STATUS.AND.4=4 PRINT "Busy error!"
;*      IF STATUS.AND.8=8 PRINT "No acknowlege error!"
;*
;*---------------------------------------------------------------------------
;*
;* Two new commands to read from or write to a special funkton register:
;*
;*     WRSFR ([address]) [byte]      Writes to a special funkton register.
;*
;*     RDSFR ([address]) [variable]  Reads from a special funkton register.
;*
;* [address] is the address of the SFR and had to be a value between 
;* 128 (080H) and 255 (0FFH).
;*
;****************************************************************************

;----- Definitions ----------------------------------------------------------

SDA		bit	P1.6                    ;I2C serial data line.
SCL		bit	P1.5                    ;I2C serial clock line.

status		equ	018H			;Communication status.

temp1		equ	11			;Temp. storage.

xbit		bit	45			;Command extension present.
 
; the following bits will be set in the status byte:

tout		equ	00000010B		;I2C time out status.
busy		equ	00000100B		;I2C bus busy status.
nack		equ	00001000B		;Slave sends no acknowledge.
						
;----------------------------------------------------------------------------
; The following code is necessary to notify the new statements to BASIC.

		org	2002H			;5Ah at 2002h tells BASIC-52
		db	5AH			;to call 2048h (see below).
		org	2048H			;Set bit 45 to tell BASIC-52
						;that custom commands or
		setb	xbit			;instructions have been
		ret				;added.
		org	2070H			;Store starting address of
		mov	dptr,#vectortable	;vector table.
		ret
		org	2078H			;Store starting address of
		mov	dptr,#tokentable	;token table.
		ret

; The old code for BASIC-52 V1.3 overwrite 2090H, but this address had to be
; used for a user reset routine! So the code now starts at here:

;===== Here starts the code for the new BASIC statements ====================

		org	2400h			;use any available address

vectortable:					;Vector table starts here.
						;Label to branch on:
		dw	i2cstart		;I2CSTART command
		dw	i2cstop			;I2CSTOP command
		dw	i2cput			;I2CPUT command
		dw	i2cget			;I2CGET command
		dw	wrsfr			;WRSFR command
		dw	rdsfr			;RDSFR command

tokentable:					;Token table starts here.
		db	10H			;1. user defined token for
                db      'I2CSTART'              ;command name.
		db	0			;End of token indicator
		db	11H			;2.
                db      'I2CSTOP'
		db	0
		db	12H			;3.
                db      'I2CPUT'
		db	0
		db	13H			;4.
                db      'I2CGET'
		db	0
                db      14H                     ;5.
                db      'WRSFR'
		db	0
                db      15H                     ;6.
                db      'RDSFR'
		db	0

;----- The following is necessary to get no problem with variable names -----

		db	0DFH			;Dummy token.
		db	07FH			;Unused dummy char.

;----------------------------------------------------------------------------

		db	0FFH			;End of tokenlist indicator.

;----------------------------------------------------------------------------

;===== i2cstart - sends an I2C start condition to beginn communication ======

i2cstart:	call	SCLhigh			;Set SCL to high.
		mov	R7,#4			;Load time out counter.
setSDA:		setb	SDA			;Set SDA to high.
		jb	SDA,ishigh		;If not high bus is busy.
		djnz	R7,setSDA		;If not try until R7 is zero.
		orl	status,#busy		;Set busy status.
		ret				;return to BASIC.

ishigh:		clr	SDA			;Set start condition.
		anl     status,#0		;Clear I2C status.
 		ret				;return to BASIC.

;===== i2cstop - sends an I2C stop condition to end communication ===========

i2cstop:	anl 	status,#0		;Clear I2C status.
		clr	SDA			;Get SDA ready for stop.
		acall 	SCLhigh			;Set clock for stop.
           	acall	delay			;Delay 4 machine cycles.
		setb	SDA			;Set stop condition.
		ret				;Return to BASIC.

;===== i2cput - sends a byte from a BASIC value out to the I2C bus ==========

;----- Get value and test for 8 bit only ------------------------------------

i2cput:		mov	A,#39H			;Put value to send on
		lcall	30H			;argument stack.
		mov	A,#1			;change value to 16 bit
		lcall	30H			;integer and write to R3:R1
		cjne	R3,#0,i2cerror		;If R3 not zero	then 
						;value bigger than 0FFH.
						;8 bit integer only error.

;----- Send byte to I2C bus -------------------------------------------------

		mov	A,R1			;Load byte to send.
		mov	R6,#8			;Load bit counter
send:		clr	SCL			;Make clock low
           	acall	delay			;Delay 4 machine cycles.
		rlc	A			;Rotate data bit to C.
		mov	SDA,C			;Put data bit on pin.
		acall	SCLhigh		        ;Send clock.
           	acall	delay			;Delay 4 machine cycles.
		djnz	R6,send			;Repeat until all bits sent.

;----- Read acknowledge from slave ------------------------------------------
	
		clr	SCL			;Make clock low.
           	acall	delay			;Delay 4 machine cycles.
		setb	SDA			;Release line for acknowledge.
		acall	SCLhigh		        ;Send clock for acknowlege.
	     	acall	delay			;Delay 4 machine cycles.
		jnb	SDA,ackok		;Check for valid acknowledge.
		orl	status,#nack		;Set no acknowledge status.
ackok:		clr	SCL			;Finish acknowledge bit.
		ret				;Return to BASIC.

;===== i2cget - Reads one byte from I2C bus to the argument stack ===========

i2cget:		mov	R6,#8			;Load bit counter
read:		clr	SCL			;Make clock low.
              	acall	delay			;Delay 4 machine cycles.
		acall	SCLhigh		        ;Send clock.
	   	acall	delay			;Delay 4 machine cycles.
		mov	C,SDA			;Get data bit from pin.
		rlc	A			;Rotate bit into result byte.
		djnz	R6,read			;Repeat until all received.

;----- Put received byte on argument stack ----------------------------------

		mov	R0,A			;Load R0 with reseived byte.
		mov	R2,#0			;Set high byte to zero.
		mov	A,#9AH			;Put byte on argument stack
		lcall	30H			;with BASIC funktion.

;----- Send acknowledge to slave --------------------------------------------

		clr	SCL			;Set clock low.
           	acall	delay			;Delay 4 machine cycles.
		mov	A,status		;Load acknowledge bit
		rrc	A			;into C and
		mov	SDA,C			;send acknowledge bit.
		acall	SCLhigh		        ;Send acknowledge clock.

;----- Set variable to received byte ----------------------------------------

		mov	A,#43H			;Set next variable to value
		ljmp	30H			;on argument stack and
						;return to BASIC.

;----- delay - generates a delay of 4 machine cycles ------------------------

delay:		ret				;4 cycles for CALL and RET.

;----- SCLhigh - sends SCL pin high and waits for any clock stretching ------

SCLhigh:	mov	R7,#4			;Load time out counter.
setSCL:	   	setb	SCL			;Set SCL to high.
	       	jb	SCL,quit		;If SCL actually high return.
		djnz	R7,setSCL		;If not try until R7 is zero.
		orl	status,#tout		;Set status time out.
quit:		ret

;----- error - sends an error message to the terminal -----------------------

i2cerror:	mov	A,#7			;Send CR/LF
		lcall	30H
		mov	R3,#high i2cerrmsg	;Set string address.
		mov	R1,#low i2cerrmsg
error:		setb	34H			;Read string from code memory.
		mov	A,#6			;Send String to
		lcall	30H			;terminal.
		clr	A
		ljmp	30H			;Back to command mode.

i2cerrmsg:      db 'ERROR: BAD I2CPUT ARGUMENT'
		db	22H			;End of text.  	

sfrerrmsg:      db 'ERROR: BAD SFR ARGUMENT'
		db	22H			;End of text.

sfrerror:	mov	A,#7			;Send CR/LF
		lcall	30H
		mov	R3,#high sfrerrmsg	;Set string address.
		mov	R1,#low sfrerrmsg
		sjmp	error

;===== rdsfr - read from special funtion register ==========================

rdsfr:		mov     A,#39H                  ;Put address from text to
		lcall	30H			;argument stack.

		mov	A,#1			;change value to 16 bit
		lcall	30H			;integer and write to R3:R1

		cjne	R3,#0,sfrerror		;If R3 not zero	then error.
		mov	A,R1			;Address to Acc.
		jnb	Acc.7,sfrerror		;If address less then 80H! 
		mov	R4,A			;Address to R4.

		mov	DPL,#low sfrgettab	;Set DPTR to jump
		mov	DPH,#high sfrgettab	;table.
		call	do_sfr			;Read SFR.

		mov	R0,A			;Load R0 with SFR byte.
		mov	R2,#0			;Set high byte to zero.
		mov	A,#9AH			;Put byte on argument stack
		lcall	30H

;----- Set variable to SFR byte ---------------------------------------------

		mov	A,#43H			;Set next variable to value
		ljmp	30H			;on argument stack and
						;return to BASIC.

;===== wrsfr - write to special funtion register ============================

wrsfr:		mov     A,#39H                  ;Put address from text to
		lcall	30H			;argument stack.

		mov	A,#1			;change value to 16 bit
		lcall	30H			;integer and write to R3:R1
		cjne	R3,#0,sfrerror		;If R3 not zero	then error
		mov	A,R1			;or
		jnb	Acc.7,sfrerror		;if address less then 80H! 
		mov	temp1,R1		;Save address.

		mov	A,#39H			;Put value to write on
		lcall	30H			;argument stack.

		mov	A,#1			;change value to 16 bit
		lcall	30H			;integer and write to R3:R1
		cjne	R3,#0,sfrerror		;If R3 not zero	then 
						;8 bit integer only error.
		mov	DPL,#low sfrputtab	;Set DPTR to jump
		mov	DPH,#high sfrputtab	;table.
		mov	R4,temp1		;Address to write to R4.

;----- do_sfr - read from or wright to SFR ----------------------------------

;----- Calculate the jump ---------------------------------------------------

do_sfr:		mov	A,R4			;Address to Acc
		add	A,#80H
		mov	R4,A
		mov	R0,#0
		add	A,ACC			;*2
		xch	A,R0
		addc	A,ACC			;carry
		xch	A,R0
		add	A,ACC			;*4
		xch	A,R0
		addc	A,ACC			;carry
                xch     A,R0

;----- Load DPTR with offset and jump ---------------------------------------

                add     A,DPL
		mov	DPL,A
		mov	A,R0
		addc	A,DPH
		mov	DPH,A
		mov	A,R4
		jmp	@A+DPTR			;Jump into table.

;----- The direct addressing table ------------------------------------------

sfrputtab:	mov	128,R1
sfrgettab:	mov	A,128
		ret
		mov	129,R1
		mov	A,129
		ret
		mov	130,R1
		mov	A,130
		ret
		mov	131,R1
		mov	A,131
		ret
		mov	132,R1
		mov	A,132
		ret
		mov	133,R1
		mov	A,133
		ret
		mov	134,R1
		mov	A,134
		ret
		mov	135,R1
		mov	A,135
		ret
		mov	136,R1
		mov	A,136
		ret
		mov	137,R1
		mov	A,137
		ret
		mov	138,R1
		mov	A,138
		ret
		mov	139,R1
		mov	A,139
		ret
		mov	140,R1
		mov	A,140
		ret
		mov	141,R1
		mov	A,141
		ret
		mov	142,R1
		mov	A,142
		ret
		mov	143,R1
		mov	A,143
		ret
		mov	144,R1
		mov	A,144
		ret
		mov	145,R1
		mov	A,145
		ret
		mov	146,R1
		mov	A,146
		ret
		mov	147,R1
		mov	A,147
		ret
		mov	148,R1
		mov	A,148
		ret
		mov	149,R1
		mov	A,149
		ret
		mov	150,R1
		mov	A,150
		ret
		mov	151,R1
		mov	A,151
		ret
		mov	152,R1
		mov	A,152
		ret
		mov	153,R1
		mov	A,153
		ret
		mov	154,R1
		mov	A,154
		ret
		mov	155,R1
		mov	A,155
		ret
		mov	156,R1
		mov	A,156
		ret
		mov	157,R1
		mov	A,157
		ret
		mov	158,R1
		mov	A,158
		ret
		mov	159,R1
		mov	A,159
		ret
		mov	160,R1
		mov	A,160
		ret
		mov	161,R1
		mov	A,161
		ret
		mov	162,R1
		mov	A,162
		ret
		mov	163,R1
		mov	A,163
		ret
		mov	164,R1
		mov	A,164
		ret
		mov	165,R1
		mov	A,165
		ret
		mov	166,R1
		mov	A,166
		ret
		mov	167,R1
		mov	A,167
		ret
		mov	168,R1
		mov	A,168
		ret
		mov	169,R1
		mov	A,169
		ret
		mov	170,R1
		mov	A,170
		ret
		mov	171,R1
		mov	A,171
		ret
		mov	172,R1
		mov	A,172
		ret
		mov	173,R1
		mov	A,173
		ret
		mov	174,R1
		mov	A,174
		ret
		mov	175,R1
		mov	A,175
		ret
		mov	176,R1
		mov	A,176
		ret
		mov	177,R1
		mov	A,177
		ret
		mov	178,R1
		mov	A,178
		ret
		mov	179,R1
		mov	A,179
		ret
		mov	180,R1
		mov	A,180
		ret
		mov	181,R1
		mov	A,181
		ret
		mov	182,R1
		mov	A,182
		ret
		mov	183,R1
		mov	A,183
		ret
		mov	184,R1
		mov	A,184
		ret
		mov	185,R1
		mov	A,185
		ret
		mov	186,R1
		mov	A,186
		ret
		mov	187,R1
		mov	A,187
		ret
		mov	188,R1
		mov	A,188
		ret
		mov	189,R1
		mov	A,189
		ret
		mov	190,R1
		mov	A,190
		ret
		mov	191,R1
		mov	A,191
		ret
		mov	192,R1
		mov	A,192
		ret
		mov	193,R1
		mov	A,193
		ret
		mov	194,R1
		mov	A,194
		ret
		mov	195,R1
		mov	A,195
		ret
		mov	196,R1
		mov	A,196
		ret
		mov	197,R1
		mov	A,197
		ret
		mov	198,R1
		mov	A,198
		ret
		mov	199,R1
		mov	A,199
		ret
		mov	200,R1
		mov	A,200
		ret
		mov	201,R1
		mov	A,201
		ret
		mov	202,R1
		mov	A,202
		ret
		mov	203,R1
		mov	A,203
		ret
		mov	204,R1
		mov	A,204
		ret
		mov	205,R1
		mov	A,205
		ret
		mov	206,R1
		mov	A,206
		ret
		mov	207,R1
		mov	A,207
		ret
		mov	208,R1
		mov	A,208
		ret
		mov	209,R1
		mov	A,209
		ret
		mov	210,R1
		mov	A,210
		ret
		mov	211,R1
		mov	A,211
		ret
		mov	212,R1
		mov	A,212
		ret
		mov	213,R1
		mov	A,213
		ret
		mov	214,R1
		mov	A,214
		ret
		mov	215,R1
		mov	A,215
		ret
		mov	216,R1
		mov	A,216
		ret
		mov	217,R1
		mov	A,217
		ret
		mov	218,R1
		mov	A,218
		ret
		mov	219,R1
		mov	A,219
		ret
		mov	220,R1
		mov	A,220
		ret
		mov	221,R1
		mov	A,221
		ret
		mov	222,R1
		mov	A,222
		ret
		mov	223,R1
		mov	A,223
		ret
		mov	224,R1
		mov	A,224
		ret
		mov	225,R1
		mov	A,225
		ret
		mov	226,R1
		mov	A,226
		ret
		mov	227,R1
		mov	A,227
		ret
		mov	228,R1
		mov	A,228
		ret
		mov	229,R1
		mov	A,229
		ret
		mov	230,R1
		mov	A,230
		ret
		mov	231,R1
		mov	A,231
		ret
		mov	232,R1
		mov	A,232
		ret
		mov	233,R1
		mov	A,233
		ret
		mov	234,R1
		mov	A,234
		ret
		mov	235,R1
		mov	A,235
		ret
		mov	236,R1
		mov	A,236
		ret
		mov	237,R1
		mov	A,237
		ret
		mov	238,R1
		mov	A,238
		ret
		mov	239,R1
		mov	A,239
		ret
		mov	240,R1
		mov	A,240
		ret
		mov	241,R1
		mov	A,241
		ret
		mov	242,R1
		mov	A,242
		ret
		mov	243,R1
		mov	A,243
		ret
		mov	244,R1
		mov	A,244
		ret
		mov	245,R1
		mov	A,245
		ret
		mov	246,R1
		mov	A,246
		ret
		mov	247,R1
		mov	A,247
		ret
		mov	248,R1
		mov	A,248
		ret
		mov	249,R1
		mov	A,249
		ret
		mov	250,R1
		mov	A,250
		ret
		mov	251,R1
		mov	A,251
		ret
		mov	252,R1
		mov	A,252
		ret
		mov	253,R1
		mov	A,253
		ret
		mov	254,R1
		mov	A,254
		ret
		mov	255,R1
		mov	A,255
		ret

;----------------------------------------------------------------------------

		end

