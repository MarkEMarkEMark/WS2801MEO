/* Adapted by MEO for WS2801 LED bulb string 
Programmed for the Due - so 100+ bulbs and fast frame rates now possible! */

/* ToDo: Functionallity
	- Frame rate controlled by potentiometer
	- buttons to change programs / variations / choose random / switch off


/* ToDo: Patterns Ideas

- Standard old fashioned lights twinkle. A random 25% fade on in 2 seconds, and stay of for 10 seconds and then fade off

- rainbow fade: (https://www.youtube.com/watch?v=xTkiNIJkWrY   end of http://www.youtube.com/watch?v=9wZhDc0PnWg)
  primary/secondary colours from 255 to 0 brightness before next colour

- various from: https://www.youtube.com/watch?v=zMKf98MpaUg / http://www.youtube.com/watch?v=w557LuVueXg&feature=player_embedded

- flames (flag?? R/Y)

*/


// THIS PROGRAM *WILL* *NOT* *WORK* ON REALLY LONG LED STRIPS.  IT USES
// AN INORDINATE AMOUNT OF RAM IN ORDER TO ACHIEVE ITS BUTTERY-SMOOTH
// ANIMATION.  See the 'strandtest' sketch for a simpler and less RAM-
// intensive example that can process more LEDs (100+).

// Example to control LPD8806-based RGB LED Modules in a pixelString; originally
// intended for the Adafruit Digital Programmable LED Belt Kit.
// ALSO REQUIRES WS2801 LIBRARY, which should be included with this code.

// I'm generally not fond of canned animation patterns.  Wanting something
// more nuanced than the usual 8-bit beep-beep-boop-boop pixelly animation,
// this program smoothly cycles through a set of procedural animated effects
// and transitions -- it's like a Video Toaster for your waist!  Some of the
// coding techniques may be a bit obtuse (e.g. function arrays), so novice
// programmers may have an easier time starting out with the 'strandtest'
// program also included with the LPD8806 library.


/* More info gleaned from pburgess

Most days I can't make heads or tails of that sketch, and I'm the one who wrote it! 
Needlessly over-engineered banned, was trying to show off to the ladies or something. :) 
But I digress! Here's a few tips I can offer:

The program distinguishes between "effects" (which generate the RGB colors for one frame of 
animation) -- there's a separate function for each one -- and "alpha" functions, which 
generate essentially a grayscale compositing mask (also animated) for transitions between 
effects. At any given time, there are two effects (a "back" and a "front") and one transition 
curretly in flight. When a transition has run its course, the "front" image then becomes the 
"back" and a new front effect and transition are randomly chosen.

The 'fxIntVars' array exists to hold information about the current effects and transition (since 
both the front and back image could be using the same effect simultaneously, static variables 
wouldn't do, so this was sort of a compromise). The first element is always a flag indicating 
whether the effect has been initialized, and if so, the other elements then contain parameters 
relating to the specific effect. (renderEffect00() is a good simple example of the 
initialization flag being used...this effect has no other parameters, so the other elements 
aren't used). I just used a block of 16-bit integers for holding all this stuff, since most of 
the math stuff is fixed-point, and made it a lot bigger than is really needed, allowing for 
some future expansion if I'm ever foolish enough to attempt that. */

#include "SPI.h"
#include "DriverWS2801.h"

#define pgm_read_byte(x) (*(x))
#define NUM_PIXELS 100
#define FRAMES_PER_SECOND 240

// You can also use hardware SPI for ultra-fast writes by omitting the data
// and clock pin arguments.  This is faster, but the data and clock are then
// fixed to very specific pin numbers: on Arduino 168/328, data = pin 11,
// clock = pin 13.  On Mega, data = pin 51, clock = pin 52. SPI 3(c) & 4(d) on Due
DriverWS2801 pixelString = DriverWS2801(NUM_PIXELS);

// Principle of operation: at any given time, the LEDs depict an image or
// animation effect (referred to as the "back" image throughout this code).
// Periodically, a transition to a new image or animation effect (referred
// to as the "front" image) occurs.  During this transition, a third buffer
// (the "alpha channel") determines how the front and back images are
// combined; it represents the opacity of the front image.  When the
// transition completes, the "front" then becomes the "back," a new front
// is chosen, and the process repeats.
byte imgData[2][NUM_PIXELS * 3],	// Data for 2 pixelStrings worth of imagery
	alphaMask[NUM_PIXELS],			// Alpha channel for compositing images
	backImgIdx = 0,					// Index of 'back' image (always 0 or 1)
	fxIdx[3];						// Effect # for back & front images + alpha
int fxIntVars[3][14],				// Effect instance variables (explained later)
	tCounter   = -1,				// Countdown to next transition
	transitionTime;					// Duration (in frames) of current transition
float fxFltVars[3][1];				// MEO: float variables
int32_t fxI32Vars[3][3];			// MEO: int32 variables
uint16_t fxI16Vars[3][1];			// MEO: uint16 variables
uint8_t fxI8Vars[3][1],				// MEO: uint8 variables
		frameDelay[3],				// MEO: if too fast - can set number of frames to pause
		frame[3];					// MEO: counter for frameDelay

// function prototypes, leave these be :)
void ProgramSolidColor(byte idx);		//pburgess
void ProgramRotatingRainbow(byte idx);	//pburgess
void ProgramSineWave(byte idx);			//pburgess
void ProgramWavyFlag(byte idx);			//pburgess
void ProgramPulse(byte idx);			//elmerfud
void ProgramLarsonOne(byte idx);		//elmerfud
void ProgramPhasing(byte idx);			//MEO
void ProgramRandomStrobe(byte idx);		//MEO
void ProgramSimplexNoise(byte idx);		//MEO & happyinmotion
void ProgramChaser(byte idx);			//MEO & Paul Martis
void ProgramFlames(byte idx);			//MEO & By Christopher De Vries
void ProgramLarsonTwo(byte idx);		//MEO

// Chaser functions
void set_color(uint8_t bulb, long color, byte idx);
void fill_sequence(uint8_t count, uint16_t sequence,
                               uint8_t span_size, int startColor, long (*sequence_func)(uint16_t sequence, int startColor), byte idx);

// Crossfade functions
void crossfadeSimple(void);
void crossfadeWipe(void);
void crossfadeDither(void);

void renderAlpha03(void);
void callback();
byte getGamma(byte x);
long hsv2rgb(long h, byte s, byte v, int wheelLine);
char fixSin(int angle);
char fixCos(int angle);


//	Arduino Due Timer code by Sebastian Vik & cmaglie
//		example: startTimer(TC1, 0, TC3_IRQn, 40)
//		TC1 : timer counter. Can be TC0, TC1 or TC2
//		0   : channel. Can be 0, 1 or 2
//		TC3_IRQn: irq number. See table.
//		40  : frequency (in Hz)
//			The interrupt service routine is TC3_Handler. See table.
//			Paramters table:
//				TC	 Channel	ISR/IRQ		  Handler Func		Due Pins
//				==	 =======	=======		  ======= ====		===	====
//				TC0, 0,			TC0_IRQn  =>  TC0_Handler()		2, 13
//				TC0, 1,			TC1_IRQn  =>  TC1_Handler()		60, 61
//				TC0, 2,			TC2_IRQn  =>  TC2_Handler()		58
//				TC1, 0,			TC3_IRQn  =>  TC3_Handler()		none (used here for lights)
//				TC1, 1,			TC4_IRQn  =>  TC4_Handler()		none (
//				TC1, 2,			TC5_IRQn  =>  TC5_Handler()		none
//				TC2, 0,			TC6_IRQn  =>  TC6_Handler()		4, 5
//				TC2, 1,			TC7_IRQn  =>  TC7_Handler()		3, 10
//				TC2, 2,			TC8_IRQn  =>  TC8_Handler()		11, 12
void startTimer(Tc *tc, uint32_t channel, IRQn_Type irq, uint32_t frequency) {
  pmc_set_writeprotect(false);
  pmc_enable_periph_clk((uint32_t)irq);
  TC_Configure(tc, channel, TC_CMR_WAVE | TC_CMR_WAVSEL_UP_RC | TC_CMR_TCCLKS_TIMER_CLOCK4);
  uint32_t rc = VARIANT_MCK/128/frequency; //128 because we selected TIMER_CLOCK4 above
  TC_SetRA(tc, channel, rc/2); //50% high, 50% low
  TC_SetRC(tc, channel, rc);
  TC_Start(tc, channel);
  tc->TC_CHANNEL[channel].TC_IER=TC_IER_CPCS;
  tc->TC_CHANNEL[channel].TC_IDR=~TC_IER_CPCS;
  NVIC_EnableIRQ(irq);
}


// List of image effect and alpha channel rendering functions; the code for
// each of these appears later in this file.  Just a few to start with...
// simply append new ones to the appropriate list here:
void (*renderEffect[])(byte) = {
	//ProgramSolidColor,
	//ProgramRotatingRainbow,
	//ProgramSineWave,
	//ProgramWavyFlag, //affected by fixSin/fixCos issue
	//ProgramPulse,
	//ProgramLarsonOne,
	//ProgramPhasing,
	//ProgramSimplexNoise, //not bright
	//ProgramRandomStrobe,
	//ProgramFlames,
	//ProgramChaser,
	ProgramLarsonTwo},
	(*renderAlpha[])(void)  = {
		//crossfadeDither,
		//crossfadeWipe,
		crossfadeSimple};

		// ---------------------------------------------------------------------------

void setup() {
	// Open serial communications and wait for port to open:
	Serial.begin(115200);

	// Start up the LED pixelString.  Note that pixelString.show() is NOT called here --
	// the callback function will be invoked immediately when attached, and
	// the first thing the calback does is update the pixelString.
	pixelString.begin();

	// Initialize random number generator from a floating analog input.
	randomSeed(analogRead(0));
	memset(imgData, 0, sizeof(imgData)); // Clear image data
	fxIntVars[backImgIdx][0] = 1;           // Mark back image as initialized

	//Timer function re-written for Ardunino Due
	startTimer(TC1, 2, TC5_IRQn, FRAMES_PER_SECOND);
}

