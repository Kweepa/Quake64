Line drawing routine for installation into VIC-20. You can pick the asm out of this fairly easily.

10 POKE55,0:POKE56,60:CLR:FORT=15360TO15510:READA:POKET,A:NEXT
11 :
12 DATA 56,162,232,165,253,229,251,176,6,162,202,73,255,105,1,134,5,133,3,56,160,200
13 DATA 165,254,229,252,176,6,160,136,73,255,105,1,132,6,133,4,166,251,164,252,165,3
14 DATA 197,4,176,34,141,121,60,165,6,141,116,60,165,4,141,125,60,74,133,3,165,5,141
15 DATA 126,60,169,192,141,146,60,165,254,141,147,60,76,129,60,141,125,60,74,133,3,165
16 DATA 5,141,116,60,165,4,141,121,60,165,6,141,126,60,169,224,141,146,60,165,253,141
17 DATA 147,60,76,129,60,232,56,165,3,233,0,176,3,105,0,200,133,3,189,0,61,133,5,189,0
18 DATA 62,133,6,177,5,29,0,63,145,5,224,0,208,222,96
19 :
20 BI=128:FORX=0TO159
21 AD=4352+192*INT(X/8)
22 HI=INT(AD/256):LO=AD-256*HI
23 POKE15616+X,LO
24 POKE15872+X,HI
25 POKE16128+X,BI
26 BI=BI/2:IFBI<1THENBI=128
27 NEXT
28 :
29 @ON:@CLR
30 POKE251,RND(1)*160:REM X1
31 POKE252,RND(1)*192:REM Y1
32 POKE253,RND(1)*160:REM X2
33 POKE254,RND(1)*192:REM Y2
34 SYS15360
35 GETA$:IFA$=""THEN35
36 GOTO30


While doing so, I found the 'skeleton' of the main loop to be general enough that only a single copy was necessary (not two, as I originally had imagined). One of the self-modifications changes between CPX and CPY at the end of the loop as necessary, that had been the decisive factor in it.

The routine is remarkable in the sense that it manages to keep the X and Y co-ordinates as work values in the respective registers throughout the whole operation of the main loop - that is something you normally do not see in non-trivial 6502 code. Normally, you would always need to swap between the registers and (zero page) memory. Still the 6502 is missing a second accumulator, and that means the single accumulator has to hold the current bitmap byte value and the decision/error value in turns (and for a short time, also the low and high byte parts of the bit column address).

Yet, this routine still does a full address calculation for each pixel, even if that is extremely streamlined by avoiding shift and mask instructions during retrieval of the bitmap column pointer which would otherwise be helpful to keep the tables small.

To further improve on this, the crucial observation is that the Y indexed address mode already does half the job of calculating the effective address of the bitmap byte, and the bitmap column pointer only changes its value when the respective 8-pixel bitmap column is left to either side. Most of the time, the bitmap column pointer stays put so we only need to update it as necessary. Factoring out that part is one of the two necessary steps.

The second step is saving the time on the bit mask retrieval. Again, the routine here reads the bit mask from a table with an X indexed ORA instruction. However, while stepping along the line, the bit in the mask either stays put or changes its position one to the left or to the right (with possible wraparound). This can be streamlined by unrolling the main loop and providing 8 copies of the loop body, one for each position of the bit to be set (or reset), as immediate constant.

In the end, the main loop of the line routine changes from:


.Line_03
 INX            ; or DEX for x as main direction (or INY/DEY for y as main direction)
 SEC
 LDA accu
 SBC #&00       ; effectively, SBC #dy for x as main direction (or SBC #dx for y as main direction)
 BCS Line_04
 ADC #&00       ; effectively, ADC #dx for x as main direction (or ADC #dy for y as main direction)
 INY            ; or DEY for x as main direction (or INX/DEX for y as main direction)
.Line_04
 STA accu
.Line_05
 LDA Line_06,X
 STA scrn
 LDA Line_07,X
 STA scrn+1
 LDA (scrn),Y
 ORA Line_08,X
 STA (scrn),Y
 CPX #&00       ; effectively, CPX #x2 for x as main direction (or CPY #y2 for y as main direction)
 BNE Line_03
 
49.5/52.5 cycles/pixel

... (the comments show where the preparation part of the routine modifies the main loop) ...

to:


5.5     LDA (base),Y
  2     EOR #bit     ; ** or AND/ORA
  6     STA (base),Y
  2     DEX
  2     BEQ end
  3     LDA error
  3     SBC dy
3/2 +-- BCS
0/3 |   ADC dx
0/2 |   INY          ; ** or DEY
  3 +-> STA error

29.5/33.5 cycles/pixel

**) self-modifying code

The latter is one copy of the loop body for x as main direction, the loop body for y as main direction has these instructions slightly re-arranged. Both main loops contain 8 copies of the loop body (i.e. they have been "unrolled 8 times") to cover all bit positions within a byte.

The X register now has its role changed from keeping the X co-ordinate to counting down the number of remaining pixels. If that number becomes 0, one of the "BEQ end" instructions is executed to terminate the loop. That is another small optimization as it saves one cycle per pixel in most cases. Furthermore, DEX does not change the carry flag (as do the CPX or CPY instructions in the former routine) so it is not necessary to do a SEC to prepare the SBC instruction in the Bresenham step. It is only necessary to enter the main loop with the C flag set once (actually, when the bitmap column pointer is adjusted, the state of the C flag needs to be kept in mind as well).

Adjusting the bitmap column pointer weighs in with 23 cycles, at most for every 8th pixel (less often so for y as main direction), so this adds in another 3 cycles per pixel at worst. In the end, the average number of cycles per pixel goes down from 51 cycles to 31.5(+3) cycles for the faster implementation, resulting in ~50 % more speed.

As the full address calculation of the bitmap column pointer is only done once, the tables can be kept small: only 20 entries for the low and high bytes each (assuming 160 pixels horizontal width for the bitmap, as used by MINIGRAFIK). The bit position table is not anymore necessary as it is now 'contained' within the immediate fields of the ORA/AND/EOR instructions. Another small improvement in play: the line is always drawn left to right - this is always possible by exchanging the line ends, should x2 be less than x1.

What does not carry over is using immediate operands for the SBC and ADC instructions - modifying these would require to change their operand fields for all 8 copies of the loop body in the relevant main loop. During init, this would incur an extra cost of at least 64 cycles (for 16 STA ABS instructions) which needs a line of at least 32 pixels length to break even.

All that needs to be done now is preparing the relevant of the two main loops with the correct instructions for stepping along the y axis (either INY or DEY), at 8 places. When the draw action is changed between set, reset or invert, also those corresponding instructions, possibly also their operands need be modified. My faster routine takes care to only do these modifications when they are really necessary. If one disregards the change of draw action, the setup part still only takes about the same time on average as the setup part of the former routine (150 cycles vs 130 cycles).

...

That being said, this faster routine now sits at a sweet spot of being quite fast with 30000 pixels/second while still being less than 1 KB in size. Any further improvement in speed to the direction of 20 cycles/pixel (as pondered about by me earlier in this thread) likely needs an exuberant increase in code size to cover all the definitions by cases. If the flexibility to change the draw action is still supposed to be kept, I would estimate it at about 10 KB or more, which IMO makes such a routine unfit for general use.