; PROJECT:	LED Snake
; PURPOSE:	The code for the flex PCB
; DEVICE:	ATmega328p
; AUTHOR:	Daniel Raymond
; DATE:		2019-04-15

#include <prescalers.inc>

.org		0x0000					; Tells PC that reset is the 1st instruction
	rjmp	reset
.org		INT0addr
	rjmp	INT0_vect
.org		OVF1addr
	rjmp	TIMER1_OVF_vect

.def util		=	r16
.def addrs		=	r17
.def data		=	r18
.def looper		=	r19
.def headX		=	r20
.def headY		=	r21
.def headDir	=	r22
.def tailX		=	r23
.def tailY		=	r24
.def util2		=	r25

.equ PSR		=	1 << PB5		; Latch pin of the Power SR		(To tell it what SR it's talking to)
.equ GSR		=	1 << PB2		; Latch pin of the Ground SR

.equ PLtch		=	1 << PB5
.equ PData		=	1 << PB4
.equ PClk		=	1 << PB3
.equ GLtch		=	1 << PB2
.equ GData		=	1 << PB1
.equ GClk		=	1 << PB0

.equ upBtn		=	PD4
.equ downBtn	=	PD5
.equ leftBtn	=	PD6
.equ rightBtn	=	PD7

.equ LEFT		=	0b0
.equ RIGHT		=	0b1
.equ UP			=	0b10
.equ DOWN		=	0b100
.equ TRUE		=	1
.equ FALSE		=	0

.equ baseArray	=	0x100
.equ matrixWidth =	8

.dseg
.org baseArray
LEDs:
	.byte	matrixWidth	;	Reserves eight bits 

.org (baseArray + matrixWidth)
snakeMove:
	.byte	1		;	All the booleans we need to keep track of
appleEaten:
	.byte	1
btnPress:
	.byte	1
gameOver:
	.byte	1
appleX:				;	Coordinates of the apple
	.byte	1
appleY:
	.byte	1
mvIndex:
	.byte	1
snkLength:
	.byte	1
directions:
	.byte	64		;	Reserves the maximum possible number of direction we would ever need to care about
.cseg

reset:
	ldi	util,	(PLtch | PData | PClk | Gltch | GData | GClk)
	out DDRB,	util						; Sets all of the SR pins to output
	call		initVar
	call		initArray
	
	cli										; Disable global interrupt system while configuring
	rcall		T1Setup						; Sets up the hardware and timer interrupts
	rcall		INT0Setup
	sei										; Re-enable global interrupt

	call		spawnApple					; Spawn the first apple in the game 

  loop:
	ldi	ZH,		high(btnPress)				; Check if the button boolean has been triggered
	ldi	ZL,		low(btnPress)
	ld	data,	Z
	tst data								; The load instruction doesn't seem to set any of the flags...
	breq		skipChangeDir				; If btnPress is equal to zero, skip the method that polls the buttons
		call	changeDir					; Otherwise, change the direction of the snake
	skipChangeDir:

	ldi	ZH,		high(snakeMove)				; Check if the timer has triggered
	ldi	ZL,		low(snakeMove)
	ld	data,	Z
	tst data								; The load instruction doesn't seem to set any of the flags...
	breq		skipUpdate
	ldi	ZH,		high(gameOver)				; Check if the game is over
	ldi	ZL,		low(gameOver)
	ld	data,	Z
	tst data								; The load instruction doesn't seem to set any of the flags...
	brne		skipUpdate					; If not, it's time to update the page!
		ldi	util,	FALSE					; Set the snakeMove boolean to false
		ldi	ZH,		high(snakeMove)			
		ldi	ZL,		low(snakeMove)	
		st	Z,		util
		call		moveHead				; Move the head in the appropriate direction

		ldi	ZH,		high(appleEaten)		; If an apple has been eaten, skip moving the tail
		ldi	ZL,		low(appleEaten)
		ld	data,	Z
		tst data							; If the apple is eaten, skip moving the tail
		brne		skipTail				
		ldi	ZH,		high(gameOver)			; Check if the game is over (if it is, don't move the tail)
		ldi	ZL,		low(gameOver)
		ld	data,	Z
		tst data							; If the game is over, skip moving the tail
		brne		skipTail
		call		moveTail				; Function that moves the tail
	   skipTail:
		call		updateLength			; Update the position variables (Movement index, snake length, etc)
	skipUpdate:
	
	rcall		shiftArray					; Constantly displays what's in the LEDs array
  rjmp	loop
rjmp	reset

;*************************************************************************************************************************************** Snake Moving

moveHead:
	push util
	push util2
	push data
	
	cpi headDir,LEFT						; If the snake is going left...
	brne		f1
	cpi headX,	0							; ... and is not at the left most boundary...
	breq		f1
	dec	headX								; ... move the snake left!
	rjmp		doneMove					; Then jump to the end
   f1:
	cpi headDir,RIGHT						; If the snake is going right...
	brne		f2
	cpi headX,	7							; ... and is not at the right most boundary...
	breq		f2
	inc	headX								; ... move the snake right!
	rjmp		doneMove
   f2:
	cpi headDir,UP							; If the snake is going up...
	brne		f3
	cpi headY,	0							; ... and is not at the top boundary...
	breq		f3
	dec headY								; ... move the snake up!
	rjmp		doneMove
   f3:
	cpi headDir,DOWN						; If the snake is going down...
	brne		doneMove
	cpi headY,	7							; ... and is not at the bottom boundary...
	breq		doneMove
	inc	headY								; ... move the snake down!

   doneMove:
	ldi	ZH,		high(appleX)				; Grab the coordinates of the apple
	ldi	ZL,		low(appleX)	
	ld	util,	Z
	ldi	ZH,		high(appleY)
	ldi	ZL,		low(appleY)	
	ld	util2,	Z
	cp	headX,	util						; Compare the coordinates of the head with the coordinates of the apple
	cpc headY,	util2
	brne		skipEatApple
	ldi util,	TRUE						; Set appleEaten boolean to TRUE
	ldi	ZH,		high(appleEaten)
	ldi	ZL,		low(appleEaten)	
	ld	util,	Z
   skipEatApple:

	ldi	ZH,		high(LEDs)					; Look at the pixel that the snake is trying to move into
	ldi	ZL,		low(LEDs)	
	add	ZL,		headY
	ld	util,	Z							; Grab the row that the snake is going into
	ldi util2,	0x80						; Left move pixel possible
	mov	data,	headX
   shiftMask:
	tst	data
	breq		doneShifting				; Shift over 0x80 until util2 = 0x80 >> headX
	lsr util2
	dec	data
	rjmp		shiftMask
   doneShifting:
	and util,	util2
	breq		setLEDs						; Skip the lose function
	rcall		lose
	
   setLEDs:
	ldi	ZH,		high(LEDs)					; Look at the pixel that the snake is trying to move into
	ldi	ZL,		low(LEDs)	
	add	ZL,		headY
	ld	util,	Z
	or	util2,	util						; Combine the previous data with the new data
	ldi	ZH,		high(LEDs)
	ldi	ZL,		low(LEDs)
	add ZL,		headY						; Go down the proper number of rows
	st	Z,		util2						; Still holds 0x80 >> headX

	pop		data							; Restore the original value of the registers
	pop		util2
	pop		util
ret

moveTail:
	push data
	push util

	ldi	ZH,		high(mvIndex)
	ldi	ZL,		low(mvIndex)
	ld	data,	Z							; Sets data to the movement Index
	ldi	ZH,		high(directions)
	ldi	ZL,		low(directions)
	add ZL,		data						; Look at the mvIndex of the directions array
	ld	util,	Z							; util is now the current tail direction

	cpi util,	LEFT						; Increment/Decrement the appropriate coordinate for the tail
	brne		b1
	dec	tailX
	rjmp		doneMvTail
   b1:
	cpi util,	RIGHT
	brne		b2
	inc tailX
	rjmp		doneMvTail
   b2:
	cpi util,	UP
	brne		b3
	dec tailY
	rjmp		doneMvTail
   b3:
	cpi util,	DOWN
	brne		doneMvTail
	inc tailY

   doneMvTail:
	ldi	ZH,		high(directions)			; Store the current value of headDir into the directions at mvIndex
	ldi	ZL,		low(directions)
	add ZL,		data
	st	Z,		headDir

	ldi util2,	0x80						; Left move pixel possible
	mov	data,	tailX						; We are going to destroy that data
   shiftTailMask:							; Shift over 0x80 until util2 = 0x80 >> headX
	tst	data								; Count how many times we need to shift
	breq		clrLEDs						; Jump if we are done shifting
	lsr util2								; Move over the correct number of pixels
	dec	data
	rjmp		shiftTailMask				; Do it again

   clrLEDs:
	ldi	ZH,		high(LEDs)					; Load the current LEDs status into the data register
	ldi	ZL,		low(LEDs)					;	"
	add ZL,		tailY						; Go to the row at headY
	ld	data,	Z							;	"

	com util2								; We are going to zero the specified bit
	and data,	util2						;	"
	st	Z,		data

	pop util
	pop data
ret

;*************************************************************************************************************************************** Game Functions

changeDir:
	push util
	push data
	push looper
	push util2

	ldi util,	FALSE						; Turn the button press boolean off
	ldi	ZH,		high(btnPress)				;	"
	ldi	ZL,		high(btnPress)				;	"
	st	Z,		util						;	"

	ldi looper,	0x08						; Create a loop to read all 4 buttons
   readBtn:
   	in	util,	PINC						; Read in the current state of the buttons
	and util,	looper						; See if one of the buttons is pressed
	brne		doneRead					; If this is true, util now holds which button is pressed
	lsr looper
	brne		readBtn						; Done reading
   doneRead:
	mov	data,	util						; We are going to be destroying the new data
	add data,	headDir						; Add the previous and the new direction

	ldi	util2,	(UP+DOWN)					; If the sum of the new & old directions is = UP + DOWN...
	cpse data,	util2						; ... the snake is trying to backtrack
	rjmp		checkLR						; If it isn't backtracking, jump to change the direction
	rjmp		dontSetDir					; 

   checkLR:
	ldi util2,	(LEFT+RIGHT)				;	" " "
	cpse data,	util2						;	" " "
	mov headDir,util						; If neither are equal, set the headDir register to the new direction
						
   dontSetDir:
	pop util2
	pop looper
	pop data
	pop util
ret

updateLength:
	ldi	ZH,		high(appleEaten)			; Check if the apple is eaten
	ldi	ZL,		low(appleEaten)	
	st	Z,		util
	tst util
	breq		skipIncrLength				; If it is, increment the value in snkLength
	ldi	ZH,		high(snkLength)
	ldi	ZL,		low(snkLength)	
	ld	util,	Z
	inc util
	st	Z,		util

	ldi	ZH,		high(directions)			; Start of Z at directions[snkLength - 1]
	ldi	ZL,		low(directions)	
	add	ZL,		util
	
	dec	ZL									; Start off the array at one less than snake length
	ldi	util,	high(directions)
   shiftData:
	ld	data,	-Z							; Load in the data of directions[util - 1]
	inc ZL	
	st	Z,		data						; Store that data into directions[util]
	dec ZL									; Decrement the index
	cpi	ZL,		low(directions)
	cpc	ZH,		util						; Compare the upper nibble 
	brne		shiftData					; If we have reached the bottom of the array, we done.

	rcall		spawnApple
   skipIncrLength:
	
	ldi	ZH,		high(mvIndex)				; Retrieve the movement index
	ldi	ZL,		low(mvIndex)	
	ld	util,	Z

	ldi	ZH,		high(directions)			; look at the directions array
	ldi	ZL,		low(directions)
	add ZL,		util						; Go to directions[mvIndex]
	st	Z,		headDir						; Store the most recent head Direction in the open space (or over write the move we just did)

	inc util								; Increment the register holding mvIndex

	ldi	ZH,		high(snkLength)				; Retrieve the snkLength once again
	ldi	ZL,		low(snkLength)
	ld	data,	Z

	cp	util,	data						; Compare the mvIndex with the snkLength
	brne		skipClrMV
	clr	util								; Clear mvIndex if it is equal to the snkLength
   skipClrMV:
	ldi	ZH,		high(mvIndex)				; Store the mvIndex back into RAM
	ldi	ZL,		low(mvIndex)				;	"
	st	Z,		util						;	"
ret

spawnApple:
	push util
	push looper
	push data
	push util2

	ldi	util,	FALSE						; Set the appleEaten variable to false
	ldi ZH,		high(appleEaten)			;	"
	ldi	ZL,		low(appleEaten)				;	"
	st	Z,		util						;	"
	
	ldi looper,	2							; We are doing two conversions
   doubleConv:
	ldi util,	1 << ADEN | 1 << ADSC | 1 << ADPS1 | 1 << ADPS0
	sts ADCSRA,	util						; Start the conversion and set the prescaler
	ldi	util,	1 << ADC0D					; Turn of the digital capablities of PC0
	sts	DIDR0,	util						;	"

   waitConversion:  
	lds	util,	ADCSRA						; See if the conversion is complete
	andi util,	1 << ADIF					; Only look at the ADC Interrupt Flag
	breq		waitConversion				; If it isn't set, jump to continue to poll

	lds data,	ADCSRA						; We need to set the Flag bit to clear it (wack)
	sbr data,	1 << ADIF					;	"
	sts ADCSRA,	data						;	"

	lds	data,	ADCL						; Reading in all the data
	lds	util,	ADCH						; Required, but not used
	andi data,	0x07						; We only care about the 3 LSB

	dec looper								; We've done one conversion
	breq		setY						; If it's already done
	ldi ZH,		high(appleX)				; Set point to look at the X apple Coordinate
	ldi	ZL,		low(appleX)					;	"
	st	Z,		data						; Put the "random" number into the X coordinate
	rjmp		doubleConv

   setY:
	ldi ZH,		high(appleY)				; Set point to look at the Y apple Coordinates
	ldi	ZL,		low(appleY)					;	"
	st	Z,		data						; Put the "random" number into the Y coordinate

	ldi	ZH,		high(LEDs)					; Got to LEDs[appleY]
	ldi	ZL,		low(LEDs)					;	"
	add	ZL,		data						;	"					
	ld	util,	Z							;	"

	ldi	ZH,		high(appleX)				; Grab the X coordinate of the apple
	ldi	ZL,		low(appleX)					;	"			
	ld	looper,	Z							;	"
	ldi util2,	0x80						; Left move pixel possible
   shiftMask2:
	tst	looper
	breq		doneShifting2				; Shift over 0x80 until util2 = 0x80 >> appleX
	lsr util2
	dec	looper
	rjmp		shiftMask2
   doneShifting2:

	or util,	util2						; LED[appleY] | (0x80 >> appleX)

	ldi	ZH,		high(LEDs)					; Turn on the LED to represent the apple
	ldi	ZL,		low(LEDs)					;	"
	add ZL,		data						; Go to LEDs[appleY] one last time
	st	Z,		util

	pop util2
	pop data
	pop looper
	pop util
ret

lose:
	push util

	ldi	util,	TRUE						; Set the gameOver variable
	ldi	ZH,		high(gameOver)				;	"
	ldi	ZL,		low(gameOver)				;	"
	st	Z,		util						;	"

	ser util
	ldi	ZH,		high(LEDs)					; Start talking to the LED array
	ldi	ZL,		low(LEDs)					;	"
   setRow:
	st	Z+,		util						; Increment the row in question and set all the LEDs in that row
	cpi	ZL,		low(LEDs+matrixWidth)		; If the row is equal to the top row, we're done
	brne		setRow
	
	pop util
ret

;*************************************************************************************************************************************** Setup Functions

T1Setup:
	ldi	util,	T1ps256						; Set game refresh rate
	sts TCCR1B,	util
	ldi util,	1 << TOIE1					; Enable Timer1 overflow interrupt ability
	sts TIMSK1,	util
ret

INT0Setup:
	ldi util,	1 << ISC00 | 1 << ISC01		; INT0 interrupt to detect RISING edge
	sts EICRA,	util
	ldi util,	1 << INT0					; Enable 1st Ext. interrupt
	out EIMSK,	util
	ldi util,	1 << INTF0
	out EIFR,	util
ret

initArray:
	ldi util,	DOWN
	ldi	ZH,		high(directions)	
	ldi	ZL,		low(directions)
	st	Z+,		util
	st	Z+,		util
	st	Z,		util

	ldi	util,	0x0						; Sets the first pixel high for simplicity's sake
	ldi	ZH,		high(LEDs)	
	ldi	ZL,		low(LEDs)	
	st	Z,		util

	ldi	util,	3							; Set the initial starting length of the snake to 3
	ldi ZH,		high(snkLength)
	ldi	ZL,		low(snkLength)
	st	Z,		util
ret

initVar:
	ldi headDir,DOWN						; Sets the intial direction of travel
	ldi headX,	3							; Start the snake in the top left corner of the matrix
	ldi	headY,	-1
	ldi tailX,	3
	ldi	tailY,	-4
ret

;*************************************************************************************************************************************** SR Output

; Changes util, util2, data, addrs, & looper
shiftArray:
	push		util
	push		util2
	push		addrs
	push		data
	push		looper

	ldi	util2,	matrixWidth					; The start of a looping mask
   pwrLoop:
	dec	util2								; move onto the next address in the array
	clr data								; Turn off all the power pins so there is no overlap
	ldi addrs,	PSR
	rcall		shiftBits					

	clr addrs								; Dummy register for the cpse instruction to compare with
	ldi	data,	0x80						; Start creating the mask out of the data register
	mov util,	util2						; We need to preserve
   createMask:
	cpse util,	addrs						; If the counter is a zero, we don't want to shift the data
	lsr data								; Shift over the mask the appropriate number of times
	cpse util,	addrs
	dec util
	brne		createMask
	com data								; Invert the bits so only one pin is grounded
	ldi addrs,	GSR							; Talk to the Ground SR
	rcall		shiftBits					; Send out the ground data

	ldi	ZH,		high(LEDs)					; Start gathering the data for the Power SR
	ldi	ZL,		low(LEDs)
	add	ZL,		util2						; Find the right address in the array
	ld	data,	Z							; Read in the LED byte
	ldi addrs,	PSR							; Talk to the power SR
	rcall		shiftBits					; Send out the data

	tst	util2								; If the address has reached zero, we are done here
   brne	pwrLoop

	pop			looper
	pop			data
	pop			addrs
	pop			util2
	pop			util
ret

; Requires the "addrs" & the "data" registers to be set
shiftBits:
	ldi	looper,	1							; Setup the mask

	in	util,	PORTB						; Reads in the current state of the port
	com addrs								; We are going to clear
	and util,	addrs						; Zero the latch bit
	com addrs								; Get the bit back to normal
	out PORTB,	util						; Output the zeroed-latch
	lsr addrs								; Focus the bit on the clock pin
	lsr	addrs
  cycle:
	com addrs
	and util,	addrs						; Clear the clock bit
	com addrs								; Revert the data back
	out PORTB,	util						; Output the data (Clock low)

	mov	util,	data						; We are going to be destroying the byte info
	and	util,	looper						; And it with the shifting mask to isolate a bit
   breq	data0								; If the result is a zero, jump to cbi data pin

	in	util,	PORTB						; We used util for another thing, so we're setting it to the updated output
	lsl addrs								; Focus on the data pin now
	or	util,	addrs						; Set the data bit high
	out PORTB,	util						; Send the data out

	rjmp		setLoop						; Jump to finish the loop stuff
   data0:
	in	util,	PORTB						; Re-set util
	lsl addrs								; focus on the data bit
	com addrs								; Invert the data of pin to clr that bit
	and	util,	addrs						; Clear the data bit in the util register
	com addrs								; Revert the byte so that it's normal again
	out	PORTB,	util						; Send the sucker out
   setLoop:
	lsr	addrs								; Focus on the clock
	or	util,	addrs						; Set the clock high
	out PORTB,	util						; Update the output

	lsl			looper						; Shift over to the next bit
	brne		cycle						; If the mask has cycled over, keep looping

	lsl addrs								; Get back over to the latch
	lsl addrs
	or	util,	addrs						; Put the latch high
	out PORTB,	util
ret

;*************************************************************************************************************************************** Interrupt Vectors

INT0_vect:
	ldi	util,	TRUE
	ldi	ZH,		high(btnPress)				; Sets the btnPress boolean in SRAM
	ldi	ZL,		low(btnPress)	
	st	Z,		util
reti

TIMER1_OVF_vect:
	ldi	util,	TRUE
	ldi	ZH,		high(snakeMove)				; Sets the snakeMove boolean
	ldi	ZL,		low(snakeMove)	
	st	Z,		util
reti