void loop() {
	// Do nothing.  All the work happens in the TC3_Handler() function below,
	// but we still need loop() here to keep the compiler happy.
}


// Timer interrupt handler.
void TC5_Handler() {
  // You must do TC_GetStatus to "accept" interrupt
  // As parameters use the first two parameters used in startTimer (TC1, 0 in this case)
  TC_GetStatus(TC1, 2);

	Serial.println("Tick");

	// Very first thing here is to issue the pixelString data generated from the
	// *previous* callback.  It's done this way on purpose because show() is
	// roughly constant-time, so the refresh will always occur on a uniform
	// beat with respect to the Timer1 interrupt.  The various effects
	// rendering and compositing code is not constant-time, and that
	// unevenness would be apparent if show() were called at the end.
	pixelString.show();

	byte frontImgIdx = 1 - backImgIdx,
		*backPtr    = &imgData[backImgIdx][0],
		r, g, b;
	int  i;

	// Always render back image based on current effect index:
	(*renderEffect[fxIdx[backImgIdx]])(backImgIdx);

	// Front render and composite only happen during transitions...
	if(tCounter > 0) {
		// Transition in progress
		byte *frontPtr = &imgData[frontImgIdx][0];
		int  alpha, inv;

		// Render front image and alpha mask based on current effect indices...
		(*renderEffect[fxIdx[frontImgIdx]])(frontImgIdx);
		(*renderAlpha[fxIdx[2]])();

		// ...then composite front over back:
		for(i=0; i<NUM_PIXELS; i++) {
			alpha = alphaMask[i] + 1; // 1-256 (allows shift rather than divide)
			inv   = 257 - alpha;      // 1-256 (ditto)
			// r, g, b are placed in variables (rather than directly in the
			// setPixelColor parameter list) because of the postincrement pointer
			// operations -- C/C++ leaves parameter evaluation order up to the
			// implementation; left-to-right order isn't guaranteed.
			r = getGamma((*frontPtr++ * alpha + *backPtr++ * inv) >> 8);
			g = getGamma((*frontPtr++ * alpha + *backPtr++ * inv) >> 8);
			b = getGamma((*frontPtr++ * alpha + *backPtr++ * inv) >> 8);
			pixelString.setPixelColor(i, r, g, b);
		}
	} else {

		// No transition in progress; just show back image
		for(i=0; i<NUM_PIXELS; i++) {
			// See note above re: r, g, b vars.

			r = getGamma(*backPtr++);
			g = getGamma(*backPtr++);
			b = getGamma(*backPtr++);
			pixelString.setPixelColor(i, r, g, b);
		}
	}

	// Count up to next transition (or end of current one):
	tCounter++;
	if(tCounter == 0) { // Transition start
		// Randomly pick next image effect and alpha effect indices:
		fxIdx[frontImgIdx] = random((sizeof(renderEffect) / sizeof(renderEffect[0])));
		fxIdx[2]           = random((sizeof(renderAlpha)  / sizeof(renderAlpha[0])));
		transitionTime     = 255; //random(30, 181); // 0.5 to 3 second transitions
		fxIntVars[frontImgIdx][0] = 0; // Effect not yet initialized
		fxIntVars[2][0]           = 0; // Transition not yet initialized
	} else if(tCounter >= transitionTime) { // End transition
		fxIdx[backImgIdx] = fxIdx[frontImgIdx]; // Move front effect index to back
		backImgIdx        = 1 - backImgIdx;     // Invert back index
		tCounter          = -3600; //-120 - random(240); // Hold image 2 to 6 seconds
	}
}

// ---------------------------------------------------------------------------
// Image effect rendering functions.  Each effect is generated parametrically
// (that is, from a set of numbers, usually randomly seeded).  Because both
// back and front images may be rendering the same effect at the same time
// (but with different parameters), a distinct block of parameter memory is
// required for each image.  The 'fxIntVars' array is a two-dimensional array
// of integers, where the major axis is either 0 or 1 to represent the two
// images, while the minor axis holds 50 elements -- this is working scratch
// space for the effect code to preserve its "state."  The meaning of each
// element is generally unique to each rendering effect, but the first element
// is most often used as a flag indicating whether the effect parameters have
// been initialized yet.  When the back/front image indexes swap at the end of
// each transition, the corresponding set of fxIntVars, being keyed to the same
// indexes, are automatically carried with them.

// Simplest rendering effect: fill entire image with solid color
void ProgramSolidColor(byte idx) {
	// Only needs to be rendered once, when effect is initialized:
	if(fxIntVars[idx][0] == 0) {
		byte *ptr = &imgData[idx][0],
			r = random(256), g = random(256), b = random(256);
		for(int i=0; i<NUM_PIXELS; i++) {
			*ptr++ = r; *ptr++ = g; *ptr++ = b;
		}

		fxIntVars[idx][0] = 1; // Effect initialized
	}
}

// Chaser
//   based on G35 Xmas lights code by Paul Martis (http://www.digitalmisery.com)
//  (more interesting patterns by MEO)
void ProgramChaser(byte idx) {
	if(fxIntVars[idx][0] == 0) {
		fxI8Vars[idx][0] = 1; //count step
		fxI16Vars[idx][0] = 0; //sequence step
		fxIntVars[idx][1] = random(3); //chaser pattern
		fxIntVars[idx][2] = 1; //number of pixels in a row with specific color
		fxIntVars[idx][3] = random(1536); //color starting point
		frameDelay[idx] = 8; //delay frame count
		frame[idx] = 0; //delay frame

		fxIntVars[idx][0] = 1; // Effect initialized
	}

	if (frame[idx] == frameDelay[idx]) //only do once every delay frames
	{
		switch (fxIntVars[idx][1])
		{
		case 0:
			fill_sequence(fxI8Vars[idx][0], fxI16Vars[idx][0], fxIntVars[idx][2], fxIntVars[idx][3], ChaseRotateAnalogic45, idx);
			break;
		case 1:
			fill_sequence(fxI8Vars[idx][0], fxI16Vars[idx][0], fxIntVars[idx][2], fxIntVars[idx][3], ChaseRotateAccentedAnalogic30, idx);
			break;
		case 2:
			fill_sequence(fxI8Vars[idx][0], fxI16Vars[idx][0], fxIntVars[idx][2], fxIntVars[idx][3], ChaseRotateCompliment, idx);
			break;
		}
		if (fxI8Vars[idx][0] < NUM_PIXELS)
		{
			++fxI8Vars[idx][0];
		}
		else
		{
			++fxI16Vars[idx][0];
		}	
		frame[idx] = 0;
	} else {
		frame[idx]++;
	}
}


//Larson Scanner Two
// Programmed by MEO from scratch

//fade levels - adjust until looks pleasing
byte larsonTrail[27]  = {255, 223, 191, 159, 127, 111, 95, 79, 63, 55, 47, 
39, 31, 27, 23, 19, 15, 13, 11, 9, 7, 6, 5, 4, 3, 2, 1};
// This function gets the fade level
inline byte getTrail(byte x) {
	return pgm_read_byte(&larsonTrail[x]);
}
void ProgramLarsonTwo(byte idx){
	if(fxIntVars[idx][0] == 0) { // Initialize effect?
		fxIntVars[idx][1] = 1024; //Colour on color wheel
		fxI32Vars[idx][0] = 0; // eye position
		fxI8Vars[idx][0] = 0; //direction (0/1)
		frameDelay[idx] = 0; //delay frame count
		frame[idx] = 0; //delay frame

		fxIntVars[idx][0] = 1; //end initialise
	}

	byte *ptr = &imgData[idx][0];

	if (frame[idx] == frameDelay[idx]) {//only do once every delay frames
		long color, offset;
		for(int i = 0; i < NUM_PIXELS; i++) {
			if (fxI8Vars[idx][1] == 0) {
				offset = i - fxI32Vars[idx][0];
			} else {
				offset = fxI32Vars[idx][0] - i;
			}
			if (offset < 28) {
				color = hsv2rgb(fxIntVars[idx][1], 255, getTrail(offset), 0);
			} else {
				color = hsv2rgb(fxIntVars[idx][1], 255, 0, 0);
			}
			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}

		//increase/decrease eye position depending on direction
		if (fxI8Vars[idx][1] == 0) {
			fxI32Vars[idx][0]++;
		} else {
			fxI32Vars[idx][0]--;
		}

		//change direction at end of string:
		if (fxI32Vars[idx][0] == (NUM_PIXELS - 1)) {
			fxI8Vars[idx][1] = 1;
		}
		if (fxI32Vars[idx][0] == -1) {
			fxI8Vars[idx][1] = 0;
		}
		frame[idx] = 0;

	} else {
		frame[idx]++;
	}
}



//By Christopher De Vries <https://bitbucket.org/devries/arduino-tcl/src/1c93786ac579aea4bc07575c078caa051c4f53b7/examples/fire/fire.ino?at=default>.
//with modifications around movement by MEO
//ToDo: use forthcoming visual echo to interpolate between frames for smoother movement
void ProgramFlames(byte idx){
	if(fxIntVars[idx][0] == 0) { // Initialize effect?
		fxIntVars[idx][1] = 101; //intensity Hi
		fxIntVars[idx][2] = 0; //intensity Lo
		fxIntVars[idx][3] = 101; //transition Hi
		fxIntVars[idx][4] = 0; //transition Lo
		fxIntVars[idx][5] = 1; //sub pattern/variation
		fxIntVars[idx][6] = 255; //Colour 1 R
		fxIntVars[idx][7] = 0; //Colour 1 G //redo these, probably, as single vars
		fxIntVars[idx][8] = 0; //Colour 1 B
		fxIntVars[idx][9] = 255; //Colour 2 R
		fxIntVars[idx][10] = 145; //Colour 2 G
		fxIntVars[idx][11] = 0; //Colour 2 B
		frameDelay[idx] = 4; //delay frame count
		frame[idx] = 0; //delay frame

		fxIntVars[idx][0] = 1; //end initialise
	}

	byte *ptr = &imgData[idx][0];

	if (frame[idx] == frameDelay[idx]) //only do once every delay frames
	{
		int transition, intensity;
		byte r, g, b;
		for(int i = 0; i < NUM_PIXELS; i++) {
			transition = (int)random(fxIntVars[idx][4], fxIntVars[idx][3]);
			intensity = (int)random(fxIntVars[idx][2], fxIntVars[idx][3]);

			r = ((fxIntVars[idx][9]-fxIntVars[idx][6])*transition/100+fxIntVars[idx][6])*intensity/100;
			g = ((fxIntVars[idx][10]-fxIntVars[idx][7])*transition/100+fxIntVars[idx][7])*intensity/100;
			b = ((fxIntVars[idx][11]-fxIntVars[idx][8])*transition/100+fxIntVars[idx][8])*intensity/100;
			*ptr++ = r; *ptr++ = g; *ptr++ = b;
		}	
		frame[idx] = 0;
	} else {
		frame[idx]++;
	}
}

// Rainbow effect (1 or more full loops of color wheel at 100% saturation).
// Not a big fan of this pattern (it's way overused with LED stuff), but it's
// practically part of the Geneva Convention by now.
void ProgramRotatingRainbow(byte idx) {
	if(fxIntVars[idx][0] == 0) { // Initialize effect?
		// Number of repetitions (complete loops around color wheel); any
		// more than 4 per meter just looks too chaotic and un-rainbow-like.
		// Store as hue 'distance' around complete belt:
		fxIntVars[idx][1] = 0; //1536; //(4 + random(1 * ((NUM_PIXELS + 31) / 32))) * 1536;  //1 was 4
		// Frame-to-frame hue increment (speed) -- may be positive or negative,
		// but magnitude shouldn't be so small as to be boring.  It's generally
		// still less than a full pixel per frame, making motion very smooth.
		fxIntVars[idx][2] = 20;//4 + random(fxIntVars[idx][1]) / NUM_PIXELS;  //1 was 4
		// Reverse speed and hue shift direction half the time.
		if(random(2) == 0) fxIntVars[idx][1] = -fxIntVars[idx][1];
		if(random(2) == 0) fxIntVars[idx][2] = -fxIntVars[idx][2];
		fxIntVars[idx][3] = 0; // Current position
		fxIntVars[idx][4] = 1; //increase step 1 / decrease step 0
		fxIntVars[idx][5] = random(4); //full rainbow / RG only / GB / BR
		fxIntVars[idx][0] = 1; // Effect initialized
	}

	byte *ptr = &imgData[idx][0];
	long color, i;
	for(i=0; i<NUM_PIXELS; i++) {
		color = hsv2rgb(fxIntVars[idx][3] + fxIntVars[idx][1] * i / NUM_PIXELS,
			255, 255, fxIntVars[idx][5]);
		*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
	}
	fxIntVars[idx][3] += fxIntVars[idx][2];

	////Make a bit more interesing by gradually tightening rainbow span size
	//step in direction
	if (fxIntVars[idx][4] == 1)
	{
		fxIntVars[idx][1]++;
	} else {
		fxIntVars[idx][1]--;
	}
	//change direction
	if (fxIntVars[idx][1] == 2500)
	{
		fxIntVars[idx][4] = 0;
	}
	if (fxIntVars[idx][1] == -1)
	{
		fxIntVars[idx][4] = 1;
	}		
}

// Sine wave chase effect
void ProgramSineWave(byte idx) {
	if(fxIntVars[idx][0] == 0) { // Initialize effect?
		fxIntVars[idx][1] = random(3) * 512; //random(1536); // Random hue
		// Number of repetitions (complete loops around color wheel);
		// any more than 4 per meter just looks too chaotic.
		// Store as distance around complete belt in half-degree units:
		fxIntVars[idx][2] = (1 + random(4 * ((NUM_PIXELS + 31) / 32))) * 720;
		// Frame-to-frame increment (speed) -- may be positive or negative,
		// but magnitude shouldn't be so small as to be boring.  It's generally
		// still less than a full pixel per frame, making motion very smooth.
		fxIntVars[idx][3] = 2;//4 + random(fxIntVars[idx][1]) / NUM_PIXELS;
		// Reverse direction half the time.
		if(random(2) == 0) fxIntVars[idx][3] = -fxIntVars[idx][3];
		fxIntVars[idx][4] = 0; // Current position
		//ToDo: Rainbow changing sine
		//ToDo: Rainbown spread across string sine
		fxIntVars[idx][0] = 1; // Effect initialized
	}

	byte *ptr = &imgData[idx][0];
	int  foo;
	long color, i;
	
	//test non-advanced version, as advanced version doesn't do black very well. >>
	byte r, g, b, rMain, gMain, bMain, rHi, gHi, bHi, rLo, gLo, bLo;
	long colorMain, colorHi, colorLo;
	colorMain = hsv2rgb(fxIntVars[idx][1], 255, 255, 0);
	colorHi = hsv2rgb(fxIntVars[idx][1], 0, 255, 0); //white
	colorLo = hsv2rgb(fxIntVars[idx][1], 0, 0, 0); //black
	// Need to decompose colors into their r, g, b elements
	rMain = (colorMain >> 16);
	gMain = (colorMain >>  8);
	bMain = colorMain;
	rHi = (colorHi >> 16);
	gHi = (colorHi >>  8);
	bHi = colorHi;
	rLo = (colorLo >> 16);
	gLo = (colorLo >>  8);
	bLo = colorLo; //<<<<
	float y;
	int wavesPerString;


	for(long i=0; i<NUM_PIXELS; i++) {
		/*// Peaks of sine wave are white, troughs are black, mid-range
		// values are pure hue (100% saturated). >> Sine table way - need to fix
		foo = fixSin(fxIntVars[idx][4] + fxIntVars[idx][2] * i / NUM_PIXELS);
		color = (foo >= 0) ?
			hsv2rgb(fxIntVars[idx][1], 254 - (foo * 2), 255, 0) :
				hsv2rgb(fxIntVars[idx][1], 255, 254 + foo * 2, 0);
		*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		//<<<< */

		//>>> Non-Sine table way - slower, but works! Need fix for above
		wavesPerString = 1;
		y = sin(PI * wavesPerString * (float)(fxIntVars[idx][4] + i) / (float)NUM_PIXELS);
		if(y >= 0.0)
		{
			// Peaks of sine wave are white
			y  = 1.0 - y; // Translate Y to 0.0 (top) to 1.0 (center)
			r = rHi - (byte)((float)(rHi - rMain) * y);
			g = gHi - (byte)((float)(gHi - gMain) * y);
			b = bHi - (byte)((float)(bHi - bMain) * y);
		}
		else
		{
			// Troughs of sine wave are black
			y += 1.0; // Translate Y to 0.0 (bottom) to 1.0 (center)
			r = rLo + (byte)((float)(rMain) * y);
			g = gLo + (byte)((float)(gMain) * y);
			b = bLo + (byte)((float)(bMain) * y);
		}
		*ptr++ = r; *ptr++ = g; *ptr++ = b;
		//<<< 
	}
	fxIntVars[idx][4] += fxIntVars[idx][3];
}

// Data for American-flag-like colors (20 pixels representing
// blue field, stars and pixelStringes).  This gets "stretched" as needed
// to the full LED pixelString length in the flag effect code, below.
// Can change this data to the colors of your own national flag,
// favorite sports team colors, etc.  OK to change number of elements.
//MEO: ToDo: this doens't work properly because of the fixSin/fixCos problem
#define C_RED   160,   0,   0
#define C_WHITE 255, 255, 255
#define C_BLUE    0,   0, 100
byte flagTable[]  = {
	C_BLUE , C_WHITE, C_BLUE , C_WHITE, C_BLUE , C_WHITE, C_BLUE,
	C_RED  , C_WHITE, C_RED  , C_WHITE, C_RED  , C_WHITE, C_RED ,
	C_WHITE, C_RED  , C_WHITE, C_RED  , C_WHITE, C_RED };

	// Wavy flag effect
	void ProgramWavyFlag(byte idx) {
		long i, sum, s, x;
		int  idx1, idx2, a, b;
		if(fxIntVars[idx][0] == 0) { // Initialize effect?
			fxIntVars[idx][1] = 720 + random(720); // Wavyness
			fxIntVars[idx][2] = 1;//4 + random(10);    // Wave speed
			fxIntVars[idx][3] = 200 + random(200); // Wave 'puckeryness'
			fxIntVars[idx][4] = 0;                 // Current  position
			fxIntVars[idx][0] = 1;                 // Effect initialized
		}
		for(sum=0, i=0; i<NUM_PIXELS-1; i++) {
			sum += fxIntVars[idx][3] + fixCos(fxIntVars[idx][4] + fxIntVars[idx][1] *
				i / NUM_PIXELS);
		}

		byte *ptr = &imgData[idx][0];
		for(s=0, i=0; i<NUM_PIXELS; i++) {
			x = 256L * ((sizeof(flagTable) / 3) - 1) * s / sum;
			idx1 =  (x >> 8)      * 3;
			idx2 = ((x >> 8) + 1) * 3;
			b    = (x & 255) + 1;
			a    = 257 - b;
			*ptr++ = ((pgm_read_byte(&flagTable[idx1    ]) * a) +
				(pgm_read_byte(&flagTable[idx2    ]) * b)) >> 8;
			*ptr++ = ((pgm_read_byte(&flagTable[idx1 + 1]) * a) +
				(pgm_read_byte(&flagTable[idx2 + 1]) * b)) >> 8;
			*ptr++ = ((pgm_read_byte(&flagTable[idx1 + 2]) * a) +
				(pgm_read_byte(&flagTable[idx2 + 2]) * b)) >> 8;
			s += fxIntVars[idx][3] + fixCos(fxIntVars[idx][4] + fxIntVars[idx][1] *
				i / NUM_PIXELS);
		}

		fxIntVars[idx][4] += fxIntVars[idx][2];
		if(fxIntVars[idx][4] >= 720) fxIntVars[idx][4] -= 720;
	}

	// TO DO: Add more effects here...Larson scanner, etc.

	// Pulse and LarsonOne by elmerfud (http://forums.adafruit.com/viewtopic.php?f=47&t=29844&p=150244&hilit=advanced+belt#p150244)
	/* "I added a couple of effects. First simple one that picks a color and pulses the entire 
	strip. The second was a larson scanner type effect..... Which I'm not totally happy with but 
	I'm lazy and it works good enough. The problem with the larson scanner was I decided to simply 
	light the peak of the sine wave table and bounce it back and fourth around the circle. Since 
	the "eye" may be more than 1 LED when it reaches the end it overlap to the other side. I'm 
	sure there's some simple way to do it, but quite honestly, I'm not a programmer, know very 
	little about math and so to me the "advanced" belt sketch is REALLY advanced."  */



	// Pulse entire image with solid color
	void ProgramPulse(byte idx) {
		if(fxIntVars[idx][0] == 0) {
			fxIntVars[idx][1] = 50; // Pulse ammount min (v)
			fxIntVars[idx][2] = 250; // Pulse ammount max (v)
			fxIntVars[idx][3] = random(1536); // Random hue

			fxIntVars[idx][4] = fxIntVars[idx][1]; // pulse position 
			fxIntVars[idx][5] = 1; // 0 = negative, 1 = positive
			fxIntVars[idx][6] = 2 + random(10); // step value
			fxIntVars[idx][0] = 1; // Effect initialized
		}

		byte *ptr = &imgData[idx][0];
		long color, i;
		for(i=0; i<NUM_PIXELS; i++) {
			color = hsv2rgb(fxIntVars[idx][3], 255, fxIntVars[idx][4], 0);
			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}

		if (fxIntVars[idx][5] == 0) {
			fxIntVars[idx][4] = fxIntVars[idx][4] - fxIntVars[idx][6];
			if (fxIntVars[idx][4] <= fxIntVars[idx][1]) {
				fxIntVars[idx][5] = 1;
				fxIntVars[idx][4] = fxIntVars[idx][1];
			}
		} else if (fxIntVars[idx][5] == 1) {
			fxIntVars[idx][4] = fxIntVars[idx][4] + fxIntVars[idx][6];
			if (fxIntVars[idx][4] >= fxIntVars[idx][2]) {
				fxIntVars[idx][5] = 0;
				fxIntVars[idx][4] = fxIntVars[idx][2];
			}
		}
	}

	// larson scanner effect
	void ProgramLarsonOne(byte idx) {
		if(fxIntVars[idx][0] == 0) { // Initialize effect?
			fxIntVars[idx][1] = random(1536); // Random hue for 'Eye'
			fxIntVars[idx][2] = (fxIntVars[idx][1] >= 768) ?  // background hue is 180 degrees opposie
				(fxIntVars[idx][1] - 768) : (fxIntVars[idx][1] + 768); 
			// Frame-to-frame increment (speed) -- may be positive or negative,
			// but magnitude shouldn't be so small as to be boring.  It's generally
			// still less than a full pixel per frame, making motion very smooth.
			fxIntVars[idx][3] = 10 + random(10);  // eye speed in fps.  not too fast not too slow
			fxIntVars[idx][4] = 0; // Current position
			fxIntVars[idx][5] = 5; // Eye size 0 - 127, generally 0-5 is what you want
			// look as the sin table, picks how far down the table 
			// we look.
			fxIntVars[idx][0] = 1; // Effect initialized
		}

		byte *ptr = &imgData[idx][0];
		int  foo;
		long color, i;
		for(i=0; i<NUM_PIXELS; i++) {
			// Use cos to determine the position of the eye as if it's a circle
			// since it use 1/2 degree increments and we use 720 here
			foo = fixCos(fxIntVars[idx][4] + 720 * i / NUM_PIXELS);
			color = (foo >= (127 - fxIntVars[idx][5])) ?
				hsv2rgb(fxIntVars[idx][1], 255, 255, 0) :
					hsv2rgb(fxIntVars[idx][2], 255, 127, 0);
			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}
		fxIntVars[idx][4] += fxIntVars[idx][3];

		// Flip directions when we reach the end
		if (fxIntVars[idx][4] <= 0) {
			fxIntVars[idx][3] = fxIntVars[idx][3] * -1;
		} else if (fxIntVars[idx][4] >= 720) {
			fxIntVars[idx][3] = fxIntVars[idx][3] * -1;
		}
	}

	//MEO Effects...

#define PI 3.14159265

	// Color phasing (inspired by: http://krazydad.com/tutorials/makecolors.php)
	//ToDo: re-implement 'turn' from pattern 9
	//      also use turn to swap phase 1.0 / 0.0
	//		e.g. fstep 0 -> 400 = 1 0 1; 400 -> = 0 1 0; 0 -> 400 = 0 1 0; 400 -> 0 = 1 0 1

	void ProgramPhasing(byte idx) {
		if(fxIntVars[idx][0] == 0) {
			fxIntVars[idx][1] = 128; // Wave center
			fxIntVars[idx][2] = 127; // Wave width (center+ width, and center - width must not pass 255 or 0)
			fxIntVars[idx][3] = 1; //direction (1 forward / 0 backwards)
			fxIntVars[idx][4] = random(18); //sub-pattern / variation
			fxIntVars[idx][5] = 0; //turn - sub-sub-variation
			fxI32Vars[idx][0] = 1500; //size
			fxI32Vars[idx][1] = 0;  //start step (fStep in 2012 version) - freq modifier
			fxI32Vars[idx][2] = 0; //pStep in 2012 version - phase modifier
			fxIntVars[idx][0] = 1; // Effect initialized
		}

		byte *ptr = &imgData[idx][0];

		float frequencyR_; //red freq
		float frequencyG_;
		float frequencyB_;
		float phaseR_; //red phase
		float phaseG_;
		float phaseB_;
		int r; //final red
		int g;
		int b;
		bool redOff_; //whether to override-and switch red channel off
		bool grnOff_;
		bool bluOff_;

		// this switch chooses a variation
		switch (fxIntVars[idx][4] % 20)
		{
		case 0:  //Wavey pastels (Green 'peak')
			phaseR_ = 0;
			phaseG_ = 2.0 * PI /3.0;
			phaseB_ = 4.0 * PI /3.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 1: // subtly changing pastel
			phaseR_ = 0;
			phaseG_ = (2.0 * PI /360.0) * (float)fxI32Vars[idx][2];
			phaseB_ = (4.0 * PI /360.0) * (float)fxI32Vars[idx][2];
			frequencyR_ = 1.666;
			frequencyG_ = 2.666;
			frequencyB_ = 3.666;
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 2: //White
			phaseR_ = 1.0;
			phaseG_ = 1.0;
			phaseB_ = 1.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 3: //Cyan/Red/White (Cyan 'peak')
			phaseR_ = 0.0;
			phaseG_ = 1.0;
			phaseB_ = 1.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 4: //Magenta/Green/White (Magenta 'peak')
			phaseR_ = 1.0;
			phaseG_ = 0.0;
			phaseB_ = 1.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 5: //Yellow/Blue/White (Yellow 'peak')
			phaseR_ = 1.0;
			phaseG_ = 1.0;
			phaseB_ = 0.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 6: //Single primary (White 'peak') - 'White' is a touch complementary color
			switch (fxIntVars[idx][5] % 3)
			{
			case 0:  //Red
				phaseR_ = 0.0;
				phaseG_ = 1.0;
				phaseB_ = 1.0;
				frequencyR_ = 0.0;
				frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0]; //0 would make white/yellow
				frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0]; //0 would make white/weak mageneta
				break;
			case 1: //Green
				phaseR_ = 1.0;
				phaseG_ = 0.0;
				phaseB_ = 1.0;
				frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyG_ = 0.0;
				frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				break;
			case 2: //Blue
				phaseR_ = 1.0;
				phaseG_ = 1.0;
				phaseB_ = 0.0;
				frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyB_ = 0.0;
				break;
			}
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 7: //Evolving pastel wave - 6 sub variations
			switch (fxIntVars[idx][5] % 6)
			{
			case 0: //these sub variations are all pretty similar
				phaseR_ = 0;
				phaseG_ = (2.0 * PI /360.0) * (float)fxI32Vars[idx][2];
				phaseB_ = (4.0 * PI /360.0) * (float)fxI32Vars[idx][2];
				frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				break;
			case 2:
				phaseR_ = (4.0 * PI /360.0) * (float)fxI32Vars[idx][2];
				phaseG_ = 0;
				phaseB_ = (2.0 * PI /360.0) * (float)fxI32Vars[idx][2];
				frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				break;
			case 4:
				phaseR_ = (2.0 * PI /360.0) * (float)fxI32Vars[idx][2];
				phaseG_ = (4.0 * PI /360.0) * (float)fxI32Vars[idx][2];
				phaseB_ = 0;
				frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				break;
			case 1:
				phaseR_ = 0;
				phaseG_ = (4.0 * PI /360.0) * (float)fxI32Vars[idx][2];
				phaseB_ = (2.0 * PI /360.0) * (float)fxI32Vars[idx][2];
				frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				break;
			case 3:
				phaseR_ = (4.0 * PI /360) * (float)fxI32Vars[idx][2];
				phaseG_ = (2.0 * PI /360) * (float)fxI32Vars[idx][2];
				phaseB_ = 0;
				frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				break;
			case 5:
				phaseR_ = (2.0 * PI /360) * (float)fxI32Vars[idx][2];
				phaseG_ = 0;
				phaseB_ = (4.0 * PI /360) * (float)fxI32Vars[idx][2];
				frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
				break;
			}
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 8: //Red/Blue/Magenta (Red 'peak')
			phaseR_ = 0.0;
			phaseG_ = 2.0 * PI /3.0;
			phaseB_ = 4.0 * PI /3.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = true; bluOff_ = false;
			break;
		case 9: //Green/Red/Yellow (Green 'peak')
			phaseR_ = 0.0;
			phaseG_ = 2.0 * PI /3.0;
			phaseB_ = 4.0 * PI /3.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = true;
			break;
		case 10: //Blue/Green/Cyan (Blue 'peak')
			phaseR_ = 0.0;
			phaseG_ = 4.0 * PI /3.0;
			phaseB_ = 2.0 * PI /3.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = true; grnOff_ = false; bluOff_ = false;
			break;
		case 11: //Cyan/Green/Red/Magenta slightly askew (Cyan 'peak')
			phaseR_ = 0.0;
			phaseG_ = 2.0 * PI /3.0;
			phaseB_ = 1.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 12: //Magenta/Green/Blue/Cyan slightly askew (Magenta 'peak')
			phaseR_ = 1.0;
			phaseG_ = 0.0;
			phaseB_ = 2.0 * PI /3.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 13: //Yellow/Blue/Red/Cyan slightly askew (Yellow 'peak')
			phaseR_ = 2.0 * PI /3.0;
			phaseG_ = 1.0;
			phaseB_ = 0.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 14:  //Green/Red/Yellow slightly askew (Green 'peak')
			phaseR_ = 0.0;
			phaseG_ = 2.0 * PI /3.0;
			phaseB_ = 4.0 * PI /3.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = 0.0;
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 15:  //Blue/Green/Cyan slightly askew (Blue 'peak')
			phaseR_ = 4.0 * PI /3.0;
			phaseG_ = 0.0;
			phaseB_ = 2.0 * PI /3.0;
			frequencyR_ = 0.0;
			frequencyG_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		case 16:  //Red/Blue/Magenta slightly askew (Magenta 'peak')
			phaseR_ = 2.0 * PI /3.0;
			phaseG_ = 4.0 * PI /3.0;
			phaseB_ = 0.0;
			frequencyR_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			frequencyG_ = 0.0;
			frequencyB_ = (float)fxI32Vars[idx][1] / (float)fxI32Vars[idx][0];
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			break;
		default: //nothing - a still pastel rainbow
			phaseR_ = 2.0 * PI /3.0;
			phaseG_ = 4.0 * PI /3.0;
			phaseB_ = 0.0;
			frequencyR_ = 0.06;
			frequencyG_ = 0.06;
			frequencyB_ = 0.06;
			redOff_ = false; grnOff_ = false; bluOff_ = false;
			;
		}

		for(int i=0; i<NUM_PIXELS; i++) {
			//ToDo: redo sin with pburgess table version  
			if (redOff_)
			{
				r = 0; 
			} else {
				r = sin(frequencyR_*i + phaseR_) * fxIntVars[idx][2] + fxIntVars[idx][1];
			}
			if (grnOff_)
			{
				g = 0;
			} else {
				g = sin(frequencyG_*i + phaseG_) * fxIntVars[idx][2] + fxIntVars[idx][1];
			}
			if (bluOff_)
			{
				b = 0;
			} else {
				b = sin(frequencyB_*i + phaseB_) * fxIntVars[idx][2] + fxIntVars[idx][1];
			}

			*ptr++ = r; *ptr++ = g; *ptr++ = b;
		}


		//step in direction
		if (fxIntVars[idx][3] == 1)
		{
			fxI32Vars[idx][1]++;
		} else {
			fxI32Vars[idx][1]--;
		}

		//set direction: 1 2 .. 98 .. 400 .. 98 .. 2 1
		if (fxI32Vars[idx][1] == 400)
		{
			fxIntVars[idx][3] = 0;
		}
		if (fxI32Vars[idx][1] == -1)
		{
			fxIntVars[idx][3] = 1;
			fxIntVars[idx][5]++;
		}

		fxI32Vars[idx][2]++;
		if (fxI32Vars[idx][2] == 800)
		{
			fxI32Vars[idx][2] = 0;
		}
	}


	// Random strobe effect 
	//(inspired by the Eiffel Tower! : https://www.youtube.com/watch?v=pH2_mnh1XFE)
	// Note: currently only works with 50, 100 or 160 pixels (easy to add more)
	//To Do - see if can use my code to generate non repeating random nos on the fly
	void ProgramRandomStrobe(byte idx) {
		if(fxIntVars[idx][0] == 0) {
			fxIntVars[idx][1] = random(10); // sub pattern / variation
			fxIntVars[idx][2] = 0; // step through effect
			// Number of repetitions (complete loops around color wheel); any
			// more than 4 per meter just looks too chaotic and un-rainbow-like.
			// Store as hue 'distance' around complete belt:
			fxIntVars[idx][3] = 512; //1536; //(4 + random(1 * ((NUM_PIXELS + 31) / 32))) * 1536;  //1 was 4
			// Frame-to-frame hue increment (speed) -- may be positive or negative,
			// but magnitude shouldn't be so small as to be boring.  It's generally
			// still less than a full pixel per frame, making motion very smooth.
			fxIntVars[idx][4] = 5;//4 + random(fxIntVars[idx][1]) / NUM_PIXELS;  //1 was 4
			// Reverse speed and hue shift direction half the time.
			if(random(2) == 0) fxIntVars[idx][3] = -fxIntVars[idx][3];
			if(random(2) == 0) fxIntVars[idx][4] = -fxIntVars[idx][4];
			fxIntVars[idx][5] = 0; // Current position
			// ToDo: make number of bulbs at a time work
			// ToDo: slow down, by having bulbs stay same for a number of frames

			fxIntVars[idx][0] = 1; // Effect initialized
		}

		byte *ptr = &imgData[idx][0];

		uint8_t noAtATime_;
		bool rainbowFlash_; //instead of single strobe color, will cycle through colour wheel
		bool rainbowMain_; //instead of single background color, will cycle through colour wheel (complimentary colour to flash)
		int rMain; //backround colour
		int gMain;
		int bMain;
		int rFlash; //flash colour
		int gFlash;
		int bFlash;

		switch (fxIntVars[idx][1])
			{
			case 0: //Black - white flash
				rainbowMain_ = false;
				rainbowFlash_ = false;
				rMain = 0; gMain = 0; bMain = 0;
				rFlash = 255; gFlash = 255; bFlash = 255;
				noAtATime_ = 2;
				break;
			case 1: //Blue - white flash
				rainbowMain_ = false;
				rainbowFlash_ = false;
				rMain = 0; gMain = 0; bMain = 51;
				rFlash = 255; gFlash = 255; bFlash = 255;
				noAtATime_ = 2;
				break;
			case 2: //Red - white flash
				rainbowMain_ = false;
				rainbowFlash_ = false;
				rMain = 51; gMain = 0; bMain = 0;
				rFlash = 255; gFlash = 255; bFlash = 255;
				noAtATime_ = 2;
				break;
			case 3: //Green - white flash
				rainbowMain_ = false;
				rainbowFlash_ = false;
				rMain = 0; gMain = 51; bMain = 0;
				rFlash = 255; gFlash = 255; bFlash = 255;
				noAtATime_ = 2;
				break;
			case 4: //Black - rainbow flash - all bulbs of single colour before change
				rainbowMain_ = false;
				rainbowFlash_ = true;
				rMain = 0; gMain = 0; bMain = 0;
				noAtATime_ = 5;
				break;
			case 5:  //Rainbow backround - white flash
				rainbowMain_ = true;
				rainbowFlash_ = false;
				rFlash = 255; gFlash = 255; bFlash = 255;
				noAtATime_ = 5;
				break;
			case 6: //Rainbow background - Rainbow flash
				rainbowMain_ = true;
				rainbowFlash_ = true;
				rFlash = 255; gFlash = 255; bFlash = 255;
				noAtATime_ = 5;
				break;
			case 7:  //red backround - blue flash
				rainbowMain_ = false;
				rainbowFlash_ = false;
				rMain = 51; gMain = 0; bMain = 0;
				rFlash = 0; gFlash = 0; bFlash = 255;
				noAtATime_ = 5;
				break;
			case 8: //blue backround - red flash
				rainbowMain_ = false;
				rainbowFlash_ = false;
				rMain = 0; gMain = 0; bMain = 51;
				rFlash = 255; gFlash = 0; bFlash = 0;
				noAtATime_ = 5;
				break;
			case 9: //warm white background - white flash
				rainbowMain_ = false;
				rainbowFlash_ = false;
				rMain = 0xFF; gMain = 0xB0; bMain = 0x40;
				rFlash = 255; gFlash = 255; bFlash = 255;
				noAtATime_ = 10;
			}

		for(int i = 0 ; i < NUM_PIXELS ; i++) {
			if (getRandom(i, NUM_PIXELS) == fxIntVars[idx][2])
			{
				if (rainbowFlash_)
				{
					int color;
					color = hsv2rgb(fxIntVars[idx][5] + fxIntVars[idx][3] 
						* i / NUM_PIXELS, 255, 255, 0);
					*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
				} else {
					*ptr++ = rFlash; *ptr++ = gFlash; *ptr++ = bFlash;
				}
			} else {
				if (rainbowMain_)
				{
					int color;
					color = hsv2rgb((fxIntVars[idx][5] + fxIntVars[idx][3] 
						* i / NUM_PIXELS) + 768, 255, 100, 0); //768 so main is 180 deg from flash
					*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
				} else {
					*ptr++ = rMain; *ptr++ = gMain; *ptr++ = bMain;
				}
			}
		}
		fxIntVars[idx][2]++;

		//reset
		if (fxIntVars[idx][2] == NUM_PIXELS)
		{
			fxIntVars[idx][2] = 0;
		}

		fxIntVars[idx][5] += fxIntVars[idx][4];
	}
	//// Code for non repeating random nos
	//ToDo: reset after each time the last bulb is reached, so doesn't repeat pattern
	//int myBulbs[light_count_];
	//int myBulb;
	//myBulb = 0;
	//// Initialise myBulbs[] to an ordered range - i.e. myBulbs[0] = 0, myBulbs[1] = 1 etc...
	//for (int range = 0; range < light_count_; range++)
	//{
	//	myBulbs[range] = range;
	//}
	//// Random shuffle (note this will always be the same - maybe can re-seed with last number of shuffle?)
	//// so, myBulbs[0]=38, myBulbs[1]=13.. etc.. for example
	//for (int shuffle = 0; shuffle < light_count_ - 1; shuffle++)
	//{
	//	int myrand = shuffle + (rand() % (light_count_ - shuffle));
	//	int save = myBulbs[shuffle];
	//	myBulbs[shuffle] = myBulbs[myrand];
	//	myBulbs[myrand] = save;
	//}
	//srand(myBulbs[0]); //re-seed for next time
	////// <<<


	// Simplex Noise
	//(inspired by happyinmotion: http://happyinmotion.livejournal.com/278357.html)
	// Simplex noise for whole strip of LEDs.
	// (Well, it's simplex noise for 6 nodes and cubic interpolation between those nodes.)
#define onethird 0.333333333
#define onesixth 0.166666667
#define numSpacing 10 //was 4
#define FULL_ONE_MINUS 255 //level range

	int ii, jj, kk, AA[] = {0, 0, 0};
	float uu, vv, ww, ss;
	int TT[] = {0x15, 0x38, 0x32, 0x2c, 0x0d, 0x13, 0x07, 0x2a};

	void ProgramSimplexNoise(byte idx) {
		if(fxIntVars[idx][0] == 0) {
			fxIntVars[idx][1] = random(7); //sub pattern/variation
			fxFltVars[idx][0] = 0.0; //yOffset
			fxIntVars[idx][0] = 1; // Effect initialized
		}

		float bulbArray_red[NUM_PIXELS + 1];
		float bulbArray_green[NUM_PIXELS + 1];
		float bulbArray_blue[NUM_PIXELS + 1];
		float bulbArray_hue[NUM_PIXELS + 1];
		float bulbArray_brightness[NUM_PIXELS + 1];
		int node_spacing = NUM_PIXELS / numSpacing;
		float rMult_;
		float gMult_;
		float bMult_;
		float spaceinc_;
		float timeinc_;
		//float yoffset_;

		switch (fxIntVars[idx][1])
		{
		case 0:
			rMult_ = 1.0;
			gMult_ = 1.0;
			bMult_ = 1.0;
			break;
		case 1:
			rMult_ = 1.0;
			gMult_ = 0.0;
			bMult_ = 1.0;
			break;
		case 2:
			rMult_ = 0.0;
			gMult_ = 1.0;
			bMult_ = 1.0;
			break;
		case 3:
			rMult_ = 1.0;
			gMult_ = 1.0;
			bMult_ = 0.0;
			break;
		case 4:
			rMult_ = 1.0;
			gMult_ = 0.0;
			bMult_ = 0.0;
			break;
		case 5:
			rMult_ = 0.0;
			gMult_ = 1.0;
			bMult_ = 0.0;
			break;
		case 6:
			rMult_ = 0.0;
			gMult_ = 0.0;
			bMult_ = 1.0;
			break;
		}

		// Useable values for space increment range from 0.8 (LEDS doing different things to their neighbours), to 0.02 (roughly one feature present in 15 LEDs).
		// 0.05 seems ideal for relaxed screensaver
		spaceinc_ = 0.05;
		// following are timings for standard arduinos - the Due is pretty fast. 
		// Also - this is 60 fps even on standard arduino so some other jiggery pokery may 
		// be required on a standard one
		// "Useable values for time increment range from 0.005 (barely perceptible) to 0.2 (irritatingly flickery)
		// 0.02 seems ideal for relaxed screensaver"
		timeinc_ = 0.005;
		//yoffset_ = (float)fxIntVars[idx][1] / 10000.0;

		byte *ptr = &imgData[idx][0];

		float xoffset = 0.0;
		for (int i = 0; i <= NUM_PIXELS; i = i + node_spacing)
		{
			xoffset += spaceinc_;
			bulbArray_red[i] = SNSimplexNoise(xoffset, fxFltVars[idx][0], 0);
			bulbArray_green[i] = SNSimplexNoise(xoffset, fxFltVars[idx][0], 1);
			bulbArray_blue[i] = SNSimplexNoise(xoffset, fxFltVars[idx][0], 2);
		}

		for(int i = 0 ; i < NUM_PIXELS ; i++) {
			int position_between_nodes = i % node_spacing;
			int last_node, next_node;

			// If at node, skip
			if ( position_between_nodes == 0 )
			{
				// At node for simplex noise, do nothing but update which nodes we are between
				last_node = i;
				next_node = last_node + node_spacing;
			}
			// Else between two nodes, so identify those nodes
			else
			{
				// And interpolate between the values at those nodes for red, green, and blue
				float t = float(position_between_nodes) / float(node_spacing);
				float t_squaredx3 = 3*t*t;
				float t_cubedx2 = 2*t*t*t;
				bulbArray_red[i] = bulbArray_red[last_node] * ( t_cubedx2 - t_squaredx3 + 1.0 ) + bulbArray_red[next_node] * ( -t_cubedx2 + t_squaredx3 );
				bulbArray_green[i] = bulbArray_green[last_node] * ( t_cubedx2 - t_squaredx3 + 1.0 ) + bulbArray_green[next_node] * ( -t_cubedx2 + t_squaredx3 );
				bulbArray_blue[i] = bulbArray_blue[last_node] * ( t_cubedx2 - t_squaredx3 + 1.0 ) + bulbArray_blue[next_node] * ( -t_cubedx2 + t_squaredx3 );
			}
		}

		// Convert values from raw noise to scaled r,g,b and feed to strip
		for (int i = 0; i < NUM_PIXELS; i++)
		{
			int r = int(bulbArray_red[i]*403 + 16);
			int g = int(bulbArray_green[i]*403 + 16);
			int b = int(bulbArray_blue[i]*403 + 16);

			if (r > FULL_ONE_MINUS)
			{
				r = FULL_ONE_MINUS;
			}
			else if (r < 0)
			{
				r = 0;    // Adds no time at all. Conclusion: constrain() sucks.
			}

			if (g > FULL_ONE_MINUS)
			{
				g = FULL_ONE_MINUS;
			}
			else if (g < 0)
			{
				g = 0;
			}

			if (b > FULL_ONE_MINUS)
			{
				b = FULL_ONE_MINUS;
			}
			else if (b < 0 )
			{
				b = 0;
			}

			if (rMult_ > 1.0)
			{
				rMult_ = 1.0;
			}
			else if (rMult_ < 0.0)
			{
				rMult_ = 0.0;
			}

			if (gMult_ > 1.0)
			{
				gMult_ = 1.0;
			}
			else if (gMult_ < 0.0)
			{
				gMult_ = 0.0;
			}

			if (bMult_ > 1.0)
			{
				bMult_ = 1.0;
			}
			else if (bMult_ < 0.0)
			{
				bMult_ = 0.0;
			}
			*ptr++ = int((float)r * rMult_); *ptr++ = int((float)g * gMult_); *ptr++ = ((float)b * bMult_);
		}
		fxFltVars[idx][0] += timeinc_;
	}

	// Simplex noise code:
	// From an original algorithm by Ken Perlin.
	// Returns a value in the range of about [-0.347 .. 0.347]
	float SNSimplexNoise(float x, float y, float z)
	{
		// Skew input space to relative coordinate in simplex cell
		ss = (x + y + z) * onethird;
		ii = SNfastfloor(x+ss);
		jj = SNfastfloor(y+ss);
		kk = SNfastfloor(z+ss);

		// Unskew cell origin back to (x, y , z) space
		ss = (ii + jj + kk) * onesixth;
		uu = x - ii + ss;
		vv = y - jj + ss;
		ww = z - kk + ss;;

		AA[0] = AA[1] = AA[2] = 0;

		// For 3D case, the simplex shape is a slightly irregular tetrahedron.
		// Determine which simplex we're in
		int hi = uu >= ww ? uu >= vv ? 0 : 1 : vv >= ww ? 1 : 2;
		int lo = uu < ww ? uu < vv ? 0 : 1 : vv < ww ? 1 : 2;

		return SNk_fn(hi) + SNk_fn(3 - hi - lo) + SNk_fn(lo) + SNk_fn(0);
	}

	int SNfastfloor(float n)
	{
		return n > 0 ? (int) n : (int) n - 1;
	}

	float SNk_fn(int a)
	{
		ss = (AA[0] + AA[1] + AA[2]) * onesixth;
		float x = uu - AA[0] + ss;
		float y = vv - AA[1] + ss;
		float z = ww - AA[2] + ss;
		float t = 0.6f - x * x - y * y - z * z;
		int h = SNshuffle(ii + AA[0], jj + AA[1], kk + AA[2]);
		AA[a]++;
		if (t < 0) return 0;
		int b5 = h >> 5 & 1;
		int b4 = h >> 4 & 1;
		int b3 = h >> 3 & 1;
		int b2 = h >> 2 & 1;
		int b = h & 3;
		float p = b == 1 ? x : b == 2 ? y : z;
		float q = b == 1 ? y : b == 2 ? z : x;
		float r = b == 1 ? z : b == 2 ? x : y;
		p = b5 == b3 ? -p : p;
		q = b5 == b4 ? -q: q;
		r = b5 != (b4^b3) ? -r : r;
		t *= t;
		return 8 * t * t * (p + (b == 0 ? q + r : b2 == 0 ? q : r));
	}

	int SNshuffle(int i, int j, int k)
	{
		return SNb(i, j, k, 0) + SNb(j, k, i, 1) + SNb(k, i, j, 2) + SNb(i, j, k, 3) + SNb(j, k, i, 4) + SNb(k, i, j, 5) + SNb(i, j, k, 6) + SNb(j, k, i, 7);
	}

	int SNb(int i, int j, int k, int B)
	{
		return TT[SNb(i, B) << 2 | SNb(j, B) << 1 | SNb(k, B)];
	}

	int SNb(int N, int B)
	{
		return N >> B & 1;
	}


	// ---------------------------------------------------------------------------
	// Alpha channel effect rendering functions.  Like the image rendering
	// effects, these are typically parametrically-generated...but unlike the
	// images, there is only one alpha renderer "in flight" at any given time.
	// So it would be okay to use local static variables for storing state
	// information...but, given that there could end up being many more render
	// functions here, and not wanting to use up all the RAM for static vars
	// for each, a third row of fxIntVars is used for this information.

	// Simplest alpha effect: fade entire pixelString over duration of transition.
	void crossfadeSimple(void) {
		byte fade = 255L * tCounter / transitionTime;
		for(int i=0; i<NUM_PIXELS; i++) alphaMask[i] = fade;
	}



	//idea: left to right, but with fade: illustrated with 9 instead of 256 levels
	//999999999999999999
	//899999999999999999
	//  .
	//111111234567899999
	//  .
	//111111111111111112
	//111111111111111111
	//params could be length of difference line (2345678 part above)
	// a larson scanner of fades!

	//idea:

	// Straight left-to-right or right-to-left wipe
	void crossfadeWipe(void) {
		long x, y, b;
		if(fxIntVars[2][0] == 0) {
			fxIntVars[2][1] = random(1, NUM_PIXELS); // run, in pixels
			fxIntVars[2][2] = (random(2) == 0) ? 255 : -255; // rise
			fxIntVars[2][0] = 1; // Transition initialized
		}

		b = (fxIntVars[2][2] > 0) ?
			(255L + (NUM_PIXELS * fxIntVars[2][2] / fxIntVars[2][1])) *
			tCounter / transitionTime - (NUM_PIXELS * fxIntVars[2][2] / fxIntVars[2][1]) :
		(255L - (NUM_PIXELS * fxIntVars[2][2] / fxIntVars[2][1])) *
			tCounter / transitionTime;
		for(x=0; x<NUM_PIXELS; x++) {
			y = x * fxIntVars[2][2] / fxIntVars[2][1] + b; // y=mx+b, fixed-point style
			if(y < 0)         alphaMask[x] = 0;
			else if(y >= 255) alphaMask[x] = 255;
			else              alphaMask[x] = (byte)y;
		}
	}

	// Dither reveal between images
	void crossfadeDither(void) {
		long fade;
		int  i, bit, reverse, hiWord;

		if(fxIntVars[2][0] == 0) {
			// Determine most significant bit needed to represent pixel count.
			int hiBit, n = (NUM_PIXELS - 1) >> 1;
			for(hiBit=1; n; n >>=1) hiBit <<= 1;
			fxIntVars[2][1] = hiBit;
			fxIntVars[2][0] = 1; // Transition initialized
		}

		for(i=0; i<NUM_PIXELS; i++) {
			// Reverse the bits in i for ordered dither:
			for(reverse=0, bit=1; bit <= fxIntVars[2][1]; bit <<= 1) {
				reverse <<= 1;
				if(i & bit) reverse |= 1;
			}
			fade   = 256L * NUM_PIXELS * tCounter / transitionTime;
			hiWord = (fade >> 8);
			if(reverse == hiWord)     alphaMask[i] = (fade & 255); // Remainder
			else if(reverse < hiWord) alphaMask[i] = 255;
			else                      alphaMask[i] = 0;
		}
	}

	// TO DO: Add more transitions here...triangle wave reveal, etc.

	// ---------------------------------------------------------------------------
	// Assorted fixed-point utilities below this line.  Not real interesting.

	// MEO: NOW 8-Bit, not 7-bit!!
	// Gamma correction compensates for our eyes' nonlinear perception of
	// intensity.  It's the LAST step before a pixel value is stored, and
	// allows intermediate rendering/processing to occur in linear space.
	// The table contains 256 elements (8 bit input), though the outputs are
	// only 7 bits (0 to 127).  This is normal and intentional by design: it
	// allows all the rendering code to operate in the more familiar unsigned
	// 8-bit colorspace (used in a lot of existing graphics code), and better
	// preserves accuracy where repeated color blending operations occur.
	// Only the final end product is converted to 7 bits, the native format
	// for the LPD8806 LED driver.  Gamma correction and 7-bit decimation
	// thus occur in a single operation.
	/*byte gammaTable[]  = 
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 
	2, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 7, 
	7, 7, 8, 8, 8, 9, 9, 9, 10, 10, 11, 11, 11, 12, 12, 13, 13, 14, 
	14, 15, 15, 16, 16, 17, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 
	23, 23, 24, 24, 25, 26, 26, 27, 28, 28, 29, 30, 30, 31, 32, 32, 
	33, 34, 35, 35, 36, 37, 38, 38, 39, 40, 41, 42, 42, 43, 44, 45, 
	46, 47, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 56, 57, 58, 59, 
	60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 73, 74, 75, 76, 
	77, 78, 79, 80, 81, 82, 84, 85, 86, 87, 88, 89, 91, 92, 93, 94, 
	95, 97, 98, 99, 100, 102, 103, 104, 105, 107, 108, 109, 111, 112, 
	113, 115, 116, 117, 119, 120, 121, 123, 124, 126, 127, 128, 130, 
	131, 133, 134, 136, 137, 139, 140, 142, 143, 145, 146, 148, 149, 
	151, 152, 154, 155, 157, 158, 160, 162, 163, 165, 166, 168, 170, 
	171, 173, 175, 176, 178, 180, 181, 183, 185, 186, 188, 190, 192, 
	193, 195, 197, 199, 200, 202, 204, 206, 207, 209, 211, 213, 215, 
	217, 218, 220, 222, 224, 226, 228, 230, 232, 233, 235, 237, 239, 
	241, 243, 245, 247, 249, 251, 253, 255 };*/

	// This function (which actually gets 'inlined' anywhere it's called)
	// exists so that getGammaTable can reside out of the way down here in the
	// utility code...didn't want that huge table distracting or intimidating
	// folks before even getting into the real substance of the program, and
	// the compiler permits forward references to functions but not data.
	inline byte getGamma(byte x) {
		//return pgm_read_byte(&gammaTable[x]);
		return x;
	}


	// Fixed-point colorspace conversion: HSV (hue-saturation-value) to RGB.
	// This is a bit like the 'Wheel' function from the original strandtest
	// code on steroids.  The angular units for the hue parameter may seem a
	// bit odd: there are 1536 increments around the full color wheel here --
	// not degrees, radians, gradians or any other conventional unit I'm
	// aware of.  These units make the conversion code simpler/faster, because
	// the wheel can be divided into six sections of 256 values each, very
	// easy to handle on an 8-bit microcontroller.  Math is math, and the
	// rendering code elsehwere in this file was written to be aware of these
	// units.  Saturation and value (brightness) range from 0 to 255.
	// MEO: wheelLine 0: Full wheel RGB; 1: RG; 2: GB; 3: BR
	long hsv2rgb(long h, byte s, byte v, int wheelLine) {
		byte r, g, b, lo;
		int  s1;
		long v1;

		// Hue
		switch (wheelLine)
		{
		case 0: // Full RGB Wheel (pburgess original function)
			h %= 1536;           // -1535 to +1535
			if(h < 0) h += 1536; //     0 to +1535
			lo = h & 255;        // Low byte  = primary/secondary color mix
			switch(h >> 8) {     // High byte = sextant of colorwheel
			case 0 : r = 255     ; g =  lo     ; b =   0     ; break; // R to Y
			case 1 : r = 255 - lo; g = 255     ; b =   0     ; break; // Y to G
			case 2 : r =   0     ; g = 255     ; b =  lo     ; break; // G to C
			case 3 : r =   0     ; g = 255 - lo; b = 255     ; break; // C to B
			case 4 : r =  lo     ; g =   0     ; b = 255     ; break; // B to M
			default: r = 255     ; g =   0     ; b = 255 - lo; break; // M to R
			}
			break;
		case 1: //RG Line only
			h %= 1024;
			if(h < 0) h += 1024;
			lo = h & 255;        // Low byte  = primary/secondary color mix
			switch(h >> 8) {     // High byte = sextant of colorwheel
			case 0 : r = 255     ; g =  lo     ; b =   0     ; break; // R to Y
			case 1 : r = 255 - lo; g = 255     ; b =   0     ; break; // Y to G
			case 2 : r = lo      ; g = 255     ; b =   0     ; break; // G to Y
			default: r = 255     ; g = 255 - lo; b =   0     ; break; // Y to R
			}
			break;
		case 2: //GB Line only
			h %= 1024;
			if(h < 0) h += 1024;
			lo = h & 255;        // Low byte  = primary/secondary color mix
			switch(h >> 8) {     // High byte = sextant of colorwheel
			case 0 : r = 0       ; g = 255     ; b =  lo     ; break; // G to C
			case 1 : r = 0       ; g = 255 - lo; b =  255    ; break; // C to B
			case 2 : r = 0       ; g =  lo     ; b =  255    ; break; // B to C
			default: r = 0       ; g = 255     ; b = 255 - lo; break; // C to G
			}
			break;
		case 3: //BR Line only
			h %= 1024;
			if(h < 0) h += 1024;
			lo = h & 255;        // Low byte  = primary/secondary color mix
			switch(h >> 8) {     // High byte = sextant of colorwheel
			case 0 : r = lo      ; g =   0     ; b =  255    ; break; // B to M
			case 1 : r = 255     ; g =   0     ; b = 255 - lo; break; // M to R
			case 2 : r = 255     ; g =   0     ; b =  lo     ; break; // R to M
			default: r = 255 - lo; g =   0     ; b =  255    ; break; // M to B
			}
			break;
		}

		// Saturation: add 1 so range is 1 to 256, allowig a quick shift operation
		// on the result rather than a costly divide, while the type upgrade to int
		// avoids repeated type conversions in both directions.
		s1 = s + 1;
		r = 255 - (((255 - r) * s1) >> 8);
		g = 255 - (((255 - g) * s1) >> 8);
		b = 255 - (((255 - b) * s1) >> 8);

		// Value (brightness) and 24-bit color concat merged: similar to above, add
		// 1 to allow shifts, and upgrade to long makes other conversions implicit.
		v1 = v + 1;
		return (((r * v1) & 0xff00) << 8) |
			((g * v1) & 0xff00)       |
			( (b * v1)           >> 8);
	}

	// The fixed-point sine and cosine functions use marginally more
	// conventional units, equal to 1/2 degree (720 units around full circle),
	// chosen because this gives a reasonable resolution for the given output
	// range (-127 to +127).  Sine table intentionally contains 181 (not 180)
	// elements: 0 to 180 *inclusive*.  This is normal.


	byte sineTable[181]  = {
		0,  1,  2,  3,  5,  6,  7,  8,  9, 10, 11, 12, 13, 15, 16, 17,
		18, 19, 20, 21, 22, 23, 24, 25, 27, 28, 29, 30, 31, 32, 33, 34,
		35, 36, 37, 38, 39, 40, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,
		52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67,
		67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 77, 78, 79, 80, 81,
		82, 83, 83, 84, 85, 86, 87, 88, 88, 89, 90, 91, 92, 92, 93, 94,
		95, 95, 96, 97, 97, 98, 99,100,100,101,102,102,103,104,104,105,
		105,106,107,107,108,108,109,110,110,111,111,112,112,113,113,114,
		114,115,115,116,116,117,117,117,118,118,119,119,120,120,120,121,
		121,121,122,122,122,123,123,123,123,124,124,124,124,125,125,125,
		125,125,126,126,126,126,126,126,126,127,127,127,127,127,127,127,
		127,127,127,127,127
	};

	char fixSin(int angle) {
		angle %= 720;               // -719 to +719
		if(angle < 0) angle += 720; //    0 to +719
		return (angle <= 360) ?
			pgm_read_byte(&sineTable[(angle <= 180) ?
angle          : // Quadrant 1
		(360 - angle)]) : // Quadrant 2
		-pgm_read_byte(&sineTable[(angle <= 540) ?
			(angle - 360)   : // Quadrant 3
		(720 - angle)]) ; // Quadrant 4
	}

	char fixCos(int angle) {
		angle %= 720;               // -719 to +719
		if(angle < 0) angle += 720; //    0 to +719
		return (angle <= 360) ?
			((angle <= 180) ?  pgm_read_byte(&sineTable[180 - angle])  : // Quad 1
			-pgm_read_byte(&sineTable[angle - 180])) : // Quad 2
		((angle <= 540) ? -pgm_read_byte(&sineTable[540 - angle])  : // Quad 3
			pgm_read_byte(&sineTable[angle - 540])) ; // Quad 4
	}

	//non-repeating random numbers 50,100 or 160 bulbs only
	byte randomTable100[]  = 
	{85, 53, 88, 71, 6, 32, 91, 79, 15, 62, 80, 7, 28, 66, 27, 16, 
	23, 19, 54, 95, 0, 47, 40, 44, 2, 36, 31, 51, 48, 38, 87, 11, 
	70, 33, 56, 34, 92, 30, 5, 1, 78, 86, 84, 98, 12, 69, 77, 43, 
	97, 8, 94, 58, 55, 74, 4, 82, 99, 72, 20, 63, 29, 60, 89, 93, 
	45, 75, 13, 83, 67, 25, 21, 42, 52, 9, 49, 17, 41, 37, 50, 81, 
	96, 39, 46, 14, 35, 18, 76, 73, 24, 64, 10, 61, 3, 65, 57, 68, 26, 22, 59, 90};

/*			byte randomTable050[]= 
	{3, 15, 49, 0, 41, 26, 5, 48, 29, 46, 34, 24, 18, 43, 28, 2, 9, 
	44, 39, 19, 16, 35, 42, 36, 38, 37, 20, 14, 32, 10, 47, 11, 8, 
	31, 13, 25, 7, 22, 6, 30, 23, 4, 12, 17, 33, 27, 40, 45, 1, 21};

	byte randomTable160[]= 
	{105, 63, 31, 53, 94, 21, 77, 13, 41, 84, 44, 110, 158, 132, 1, 
	15, 93, 91, 30, 92, 40, 98, 27, 56, 7, 123, 75, 90, 100, 14, 70, 
	72, 101, 136, 43, 3, 137, 28, 22, 42, 149, 6, 157, 0, 111, 24, 
	64, 114, 128, 155, 51, 76, 88, 127, 78, 69, 120, 
	35, 49, 74, 26, 87, 154, 134, 2, 32, 4, 131, 57, 23, 54, 80, 73, 71, 
	50, 85, 68, 89, 33, 82, 147, 146, 145, 144, 67, 109, 79, 66, 25, 121, 
	46, 99, 17, 60, 86, 55, 102, 152, 108, 62, 112, 153, 59, 116, 83, 36, 
	34, 115, 140, 142, 135, 107, 8, 61, 156, 138, 45, 143, 118, 39, 11, 124, 
	130, 47, 52, 148, 106, 5, 96, 29, 126, 58, 122, 104, 159, 141, 10, 150, 
	117, 48, 12, 129, 81, 125, 18, 95, 119, 113, 103, 9, 133, 20, 139, 151, 
	37, 97, 38, 16, 19, 65};
*/
	// This function gets the fixed non-repeating random number
	inline byte getRandom(byte x, byte size) {
		switch (size)
		{
		case 50:
			//return pgm_read_byte(&randomTable050[x]);
			break;
		case 100:
			return pgm_read_byte(&randomTable100[x]);
			break;
		case 160:
			//return pgm_read_byte(&randomTable160[x]);
			break;
		}
	}


void fill_sequence(uint8_t count, uint16_t sequence, uint8_t span_size, int startColor, 
						   long (*sequence_func)(uint16_t sequence, int startColor), byte idx)
{
	//begin, count, sequence, span, func, idx)
	while (count--)
	{
		set_color(count, sequence_func(sequence++ / span_size, startColor), idx);
	}
}

void set_color(uint8_t bulb, long color, byte idx)
{
	byte *ptr = &imgData[idx][0];
	for (int i=0; i<NUM_PIXELS; i++) 
	{
		if (i == bulb)
		{
			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		} else {
			*ptr++;*ptr++;*ptr++; //leave alone
		}		
	}
} 

//Chaser patterns
long ChaseRGB(uint16_t sequence, int startColor)
{
    sequence = sequence % 3;
    if (sequence == 0)
    {
        return (hsv2rgb(0, 255, 255, 0));
    }
    if (sequence == 1)
    {
        return (hsv2rgb(512, 255, 255, 0));
    }
    return (hsv2rgb(1024, 255, 255, 0));
} 

long ChaseRotateCompliment(uint16_t sequence, int startColor)
{
	uint16_t positionP, positionC;
	positionP = (startColor + sequence) % 1536;
	positionC = (startColor + sequence + 768) % 1536; // + 768 = 180 degrees
    sequence = sequence % 5;
    if (sequence == 0)
    {
        return (hsv2rgb(positionC, 255, 255, 0)); // Complimetary color
    } else {
        return (hsv2rgb(positionP, 255, 255, 0)); // Primary colour
    }
}

long ChaseRotateAnalogic45(uint16_t sequence, int startColor)
{
	uint16_t positionP1, positionP2, positionP3;
	positionP1 = (startColor + sequence) % 1536;
	positionP2 = (startColor + sequence + 192) % 1536; // + 192 = 45 degrees
	positionP3 = (startColor + sequence +1344) % 1536; // -192 = -45 degrees (added 1344 is equiv)
    sequence = sequence % 4;
    if (sequence == 0)
    {
        return (hsv2rgb(positionP2, 255, 255, 0)); // 45 degrees anti-clockwise
    }
	if ((sequence == 1) || (sequence == 3))
	{
        return (hsv2rgb(positionP3, 255, 255, 0)); // Primary colour
    }
	return (hsv2rgb(positionP1, 255, 255, 0)); //45 degrees clockwise
}

long ChaseRotateAccentedAnalogic30(uint16_t sequence, int startColor)
{
	uint16_t positionP1, positionP2, positionP3, positionC;
	positionP1 = (startColor + sequence) % 1536;
	positionP2 = (startColor + sequence + 128) % 1536; // + 128 = 30 degrees
	positionP3 = (startColor + sequence + 1280) % 1536; // -128 = -30 degrees (added 1280 is equiv)
	positionC = (startColor + sequence + 768) % 1536; // + 768 = 180 degrees
    sequence = sequence % 6;
    if (sequence == 0)
    {
        return (hsv2rgb(positionP2, 255, 255, 0)); // 30 degrees anti-clockwise
    }
	if ((sequence == 1) || (sequence == 5))
	{
        return (hsv2rgb(positionP1, 255, 255, 0)); // Primary colour
    }
	if ((sequence == 2) || (sequence == 4))
	{
        return (hsv2rgb(positionP3, 255, 255, 0)); // Primary colour
    }
	return (hsv2rgb(positionC, 255, 255, 0)); //30 degrees clockwise
}