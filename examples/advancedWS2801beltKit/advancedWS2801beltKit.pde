//BUG LIST:
// - Phaser seems to lock buttons

/* Adapted by MEO for WS2801 LED bulb string 
Programmed for the Due - so 100+ bulbs and fast frame rates now possible! */

/* ToDo: Functionallity
	- Frame rate controlled by potentiometer
	-	or... Speed parameter (e.g. Rainbow's: IntVar 0; Sine's: IntVar 1; Phasing's rate/switchHalf/Full)
	-	global speed ver is mapped onto values suitable for Program
	- buttons to change programs / variations / choose random / switch off
	- replace common vars with named ones (like current frame, main hue etc)
	- choose fade effect button

	- use table similar to dampingTable for larson/random strobe - so can have variable level of trail fade

/* ToDo: Patterns Ideas

- various from: https://www.youtube.com/watch?v=zMKf98MpaUg / http://www.youtube.com/watch?v=w557LuVueXg&feature=player_embedded

- flames (flag?? R/Y)

- whites
    r = 255; g = 147; b = 41; //-CANDLE - 1900
    r = 255; g = 197; b = 143; //-40W TUNG - 2600
    r = 255; g = 214; b = 170; //-100W TUNG - 2850
    r = 255; g = 241; b = 224; //-HALOGEN - 3200
    r = 255; g = 250; b = 244; //-CARBON ARC - 5200
    r = 255; g = 255; b = 251; //-HIGH NOON SUN - 5400
    r = 255; g = 255; b = 255; //-DIRECT SUN - 6000
    r = 201; g = 226; b = 255; //-OVERCAST SKY - 7000
    r = 64; g = 156; b = 255; //-CLEAR BLUE SKY - 20000 

- Candles:
	gently flickering very warm white (all bulbs flicker differently - flames?)

- standard rainbow at low brightness. Shoot white trail in opps direction
	- rainbow: hsl2rgb(rainbowcolor, 255, 15) --->
	- white:   hsl2rgb(rainbowcolor, 0 + fade, (255 - fade) stop at 15)<---

*/

// THIS PROGRAM *WILL* *NOT* *WORK* ON REALLY int LED STRIPS.  IT USES
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
#include "ARMtimer.h"
#include "Keypad.h"
#include "LiquidCrystal.h"

#define pgm_read_byte(x) (*(x))
#define NUM_PIXELS 100
#define FRAMES_PER_SECOND 60
#define FADE_FRAMES 256   //number of frames to crossfade within
#define STAY_FRAMES 2000 //number of frames to show a program - if multiple of half num pixels, then some programs won't run into each other (eg random strobe fade)
#define MAX_LEVEL 256 //max R,G,B or S, V levels (note: need to subtract one to make 0 based)

#define PI 3.14159265

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

// Membrane 4x4 Keypad setup:
const byte KEYPAD_ROWS = 4; //four KEYPAD_ROWS
const byte KEYPAD_COLS = 4; //four columns
//define the cymbols on the buttons of the keypads
char keyTable[KEYPAD_ROWS][KEYPAD_COLS] = {
  {'1','2','3','A'},
  {'4','5','6','B'},
  {'7','8','9','C'},
  {'*','0','#','D'}};
char matrixJustPressed = ' ';
byte rowPins[KEYPAD_ROWS] = {39, 41, 43, 45}; //connect to the row pinouts of the keypad
byte colPins[KEYPAD_COLS] = {47, 49, 51, 53}; //connect to the column pinouts of the keypad
Keypad customKeypad = Keypad(makeKeymap(keyTable), rowPins, colPins, KEYPAD_ROWS, KEYPAD_COLS);

//buttons
#define BUTTON_PROG_UP 0
#define BUTTON_RANDOM 6
#define BUTTON_ONOFF 7

//states
bool justPressedOnOff, desireOff, turningOff, turningOn, isOff;
bool desireRandom = true;
bool desireProgChangeUp = false;
bool desireProgChangeDn = false;
bool desirePattChangeUp = false;
bool desirePattChangeDn = false;
bool desireFadeChangeUp = false;
bool desireFadeChangeDn = false;
int nextProgram = 1;
int nextPattern = 0; //ToDo
int nextFade = 0; //ToDo
int brightness = 8; //ToDo
int speed = 5; //ToDo


// initialize the LCD library with the numbers of the interface pins
LiquidCrystal lcd(12, 11, 5, 4, 3, 2);


//table of powers for damping used in ProgramRandomSplash [pow(damping, frame) - damping^frame]
#define damping 0.90
float dampingTable[100];

int numPrograms = 0;

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
bool fxInitialised[3];			// Whether to set initialisation variables, or already fxInitialised
int fxIntVars[3][11],				// Effect instance variables (explained later)
	fxArrVars[3][2][10],			// MEO: 2 x Array
	fxFrameCount[3],				// MEO: current overall frame count of single effect
	fxFrameDelay[3],			// MEO: if too fast - can set number of frames to pause
	fxFrameDelayCount[3],		// MEO: counter for fxFrameDelay
	tCounter   = -1,				// Countdown to next transition
	transitionTime;					// Duration (in frames) of current transition
float fxFltVars[3][6];				// MEO: float variables
bool fxBlnVars[3][3];				// MEO: bool variables

bool randProg = true;
bool lightsOn = true;

// Chaser functions
void SetChaserColor(int bulb, int color, byte idx);
void FillChaserSeq(int count, int sequence,
                               int span_size, int startColor, int (*sequence_func)(int sequence, int startColor), byte idx);

// Crossfade functions
void crossfadeSimple(void);
void crossfadeWipe(void);
void crossfadeDither(void);

//Programs
void ProgramOff(byte idx);
void ProgramLarsonScanner(byte idx);
void ProgramRandomSplash(byte idx);
void ProgramStrobeFade(byte idx);

volatile void CheckSwitches(void);
volatile void LightFrame(void);

byte getGamma(byte x);
int HSVtoRGB(int h, byte s, byte v, int wheelLine);
char FixedSine(int angle);
char FixedCosine(int angle);

// List of image effect and alpha channel rendering functions; the code for
// each of these appears later in this file.  Just a few to start with...
// simply append new ones to the appropriate list here:
void (*renderEffect[])(byte) = {
			ProgramOff,
			//ProgramSolidColor,
			//ProgramRotatingRainbow,
			//ProgramSineWave, //affected by FixedSine/FixedCosine issue - temp fixed by using proper Sin
			//ProgramWavyFlag, //affected by FixedSine/FixedCosine issue -temp fixed by using proper Cos
			//ProgramPulse,
			//ProgramPhasing,
			//ProgramSimplexNoise,
			//ProgramRandomStrobe,
			//ProgramFlames,
			//ProgramChaser,
			//ProgramLarsonScanner,
			//ProgramOldFashioned,
			//ProgramRotatingCircles,
			//ProgramRainbowWhite,
			//ProgramRandomSplash,
			//ProgramStrobeFade,
			ProgramComet},
	  (*renderAlpha[])(void) = {
			//crossfadeDither,
			//crossfadeWipe,
			crossfadeSimple};
	
// ---------------------------------------------------------------------------

void setup() {
	// set up the LCD's number of columns and rows: 
	lcd.begin(16,2);

	startTimer(TC1, 0, TC3_IRQn, 61, LightFrame);  //61/67 are primes, so should never be a same time
    //startTimer(TC0, 0, TC0_IRQn, 67, CheckSwitches);

	// Open serial communications and wait for port to open:
	Serial.begin(115200);

	// Start up the LED pixelString.  Note that pixelString.show() is NOT called here --
	// the LightFrame function will be invoked immediately when attached, and
	// the first thing the calback does is update the pixelString.
	pixelString.begin();

	// Initialize random number generator from a floating analog input.
	randomSeed(analogRead(0));
	memset(imgData, 0, sizeof(imgData)); // Clear image data

	fxIdx[0] = 0; //crossfade in from ProgramOff()
	fxIdx[1] = 0; //crossfade in from ProgramOff()

	fxIntVars[backImgIdx][0] = 1;           // Mark back image as initialized

	//set up the damping table (replaces pow function which is far too slow)
	for (int table = 0; table < 100; table++)
	{
		dampingTable[table] = pow(damping, table);
	}

	numPrograms = (sizeof(renderEffect) / sizeof(renderEffect[0])) - 1 ;//remember includes ProgramOff, so subtracted 1
	Serial.print("Number of programs: ");Serial.println(numPrograms);

	//initial display values:
	lcd.setCursor(15, 1);
	lcd.print("#");
}

void loop() {
	//required by Ardunino compiler - but all my code in interrupt handlers
}


//###############################

//pushbuttons
//ToDo: Utilise keypad to allow direct choosing of programs - e.g.
//		"A01" - chooses program 1
//		"A08" - chooses program 8 (if higher than max, then just ignore)
//		"B01" - chooses fade 1
//		"C01" - brightess level 1
//		"D01" - color variation? or add rotary dialer for this?
//		- needs to accept sequence of letter and two numbers (ignore other combos)
volatile void CheckSwitches(void) {
	byte frontImgIdx = 1 - backImgIdx;
	char customKey = customKeypad.getKey();
  
	if (customKey){
		Serial.println(customKey);
		switch (customKey) {
			case '*':
				desireOff = !desireOff;
				if (desireOff) {
					Serial.print("Desire off: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
				} else {
					Serial.print("Desire on: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
				}
				break;
			case '#':
				desireRandom = !desireRandom;
				lcd.setCursor(15, 1);
				if (desireRandom) {
					Serial.print("Random Program: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
					lcd.print("#");
				} else {
					Serial.print("Fixed Program: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
					lcd.print("=");
				}
				break;
			case '1':
				desireProgChangeUp = true;
				Serial.print("Desire Prog Change Up: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
				break;
			case '2':
				desireProgChangeDn = true;
				Serial.print("Desire Prog Change Down: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter);
				break;
			case '3':
				speed += 1;
				if (speed == 10) {
					speed = 9;
				}
				Serial.print("Speed Up: ["); Serial.println(speed); 
				break;
			case '4':
				speed -= 1;
				if (speed == 0) {
					speed = 1;
				}
				Serial.print("Speed Down: ["); Serial.println(speed);
				break;
			case '5':
				brightness += 1;
				if (brightness == 9) {
					brightness = 8;
				}
				Serial.print("Brightness Up: ["); Serial.println(brightness); 
				break;
			case '6':
				brightness -= 1;
				if (brightness == 0) {
					brightness = 1;
				}
				Serial.print("Brightness Down: ["); Serial.println(brightness);
				break;
			case '7':
				desirePattChangeUp = true;
				Serial.print("Desire Pattern Change Up: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
				break;
			case '8':
				desirePattChangeDn = true;
				Serial.print("Desire Pattern Change Down: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter);
				break;
			case '9':
				desireFadeChangeUp = true;
				Serial.print("Desire Fade Change Up: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
				break;
			case '0':
				desireFadeChangeDn = true;
				Serial.print("Desire Fade Change Down: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter);
				break;
			case 'A':
				break;
			case 'B':
				break;
			case 'C':
				break;
			case 'D':
				break;
		}
		customKey = ' ';
	} else {
		customKey = ' ';
	}
}

volatile void LightFrame(void) {
	// Very first thing here is to issue the pixelString data generated from the
	// *previous* LightFrame.  It's done this way on purpose because show() is
	// roughly constant-time, so the refresh will always occur on a uniform
	// beat with respect to the Timer1 interrupt.  The various effects
	// rendering and compositing code is not constant-time, and that
	// unevenness would be apparent if show() were called at the end.
	pixelString.show();

	CheckSwitches(); //used to have it's own interrupt, but seems ok sharing - test both ways fully

	// tCounter counts from *minus* STAY_FRAMEs to 0, where transition starts,
	// then up to *plus* FADE_FRAMES

	byte frontImgIdx = 1 - backImgIdx,
		*backPtr = &imgData[backImgIdx][0],
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

	//immediately set counter to fire off next transition, if...
	// not already turning off, and want off and is on
	// not already turning on, and want on, and is off
	if ((desireOff && !turningOff && !isOff) || (!desireOff && !turningOn && isOff)) {
		if (tCounter > 0) {
			Serial.print("Already in transition... wait..." ); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
		} else {
			tCounter = 0;
			if (desireOff) {
				turningOff = true;
				turningOn = false;
				Serial.print("Turning off: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
			} else {
				turningOn = true;
				turningOff = false;
				fxIdx[backImgIdx] = 0; //ensure coming on from ProgramOff
				Serial.print("Turning on: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
			}
		}
	}

	if (desireProgChangeUp || desireProgChangeDn)	{
		tCounter = 0;
	}

	if(tCounter == 0) { // Transition start
		if (turningOff) {
			fxIdx[frontImgIdx] = 0;
		} else {
			if (desireRandom) {
				// Randomly pick next image effect
				fxIdx[frontImgIdx] = 1 + random(numPrograms); //+1 so that doesn't run ProgramOff()
			} else {
				if (desireProgChangeUp){
					desireProgChangeUp = false;
					fxIdx[frontImgIdx] = 1 + nextProgram;
					if (fxIdx[frontImgIdx] == numPrograms + 1) { //loop if necessary
						fxIdx[frontImgIdx] = 1;
					}
					Serial.print("Next Program +: " ); Serial.println(fxIdx[frontImgIdx]);
				} else if (desireProgChangeDn) {
					desireProgChangeDn = false;
					fxIdx[frontImgIdx] = nextProgram - 1;
					if (fxIdx[frontImgIdx] == 0) { //loop if necessary
						fxIdx[frontImgIdx] = numPrograms;
					}
					Serial.print("Next Program -: " ); Serial.println(fxIdx[frontImgIdx]);
				}
			}
		}
		nextProgram  = fxIdx[frontImgIdx];

		//randomly pick next fade effect
		fxIdx[2] = random((sizeof(renderAlpha) / sizeof(renderAlpha[0])));
		nextFade = fxIdx[2];

		transitionTime = FADE_FRAMES;
		fxInitialised[frontImgIdx] = false; // Effect not yet initialized
		fxInitialised[2] = false; // Transition not yet initialized
	} else if(tCounter >= transitionTime) { // End transition
		fxIdx[backImgIdx] = fxIdx[frontImgIdx]; // Move front effect index to back
		backImgIdx = 1 - backImgIdx;     // Invert back index

		//transition finished, so mark as switched on or off, if was turning on or off
		if (turningOff) {
			isOff = true;
			Serial.print("Is off: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
		}
		if (turningOn) {
			isOff = false;
			Serial.print("Is on: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
		}
		//transition finished, so no longer turning on or off
		turningOff = false;
		turningOn = false;
		//if not randomised, then set transition time to very long
		if (desireRandom) {
			tCounter = -STAY_FRAMES; //-120 - random(240); // Hold image 2 to 6 seconds
		} else {
			tCounter = -99999999; //days worth
		}
		//regardless of randomised or not, if is off, set transition time to very long
		if (isOff) {
			tCounter = -99999999; //days worth
		}
		Serial.print("Timer reset: ["); Serial.print(fxIdx[frontImgIdx]); Serial.print(" / "); Serial.print(fxIdx[backImgIdx]); Serial.print("] "); Serial.println(tCounter); 
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

// Simulate being off, by turn all bulbs to black
void ProgramOff(byte idx) {
	// Only needs to be rendered once, when effect is initialized:
	if(fxInitialised[idx] == false) {
		lcd.setCursor(0, 0);
		lcd.print("Off             ");
		byte *ptr = &imgData[idx][0];
		for(int i=0; i<NUM_PIXELS; i++) {
			*ptr++ = 0; *ptr++ = 0; *ptr++ = 0;
		}
		fxInitialised[idx] = true; // Effect initialized
	}
}


// Simplest rendering effect: fill entire image with solid color
void ProgramSolidColor(byte idx) {
	// Only needs to be rendered once, when effect is initialized:
	if(fxInitialised[idx] == false) {
		lcd.setCursor(0, 0);
		lcd.print("Solid Colour    ");
		int color;
		color = HSVtoRGB(random(1536), 255, 255, 0);

		byte *ptr = &imgData[idx][0];
		for(int i=0; i<NUM_PIXELS; i++) {
			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}
		fxInitialised[idx] = true; // Effect initialized
	}
}


// Rainbow effect (1 or more full loops of color wheel at 100% saturation).
// Not a big fan of this pattern (it's way overused with LED stuff), but it's
// practically part of the Geneva Convention by now.
void ProgramRotatingRainbow(byte idx) {
	if(fxInitialised[idx] == false) { // Initialize effect?
		lcd.setCursor(0, 0);
		lcd.print("Rainbow         ");
		// Number of repetitions (complete loops around color wheel); any
		// more than 4 per meter just looks too chaotic and un-rainbow-like.
		// Store as hue 'distance' around complete belt:
		fxIntVars[idx][0] = 0; //1536; //(4 + random(1 * ((NUM_PIXELS + 31) / 32))) * 1536;  //1 was 4
		// Frame-to-frame hue increment (speed) -- may be positive or negative,
		// but magnitude shouldn't be so small as to be boring.  It's generally
		// still less than a full pixel per frame, making motion very smooth.
		fxIntVars[idx][1] = 20;//4 + random(fxIntVars[idx][1]) / NUM_PIXELS;  //1 was 4
		// Reverse speed and hue shift direction half the time.
		if(random(2) == 0) fxIntVars[idx][0] = -fxIntVars[idx][0];
		if(random(2) == 0) fxIntVars[idx][1] = -fxIntVars[idx][1];
		fxIntVars[idx][2] = 0; // Current position
		fxIntVars[idx][3] = 1; //increase step 1 / decrease step 0
		fxIntVars[idx][4] = random(4); //full rainbow / RG only / GB / BR

		fxInitialised[idx] = true; // Effect initialized
	}

	byte *ptr = &imgData[idx][0];
	int color, i;
	for(i=0; i<NUM_PIXELS; i++) {
		color = HSVtoRGB(fxIntVars[idx][2] + fxIntVars[idx][0] * i / NUM_PIXELS,
			255, 255, fxIntVars[idx][4]);
		*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
	}
	fxIntVars[idx][2] += fxIntVars[idx][1];

	////Make a bit more interesing by gradually tightening rainbow span size
	//step in direction
	if (fxIntVars[idx][3] == 1)
	{
		fxIntVars[idx][0]++;
	} else {
		fxIntVars[idx][0]--;
	}
	//change direction
	if (fxIntVars[idx][0] == 2500)
	{
		fxIntVars[idx][3] = 0;
	}
	if (fxIntVars[idx][0] == -1)
	{
		fxIntVars[idx][3] = 1;
	}		
}

// Sine wave chase effect
void ProgramSineWave(byte idx) {
	if(fxInitialised[idx] == false) { // Initialize effect?
		lcd.setCursor(0, 0);
		lcd.print("Sine Wave       ");
		fxIntVars[idx][0] = random(3) * 512; //random(1536); // Random hue
		// Number of repetitions (complete loops around color wheel);
		// any more than 4 per meter just looks too chaotic.
		// Store as distance around complete belt in half-degree units:
		fxIntVars[idx][1] = (1 + random(4 * ((NUM_PIXELS + 31) / 32))) * 720;
		// Frame-to-frame increment (speed) -- may be positive or negative,
		// but magnitude shouldn't be so small as to be boring.  It's generally
		// still less than a full pixel per frame, making motion very smooth.
		fxIntVars[idx][2] = 4 + random(fxIntVars[idx][0]) / NUM_PIXELS;
		// Reverse direction half the time.
		if(random(2) == 0) fxIntVars[idx][2] = -fxIntVars[idx][2];
		fxIntVars[idx][3] = 0; // Current position
		//ToDo: Rainbow changing sine
		//ToDo: Rainbown spread across string sine
		fxIntVars[idx][4] = random(2) + 1; //number of half waves per string
		fxIntVars[idx][5] = random(2); //still colour or rainbow
		fxIntVars[idx][6] = random(4); //full rainbow or lines
		fxIntVars[idx][7] = 0; //start of rainbow

		fxInitialised[idx] = true; // Effect initialized
	}

	byte *ptr = &imgData[idx][0];
	int  foo;
	int color, i;
	float y;

	for(int i=0; i<NUM_PIXELS; i++) {
		// Peaks of sine wave are white, troughs are black, mid-range
		// values are pure hue (100% saturated).
		//>> Sine table way - need to fix
		////foo = FixedSine(fxIntVars[idx][4] + fxIntVars[idx][2] * i / NUM_PIXELS); //original 
		/*foo = (int)(sin(fxIntVars[idx][4] + fxIntVars[idx][2] * i / NUM_PIXELS) * 255); //fix attempt - almost works
		color = (foo >= 0) ?
			HSVtoRGB(fxIntVars[idx][1], 254 - (foo * 2), 255, 0) :
				HSVtoRGB(fxIntVars[idx][1], 255, 254 + foo * 2, 0);
		*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		//<<<<*/

		//>>> Non-Sine table way - slower, but works! Need fix for above
		y = sin(PI * (float)fxIntVars[idx][4] * 0.5 * 
			(float)(fxIntVars[idx][3] + (float)i) / (float)NUM_PIXELS) * 255.0;

		color = (y >= 0.0) ?
			// Peaks of sine wave are white (saturation = 0)
			color = HSVtoRGB(fxIntVars[idx][0]+(fxIntVars[idx][7]*fxIntVars[idx][5]), 255 - (int)y, 255, fxIntVars[idx][6]) :
				// troughs are black (level = 0)
				color = HSVtoRGB(fxIntVars[idx][0]+(fxIntVars[idx][7]*fxIntVars[idx][5]), 255, 255 + (int)y, fxIntVars[idx][6]);
		*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
	}
	fxIntVars[idx][3] += fxIntVars[idx][2];
	fxIntVars[idx][7]++;
}

// Data for American-flag-like colors (20 pixels representing
// blue field, stars and pixelStringes).  This gets "stretched" as needed
// to the full LED pixelString length in the flag effect code, below.
// Can change this data to the colors of your own national flag,
// favorite sports team colors, etc.  OK to change number of elements.
//MEO: ToDo: this doens't work properly because of the FixedSine/FixedCosine problem
#define USA_RED   160,   0,   0
#define USA_WHITE 255, 255, 255
#define USA_BLUE    0,   0, 100

#define WHITE_CANDLE 255, 147, 41 //-CANDLE - 1900
#define WHITE_40W 255, 157, 50 //-
#define BLACK 0, 0, 0

#define FLAME_YELLOW   255,   127,   0
#define FLAME_ORANGE 255, 47, 00
#define FLAME_RED    255,   0, 0

#define STD_RED 255,0,0
#define STD_GREEN 0,255,0
#define STD_BLUE 0,0,255

//cheesy RGB version
/*byte flagTable[] = {
	STD_RED, BLACK, STD_GREEN, BLACK, STD_BLUE, BLACK,
	STD_RED, BLACK, STD_GREEN, BLACK, STD_BLUE, BLACK,
	STD_RED, BLACK, STD_GREEN, BLACK, STD_BLUE, BLACK};*/

//flame effect version - RED/ORANGE - ORANGE/YELLOW
byte flagTable[]  = {
	FLAME_YELLOW, FLAME_ORANGE, FLAME_YELLOW , FLAME_ORANGE, FLAME_YELLOW, FLAME_ORANGE, FLAME_YELLOW,
	FLAME_ORANGE, FLAME_RED, FLAME_ORANGE, FLAME_RED, FLAME_ORANGE, FLAME_RED ,
	BLACK, FLAME_RED, BLACK, FLAME_RED, BLACK, FLAME_RED, BLACK };

//original USA flag version
/*byte flagTable[]  = {
	USA_BLUE , USA_WHITE, USA_BLUE, USA_WHITE, USA_BLUE, USA_WHITE, USA_BLUE,
	USA_RED  , USA_WHITE, USA_RED, USA_WHITE, USA_RED, USA_WHITE, USA_RED ,
	USA_WHITE, USA_RED, USA_WHITE, USA_RED, USA_WHITE, USA_RED };*/

//flickey candle version
/*byte flagTable[] = { WHITE_CANDLE, BLACK, WHITE_40W, BLACK,
	WHITE_CANDLE, BLACK, WHITE_40W, BLACK,
	WHITE_CANDLE, BLACK, WHITE_40W, BLACK,
	WHITE_CANDLE, BLACK, WHITE_40W, BLACK,
	WHITE_CANDLE, BLACK, WHITE_40W, BLACK,
	WHITE_CANDLE, BLACK, WHITE_40W, BLACK,
	WHITE_CANDLE, BLACK, WHITE_40W, BLACK,
	WHITE_CANDLE, BLACK, WHITE_40W, BLACK };*/

// Wavy flag effect
void ProgramWavyFlag(byte idx) {
	int i, sum, s, x;
	int  idx1, idx2, a, b;
	if(fxInitialised[idx] == false) { // Initialize effect?
		lcd.setCursor(0, 0);
		lcd.print("Wavy Flag       ");
		fxIntVars[idx][0] = 720 + random(720); // Wavyness
		fxIntVars[idx][1] = 1;//4 + random(10);    // Wave speed
		fxIntVars[idx][2] = 200 + random(200); // Wave 'puckeryness'
		fxIntVars[idx][3] = 0;                 // Current  position
		
		fxFrameDelay[idx] = 2; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true;                 // Effect initialized
	}

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) { //only do once every delay frames
		for(sum=0, i=0; i<NUM_PIXELS-1; i++) {
				sum += fxIntVars[idx][2] + (int)(cos((float)fxIntVars[idx][3] + (float)fxIntVars[idx][0] *
				(float)i / (float)NUM_PIXELS) * 255.0);
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

			s += fxIntVars[idx][2] + (int)(cos((float)fxIntVars[idx][3] + (float)fxIntVars[idx][0] *
				(float)i / (float)NUM_PIXELS) * 255.0);
		}

		fxIntVars[idx][3] += fxIntVars[idx][1];
		if(fxIntVars[idx][3] >= 720) fxIntVars[idx][3] -= 720;

		fxFrameDelayCount[idx] = 0;
	} else {
		fxFrameDelayCount[idx]++;
	}
}

// Pulse by elmerfud (http://forums.adafruit.com/viewtopic.php?f=47&t=29844&p=150244&hilit=advanced+belt#p150244)
// "I added a ... simple one that picks a color and pulses the entire strip.

// Pulse entire image with solid color
void ProgramPulse(byte idx) {
	if(fxInitialised[idx] == false) {
		lcd.setCursor(0, 0);
		lcd.print("Pulse           ");
		fxIntVars[idx][0] = 50; // Pulse ammount min (v)
		fxIntVars[idx][1] = 250; // Pulse ammount max (v)
		fxIntVars[idx][2] = random(1536); // Random hue

		fxIntVars[idx][3] = fxIntVars[idx][0]; // pulse position 
		fxIntVars[idx][4] = 1; // 0 = negative, 1 = positive
		fxIntVars[idx][5] = 2 + random(10); // step value

		fxFrameDelay[idx] = 0; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; // Effect initialized
	}

	byte *ptr = &imgData[idx][0];
	int color, i;

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) { //only do once every delay frames
		for(i=0; i<NUM_PIXELS; i++) {
			color = HSVtoRGB(fxIntVars[idx][2], 255, fxIntVars[idx][3], 0);
			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}

		if (fxIntVars[idx][4] == 0) {
			fxIntVars[idx][3] = fxIntVars[idx][3] - fxIntVars[idx][5];
			if (fxIntVars[idx][3] <= fxIntVars[idx][0]) {
				fxIntVars[idx][4] = 1;
				fxIntVars[idx][3] = fxIntVars[idx][0];
			}
		} else if (fxIntVars[idx][4] == 1) {
			fxIntVars[idx][3] = fxIntVars[idx][3] + fxIntVars[idx][5];
			if (fxIntVars[idx][3] >= fxIntVars[idx][1]) {
				fxIntVars[idx][4] = 0;
				fxIntVars[idx][3] = fxIntVars[idx][1];
			}
		}

		fxFrameDelayCount[idx] = 0;
	} else {
		fxFrameDelayCount[idx]++;
	}
}

//By Christopher De Vries <https://bitbucket.org/devries/arduino-tcl/src/1c93786ac579aea4bc07575c078caa051c4f53b7/examples/fire/fire.ino?at=default>.
//with modifications around movement by MEO
//ToDo: use forthcoming visual echo to interpolate between frames for smoother movement
void ProgramFlames(byte idx){
	if(fxInitialised[idx] == false) { // Initialize effect?
		lcd.setCursor(0, 0);
		lcd.print("Flames          ");

		fxIntVars[idx][0] = 101; //intensity Hi
		fxIntVars[idx][1] = 0; //intensity Lo
		fxIntVars[idx][2] = 101; //transition Hi
		fxIntVars[idx][3] = 0; //transition Lo
		fxIntVars[idx][4] = 1; //sub pattern/variation
		fxIntVars[idx][5] = 255; //Colour 1 R
		fxIntVars[idx][6] = 0; //Colour 1 G //ToDo: redo these as single vars
		fxIntVars[idx][7] = 0; //Colour 1 B
		fxIntVars[idx][8] = 255; //Colour 2 R
		fxIntVars[idx][9] = 145; //Colour 2 G
		fxIntVars[idx][10] = 0; //Colour 2 B

		fxFrameDelay[idx] = 4; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; //end initialise
	}

	byte *ptr = &imgData[idx][0];

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) //only do once every delay frames
	{
		int transition, intensity;
		byte r, g, b;
		for(int i = 0; i < NUM_PIXELS; i++) {
			transition = (int)random(fxIntVars[idx][3], fxIntVars[idx][2]);
			intensity = (int)random(fxIntVars[idx][1], fxIntVars[idx][2]);

			r = ((fxIntVars[idx][8]-fxIntVars[idx][5])*transition/100+fxIntVars[idx][5])*intensity/100;
			g = ((fxIntVars[idx][9]-fxIntVars[idx][6])*transition/100+fxIntVars[idx][6])*intensity/100;
			b = ((fxIntVars[idx][10]-fxIntVars[idx][7])*transition/100+fxIntVars[idx][7])*intensity/100;
			*ptr++ = r; *ptr++ = g; *ptr++ = b;
		}	
		fxFrameDelayCount[idx] = 0;
	} else {
		fxFrameDelayCount[idx]++;
	}
}

//MEO Effects...

// Color phasing (inspired by: http://krazydad.com/tutorials/makecolors.php)
//ToDo: re-implement 'turn' from pattern 9
//      also use turn to swap phase 1.0 / 0.0
//		e.g. fstep 0 -> 400 = 1 0 1; 400 -> = 0 1 0; 0 -> 400 = 0 1 0; 400 -> 0 = 1 0 1

//why does this program break the button pressing??

#define rate 1000.0 //2000.0 //size or rate of change, or how much moves at a time, or summat (larger takes longer)
#define switchHalf 1000 //2000 //should be related to rate (e.g. rate=100.0, this 100)
#define switchFull 2000 //4000

void ProgramPhasing(byte idx) {
	if(fxInitialised[idx] == false) {
		lcd.setCursor(0, 0);
		lcd.print("Phasing         ");

		fxIntVars[idx][0] = 0;  //start step (fStep in 2012 version) - freq modifier
		fxIntVars[idx][1] = random(32); //sub-pattern / variation
		fxIntVars[idx][2] = 0; //pStep in 2012 version - phase modifier
		fxIntVars[idx][3] = 1; //direction (1 forward / 0 backwards)
		fxIntVars[idx][4] = 0; //turn - sub-sub-variation

		//The following variables are used, but not necessarily initialised here
		//fxFltVars[idx][0] - frequency Red
		//fxFltVars[idx][1] - frequency Green
		//fxFltVars[idx][2] - frequency Blue
		//fxFltVars[idx][3] - phase Red
		//fxFltVars[idx][4] - phase Green
		//fxFltVars[idx][5] - phase Blue
		//fxBlnVars[idx][0] - red override (whether to override-and switch red channel off)
		//fxBlnVars[idx][1] - green override
		//fxBlnVars[idx][2] - blue override

		fxBlnVars[idx][0] = false; //these may get over rided in following switch.
		fxBlnVars[idx][1] = false; 
		fxBlnVars[idx][2] = false;

		// this switch displays the variation on the LCD, and sets the *fixed* values
		// Note: the same variables are not always the fixed ones
		// ToDo: put LCD varitions up for 20-31
		lcd.setCursor(0, 1);
		switch (fxIntVars[idx][1]) {
			case 0:  //Wavey pastels (Green 'peak')
				lcd.print("Wavey Pastels  ");

				fxFltVars[idx][3] = 0;
				fxFltVars[idx][4] = 2.0 * PI /3.0;
				fxFltVars[idx][5] = 4.0 * PI /3.0;
				break;
			case 1: // subtly changing pastel
				lcd.print("Subtle Pastels ");

				fxFltVars[idx][3] = 0;
				fxFltVars[idx][0] = 1.666;
				fxFltVars[idx][1] = 2.666;
				fxFltVars[idx][2] = 3.666;
				break;
			case 2: //White
				lcd.print("White          ");

				fxFltVars[idx][3] = 1.0;
				fxFltVars[idx][4] = 1.0;
				fxFltVars[idx][5] = 1.0;
				break;
			case 3: //Cyan/Red/White (Cyan 'peak')
				lcd.print("Cyan / R / W   ");

				fxFltVars[idx][3] = 0.0;
				fxFltVars[idx][4] = 1.0;
				fxFltVars[idx][5] = 1.0;
				break;
			case 4: //Magenta/Green/White (Magenta 'peak')
				lcd.print("Magenta / G / W");

				fxFltVars[idx][3] = 1.0;
				fxFltVars[idx][4] = 0.0;
				fxFltVars[idx][5] = 1.0;
				break;
			case 5: //Yellow/Blue/White (Yellow 'peak')
				lcd.print("Yellow / B / W ");

				fxFltVars[idx][3] = 1.0;
				fxFltVars[idx][4] = 1.0;
				fxFltVars[idx][5] = 0.0;
				break;
			case 6:  //nothing - a still pastel rainbow 
				lcd.print("Still Pastels  ");

				fxFltVars[idx][3] = 2.0 * PI /3.0;
				fxFltVars[idx][4] = 4.0 * PI /3.0;
				fxFltVars[idx][5] = 0.0;
				fxFltVars[idx][0] = 0.06;
				fxFltVars[idx][1] = 0.06;
				fxFltVars[idx][2] = 0.06;
				break;
			case 7: //Evolving pastel wave - 6 sub variations
				lcd.print("Evolving Pastel");
				break;
			case 8: //Red/Blue/Magenta (Red 'peak')
				lcd.print("Red / B / M    ");

				fxFltVars[idx][3] = 0.0;
				fxFltVars[idx][4] = 2.0 * PI /3.0;
				fxFltVars[idx][5] = 4.0 * PI /3.0;	
				fxBlnVars[idx][1] = true; //switch off green channel
				break;
			case 9: //Green/Red/Yellow (Green 'peak')
				lcd.print("Green / R / Y  ");

				fxFltVars[idx][3] = 0.0;
				fxFltVars[idx][4] = 2.0 * PI /3.0;
				fxFltVars[idx][5] = 4.0 * PI /3.0;
				fxBlnVars[idx][2] = true; //switch off blue channel
				break;
			case 10: //Blue/Green/Cyan (Blue 'peak')
				lcd.print("Blue / G / C   ");

				fxFltVars[idx][3] = 0.0;
				fxFltVars[idx][4] = 4.0 * PI /3.0;
				fxFltVars[idx][5] = 2.0 * PI /3.0;
				fxBlnVars[idx][0] = true; //switch off red channel
				break;
			case 11: //Cyan/Green/Red/Magenta slightly askew (Cyan 'peak')
				lcd.print("C / G / R / M  ");

				fxFltVars[idx][3] = 0.0;
				fxFltVars[idx][4] = 2.0 * PI /3.0;
				fxFltVars[idx][5] = 1.0;
				break;
			case 12: //Magenta/Green/Blue/Cyan slightly askew (Magenta 'peak')
				lcd.print("M / G / B / C  ");

				fxFltVars[idx][3] = 1.0;
				fxFltVars[idx][4] = 0.0;
				fxFltVars[idx][5] = 2.0 * PI /3.0;
				break;
			case 13: //Yellow/Blue/Red/Cyan slightly askew (Yellow 'peak')
				lcd.print("Y / B / R / C  ");

				fxFltVars[idx][3] = 2.0 * PI /3.0;
				fxFltVars[idx][4] = 1.0;
				fxFltVars[idx][5] = 0.0;
				break;
			case 14:  //Green/Red/Yellow slightly askew (Green 'peak')
			case 20: 
			case 26:
				lcd.print("G / R / Y      ");

				fxFltVars[idx][3] = 0.0;
				fxFltVars[idx][4] = 2.0 * PI /3.0;
				fxFltVars[idx][5] = 4.0 * PI /3.0;
				fxFltVars[idx][2] = 0.0;
				break;
			case 15:  //Blue/Green/Cyan slightly askew (Blue 'peak')
			case 21:
			case 27:
				lcd.print("B / G / C      ");

				fxFltVars[idx][3] = 4.0 * PI /3.0;
				fxFltVars[idx][4] = 0.0;
				fxFltVars[idx][5] = 2.0 * PI /3.0;
				fxFltVars[idx][0] = 0.0;
				break;
			case 16:  //Red/Blue/Magenta slightly askew (Magenta 'peak')
			case 22:
			case 28:
				lcd.print("R / B / M      ");
				
				fxFltVars[idx][3] = 2.0 * PI /3.0;
				fxFltVars[idx][4] = 4.0 * PI /3.0;
				fxFltVars[idx][5] = 0.0;
				fxFltVars[idx][1] = 0.0;
				break;
			case 17: //Blue (White 'peak') - 'White' is a touch complementary color
			case 23:
			case 29:
				lcd.print("Blue & White    ");

				fxFltVars[idx][3] = 1.0;
				fxFltVars[idx][4] = 1.0;
				fxFltVars[idx][5] = 0.0;
				fxFltVars[idx][2] = 0.0;
				break;
			case 18: //Red (White 'peak') - 'White' is a touch complementary color
			case 24:
			case 30:
				lcd.print("Red & White     ");

				fxFltVars[idx][3] = 0.0;
				fxFltVars[idx][4] = 1.0;
				fxFltVars[idx][5] = 1.0;
				fxFltVars[idx][0] = 0.0;
				break;
			case 19: //Green (White 'peak') - 'White' is a touch complementary color
			case 25:
			case 31:
				lcd.print("Green & White   ");

				fxFltVars[idx][3] = 1.0;
				fxFltVars[idx][4] = 0.0;
				fxFltVars[idx][5] = 1.0;
				fxFltVars[idx][1] = 0.0;
				break;
		}

		fxFrameDelay[idx] = 0; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; // Effect initialized
	}

	// this switch sets the *variable* variables! (again, not necessarily the same ones)
	switch (fxIntVars[idx][1]) {
		case 0:  //Wavey pastels (Green 'peak')
		case 2: //White
		case 3: //Cyan/Red/White (Cyan 'peak')
		case 4: //Magenta/Green/White (Magenta 'peak')
		case 5: //Yellow/Blue/White (Yellow 'peak')
		case 8: //Red/Blue/Magenta (Red 'peak')
		case 9: //Green/Red/Yellow (Green 'peak')
		case 10: //Blue/Green/Cyan (Blue 'peak')
		case 11: //Cyan/Green/Red/Magenta slightly askew (Cyan 'peak')
		case 12: //Magenta/Green/Blue/Cyan slightly askew (Magenta 'peak')
		case 13: //Yellow/Blue/Red/Cyan slightly askew (Yellow 'peak')
			fxFltVars[idx][0] = (float)fxIntVars[idx][0] / rate;
			fxFltVars[idx][1] = (float)fxIntVars[idx][0] / rate;
			fxFltVars[idx][2] = (float)fxIntVars[idx][0] / rate;
			break;
		case 1: // subtly changing pastel
			fxFltVars[idx][4] = (2.0 * PI /360.0) * (float)fxIntVars[idx][0];
			fxFltVars[idx][5] = (4.0 * PI /360.0) * (float)fxIntVars[idx][0];
			break;
		case 6: //Single primary (White 'peak') - 'White' is a touch complementary color
			break;
		case 7: //Evolving pastel wave - 6 sub variations
			fxFltVars[idx][0] = (float)fxIntVars[idx][0] / rate;
			fxFltVars[idx][1] = (float)fxIntVars[idx][0] / rate;
			fxFltVars[idx][2] = (float)fxIntVars[idx][0] / rate;
			float temp;
			temp = (PI /360.0) * (float)fxIntVars[idx][0];
			switch (fxIntVars[idx][4] % 6) {
				case 0: //these sub variations are all pretty similar
					fxFltVars[idx][3] = 0.0 * temp;
					fxFltVars[idx][4] = 2.0 * temp;
					fxFltVars[idx][5] = 4.0 * temp;
					break;
				case 2:
					fxFltVars[idx][3] = 4.0 * temp;
					fxFltVars[idx][4] = 0.0 * temp;
					fxFltVars[idx][5] = 2.0 * temp;
					break;
				case 4:
					fxFltVars[idx][3] = 2.0 * temp;
					fxFltVars[idx][4] = 4.0 * temp;
					fxFltVars[idx][5] = 0.0 * temp;
					break;
				case 1:
					fxFltVars[idx][3] = 0.0 * temp;
					fxFltVars[idx][4] = 4.0 * temp;
					fxFltVars[idx][5] = 2.0 * temp;
					break;
				case 3:
					fxFltVars[idx][3] = 4.0 * temp;
					fxFltVars[idx][4] = 2.0 * temp;
					fxFltVars[idx][5] = 0.0 * temp;
					break;
				case 5:
					fxFltVars[idx][3] = 2.0 * temp;
					fxFltVars[idx][4] = 0.0 * temp;
					fxFltVars[idx][5] = 4.0 * temp;
					break;
			}
			break;
		case 14: //Green/Red/Yellow slightly askew (Green 'peak')
		case 17: //Blue & White (White 'peak')
			fxFltVars[idx][0] = (float)fxIntVars[idx][0] / rate; 
			fxFltVars[idx][1] = (float)fxIntVars[idx][0] / rate; 
			break;
		case 15: //Blue/Green/Cyan slightly askew (Blue 'peak')
		case 18: //Red & White (White 'peak')
			fxFltVars[idx][1] = (float)fxIntVars[idx][0] / rate;
			fxFltVars[idx][2] = (float)fxIntVars[idx][0] / rate; 
			break;
		case 16:  //Red/Blue/Magenta slightly askew (Magenta 'peak')
		case 19: //Green & White (White 'peak')
			fxFltVars[idx][0] = (float)fxIntVars[idx][0] / rate;
			fxFltVars[idx][2] = (float)fxIntVars[idx][0] / rate;
			break;

		case 20: //Green/Magenta (Green 'peak')
		case 23: //Magenta & White (White 'peak')
			fxFltVars[idx][0] = 0;
			fxFltVars[idx][1] = (float)fxIntVars[idx][0] / rate;
			break;
		case 21: //Cyan/Green (Cyan 'peak')
		case 24: //Yellow & White (White 'peak')
			fxFltVars[idx][1] = 0; //in case 17: 0 would make white/yellow
			fxFltVars[idx][2] = (float)fxIntVars[idx][0] / rate; //in case 17: 0 would make white/weak mageneta
			break;
		case 22: //Magenta/Red (Magenta 'peak')
		case 25: //Cyan/Green (Cyan 'peak') variation
			fxFltVars[idx][0] = 0;
			fxFltVars[idx][2] = (float)fxIntVars[idx][0] / rate;
			break;

		case 26: //Yellow/Green (Yellow 'peak')
		case 29: //Cyan & White (White 'peak')
			fxFltVars[idx][0] = (float)fxIntVars[idx][0] / rate;
			fxFltVars[idx][1] = 0; // in case 14: 0 makes green/yellow
			break;
		case 27: //Cyan/Blue (Cyan 'peak')
		case 30: //Cyan/Magenta (Cyan 'peak')
			fxFltVars[idx][1] = (float)fxIntVars[idx][0] / rate;
			fxFltVars[idx][2] = 0; //in case 17: 0 would make white/weak mageneta
			break;
		case 28:  //Magenta/Blue (Magenta 'peak')
		case 31: //Cyan/White (White 'peak') variation
			fxFltVars[idx][0] = (float)fxIntVars[idx][0] / rate;
			fxFltVars[idx][2] = 0;
			break;
	}

	byte *ptr = &imgData[idx][0];

	for(int i=0; i<NUM_PIXELS; i++) {
		if (fxBlnVars[idx][0]) {
			*ptr++ = 0; 
		} else {
			*ptr++ = int(sin(fxFltVars[idx][0] * i + fxFltVars[idx][3]) * (((float)MAX_LEVEL / 2.0) - 1.0) + ((float)MAX_LEVEL / 2.0));
		}
		if (fxBlnVars[idx][1]) {
			*ptr++ = 0;
		} else {
			*ptr++ = int(sin(fxFltVars[idx][1] * i + fxFltVars[idx][4]) * (((float)MAX_LEVEL / 2.0) - 1.0) + ((float)MAX_LEVEL / 2.0));
		}
		if (fxBlnVars[idx][2]) {
			*ptr++ = 0;
		} else {
			*ptr++ = int(sin(fxFltVars[idx][2] * i + fxFltVars[idx][5]) * (((float)MAX_LEVEL / 2.0) - 1.0) + ((float)MAX_LEVEL / 2.0));
		}
	}

	//step up in general
	fxIntVars[idx][2]++;

	//step in direction
	if (fxIntVars[idx][3] == 1) {
		fxIntVars[idx][0]++;
	} else {
		fxIntVars[idx][0]--;
	} 

	//set reverse direction: 0 1 2 .. 98 99 .. 399 400 399 .. 99 98 .. 2 1
	if (fxIntVars[idx][2] == switchHalf) { 
		fxIntVars[idx][3] = 0;
	}
	//repeat when finished 0 1 2 .. 799 800 0 1 2 .. 799 800
	if (fxIntVars[idx][2] == switchFull) {
		fxIntVars[idx][2] = 0;
	} 

	//set forward direction: 0 1 2 .. 98 99 .. 399 400 399 .. 99 98 .. 2 1
	//and increment sub-sub-variation counter
	if (fxIntVars[idx][0] == 0) {
		fxIntVars[idx][3] = 1;
		fxIntVars[idx][4]++;
	} 
}


// Random strobe effect 
//(inspired by the Eiffel Tower! : https://www.youtube.com/watch?v=pH2_mnh1XFE)
// Note: currently only works with 50, 100 or 160 pixels (easy to add more)
//To Do - see if can use my code to generate non repeating random nos on the fly
void ProgramRandomStrobe(byte idx) {
	if(fxInitialised[idx] == false) {
		lcd.setCursor(0, 0);
		lcd.print("Random Strobe   ");
		fxIntVars[idx][0] = 0; // Current position
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

		// ToDo: make number of bulbs at a time work
		// ToDo: slow down, by having bulbs stay same for a number of frames

		fxInitialised[idx] = true; // Effect initialized
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

	int color;
	for(int i = 0 ; i < NUM_PIXELS ; i++) {
		if (GetRandom(i, NUM_PIXELS) == fxIntVars[idx][2]) {
			if (rainbowFlash_) {
				int color;
				color = HSVtoRGB(fxIntVars[idx][0] + fxIntVars[idx][3] 
					* i / NUM_PIXELS, 255, 255, 0);
				*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
			} else {
				*ptr++ = rFlash; *ptr++ = gFlash; *ptr++ = bFlash;
			}
		} else {
			if (rainbowMain_)
			{
				color = HSVtoRGB((fxIntVars[idx][0] + fxIntVars[idx][3] 
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

	fxIntVars[idx][0] += fxIntVars[idx][4];
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

void ProgramSimplexNoise(byte idx) {
	if(fxInitialised[idx] == false) {
		lcd.setCursor(0, 0);
		lcd.print("Simplex Noise   ");
		fxIntVars[idx][0] = random(7); //sub pattern/variation
		fxFltVars[idx][0] = 0.0; //yOffset
		fxInitialised[idx] = true; // Effect initialized
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

	switch (fxIntVars[idx][0])
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
		int r = int(bulbArray_red[i]*921 + 2); //was 403 + 16: for 127 to -127 levels
		int g = int(bulbArray_green[i]*921 + 2); //921 + 2: for 255 to -255 levels
		int b = int(bulbArray_blue[i]*921 + 2);

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

// Chaser
//   based on G35 Xmas lights code by Paul Martis (http://www.digitalmisery.com)
//  (more interesting patterns by MEO)
void ProgramChaser(byte idx) {
	if(fxInitialised[idx] == false) {
		lcd.setCursor(0, 0);
		lcd.print("Chaser          ");

		fxIntVars[idx][0] = 0; //sequence step
		fxIntVars[idx][1] = random(3); //chaser pattern
		fxIntVars[idx][2] = 5; //number of pixels in a row with specific color
		fxIntVars[idx][3] = random(1536); //color starting point
		fxIntVars[idx][4] = 1; //count step

		fxFrameDelay[idx] = 0; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; // Effect initialized
	}

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) //only do once every delay frames
	{
		switch (fxIntVars[idx][1])
		{
		case 0:
			FillChaserSeq(fxIntVars[idx][4], fxIntVars[idx][0], fxIntVars[idx][2], fxIntVars[idx][3], ChaseRotateAnalogic45, idx);
			break;
		case 1:
			FillChaserSeq(fxIntVars[idx][4], fxIntVars[idx][0], fxIntVars[idx][2], fxIntVars[idx][3], ChaseRotateAccentedAnalogic30, idx);
			break;
		case 2:
			FillChaserSeq(fxIntVars[idx][4], fxIntVars[idx][0], fxIntVars[idx][2], fxIntVars[idx][3], ChaseRotateCompliment, idx);
			break;
		}
		if (fxIntVars[idx][4] < NUM_PIXELS)
		{
			++fxIntVars[idx][4];
		}
		else
		{
			++fxIntVars[idx][4];
		}	
		fxFrameDelayCount[idx] = 0;
	} else {
		fxFrameDelayCount[idx]++;
	}
}


//Larson Scanner
// Programmed by MEO from scratch
// ToDo: When hits either end, the fade stops dead. 
//       Can't really tell at 60Hz, but still it's bugging me, and I'd like to fix it
//ToDo: as with strobe fade - fade also moves through rainbow - not too noticable, as only 28 steps - but would be nice to offset
void ProgramLarsonScanner(byte idx){
	if(fxInitialised[idx] == false) { // Initialize effect?
		lcd.setCursor(0, 0);
		lcd.print("Larson Scanner  ");
		fxIntVars[idx][0] = NUM_PIXELS; //position - start one loop in, so can count backwards
		fxIntVars[idx][1] = random(6) * 256; //Colour on color wheel

		// Frame-to-frame hue increment (speed) -- may be positive or negative,
		// but magnitude shouldn't be so small as to be boring.  It's generally
		// still less than a full pixel per frame, making motion very smooth.
		fxIntVars[idx][2] = 5;//4 + random(fxIntVars[idx][1]) / NUM_PIXELS;  //1 was 4
		// Reverse speed and hue shift direction half the time.
		if(random(2) == 0) fxIntVars[idx][1] = -fxIntVars[idx][1];
		if(random(2) == 0) fxIntVars[idx][2] = -fxIntVars[idx][2];
		fxIntVars[idx][3] = 0; // Current position
		fxIntVars[idx][4] = random(4); // full rainbow or one of the lines
		fxIntVars[idx][5] = random(2); //whether to rainbow, or fixed colour
		fxIntVars[idx][6]= 1; //repeats per string

		fxFrameDelay[idx] = 0; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; //end initialise
	}

	byte *ptr = &imgData[idx][0];

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) {//only do once every delay frames
		int color, offset;
		for(int i = 0; i < NUM_PIXELS; i++) {
			//do backwards trail offset, so brighter overrides dimmer when overlap
			color = HSVtoRGB(0,0,0,0); //background
			for (offset = 27; offset >= 0; offset--) { // works with GetSmoothFade9, but overkill
				
				if (fxIntVars[idx][6] == 1) { //one per string
					if (i == GetSimpleOscillatePos(fxIntVars[idx][0] - offset, 99, 99)) {
						if (fxIntVars[idx][5] == 1) { //rainbow
							color = HSVtoRGB((fxIntVars[idx][3] + fxIntVars[idx][1] 
								* i / NUM_PIXELS) - offset, 255, GetSmoothFade27(offset), fxIntVars[idx][4]);
						} else { //fixed color
							color = HSVtoRGB(fxIntVars[idx][1], 255, GetSmoothFade27(offset), 0);
						}
					} 
				} else { //5 per string - ToDo: would be good to generalise this 1/2/4/5/10 per string
					if (i%20 == GetSimpleOscillatePos(fxIntVars[idx][0] - offset, 19, 19)) {
						if (fxIntVars[idx][5] == 1) { //rainbow
							color = HSVtoRGB((fxIntVars[idx][3] + fxIntVars[idx][1] 
								* i / NUM_PIXELS) - offset, 255, GetSmoothFade9(offset), fxIntVars[idx][4]);
						} else { //fixed color
							color = HSVtoRGB(fxIntVars[idx][1], 255, GetSmoothFade9(offset), 0);
						}
					} 
				}
			}
			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}

		//for rainbow version - move through rainbow
		fxIntVars[idx][3] += fxIntVars[idx][2];

		//increase oscillate step
		fxIntVars[idx][0]++;

		fxFrameDelayCount[idx] = 0;
	} else {
		fxFrameDelayCount[idx]++;
	}
}


//Stobe with fade
//Programmed by MEO from scratch - based on my Random Strobe, but with the fade from my Larson Scanner
//ToDo: merge with Random Strobe, with Fade as a flag
//ToDo: as with Larson - fade also moves through rainbow - not too noticable, as only 28 steps - but would be nice to offset
void ProgramStrobeFade(byte idx){
	if(fxInitialised[idx] == false) { // Initialize effect?
		lcd.setCursor(0, 0);
		lcd.print("Strobe Fade     ");
		fxIntVars[idx][0] = 0; // eye position
		fxIntVars[idx][1] = random(3) * 512; //Colour on color wheel
		// Frame-to-frame hue increment (speed) -- may be positive or negative,
		// but magnitude shouldn't be so small as to be boring.  It's generally
		// still less than a full pixel per frame, making motion very smooth.
		fxIntVars[idx][2] = 5;//4 + random(fxIntVars[idx][1]) / NUM_PIXELS;  //1 was 4
		// Reverse speed and hue shift direction half the time.
		if(random(2) == 0) fxIntVars[idx][1] = -fxIntVars[idx][1];
		if(random(2) == 0) fxIntVars[idx][2] = -fxIntVars[idx][2];
		fxIntVars[idx][3] = 0; // Current position
		fxIntVars[idx][4] = random(4); //full rainbow or one of the lines
		fxIntVars[idx][5] = random(3); //whether fixed colour, rainbow, or rainbow change color fade

		fxFrameDelay[idx] = 0; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; //end initialise
	}

	byte *ptr = &imgData[idx][0];

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) {//only do once every delay frames
		int color, offset;

		for(int i = 0; i < NUM_PIXELS; i++) {
			offset = (NUM_PIXELS + fxIntVars[idx][0] - GetRandom(i, NUM_PIXELS)) % NUM_PIXELS;
			if (fxIntVars[idx][5] == 0) {
				color = HSVtoRGB(fxIntVars[idx][1], 255, GetSmoothFade27(offset), 0);
			} else if (fxIntVars[idx][5] == 1) {//rainbow - the complex color term is due to needing to fade in the same colour - otherwise the fade carry  on rotating through colours
				color = HSVtoRGB(((fxIntVars[idx][3] + fxIntVars[idx][1] 
					* i / NUM_PIXELS) - (offset * fxIntVars[idx][2])) % 1536, 255, GetSmoothFade27(offset), fxIntVars[idx][4]);
			} else { //fade changes colour
				color = HSVtoRGB(((fxIntVars[idx][3] + fxIntVars[idx][1] 
					* i / NUM_PIXELS) + (offset * fxIntVars[idx][2]) * 10) % 1536, 255, GetSmoothFade27(offset), fxIntVars[idx][4]);
			}
			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}

		//increase/decrease eye position
		fxIntVars[idx][0]++;

		//for rainbow version - move through rainbow
		fxIntVars[idx][3] += fxIntVars[idx][2];
		fxFrameDelayCount[idx] = 0;
	} else {
		fxFrameDelayCount[idx]++;
	}
}


// Fade in/out a random 20% of bulbs
void ProgramOldFashioned(byte idx) {
	if(fxInitialised[idx] == false) {
		lcd.setCursor(0, 0);
		lcd.print("Old Fashioned   ");
		fxIntVars[idx][0] = 20; // Number of bulbs at a time
		fxIntVars[idx][1] = 600; // Frames to stay at full level
		fxIntVars[idx][2] = 0; //hue - old colour
		fxIntVars[idx][3] = random(1536); // Random hue (new colour)
		fxIntVars[idx][4] = 0; // fade position 
		fxIntVars[idx][5] = 0; //frame count
		fxIntVars[idx][6] = 0; //which bulbs at a time count

		//ToDo: add color level, so can start off from black

		fxFrameDelay[idx] = 0; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; // Effect initialized
	}

	byte *ptr = &imgData[idx][0];
	int color, i, j, outLo, outHi, inLo, inHi;

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) { //only do once every delay frames


		for(i=0; i<NUM_PIXELS; i++) {
			int rBulb;
			rBulb = GetRandom(i, NUM_PIXELS); //for non-repeating random
			//rBulb = i; // for sequential

			outLo = (NUM_PIXELS + (fxIntVars[idx][6] * fxIntVars[idx][0]) - fxIntVars[idx][0]) % NUM_PIXELS;
			outHi = (NUM_PIXELS + (fxIntVars[idx][6] * fxIntVars[idx][0]) - 1) % NUM_PIXELS;
			inLo = (NUM_PIXELS + (fxIntVars[idx][6] * fxIntVars[idx][0])) % NUM_PIXELS;
			inHi = (NUM_PIXELS + (fxIntVars[idx][6] * fxIntVars[idx][0]) + fxIntVars[idx][0] - 1) % NUM_PIXELS;

			color = HSVtoRGB(fxIntVars[idx][3], 255, 0, 0); //default off
			if ((rBulb >= inLo) && (rBulb <= inHi)) {
				color = HSVtoRGB(fxIntVars[idx][3], 255, getGamma(fxIntVars[idx][4]), 0); //fade in new set
			} else if ((rBulb >= outLo) && (rBulb <= outHi)) {
				color = HSVtoRGB(fxIntVars[idx][2], 255, 255 - getGamma(fxIntVars[idx][4]), 0);//fade out last set
			}

			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}

		//fade counter - if brighness level < 255 AND frame count == 0
		if ((fxIntVars[idx][4] < 255) && (fxIntVars[idx][5] == 0)) {
			fxIntVars[idx][4]++; //increase brightness (decrease brightness old)
		}

		//increase frame count, only when at max brightess
		// frame counter - if brightness == 255 
		if (fxIntVars[idx][4] == 255) {
			fxIntVars[idx][5]++; // increase frame count
		}

		//start over, with new bulbs - if frame count == frames to stay at full level
		if (fxIntVars[idx][5] == fxIntVars[idx][1]) {
			fxIntVars[idx][5] = 0; //reset frame count
			fxIntVars[idx][4] = 0; //reset brightness
			fxIntVars[idx][6] = fxIntVars[idx][6]++; // go to next set of bulbs

			fxIntVars[idx][2] = fxIntVars[idx][3]; //save last colour
			fxIntVars[idx][3] = random(1536); //new colour
		}

		//start completely over
		if (fxIntVars[idx][6] >= (NUM_PIXELS / fxIntVars[idx][0])) {
			fxIntVars[idx][6] = 0;
		}

		fxFrameDelayCount[idx] = 0;
	} else {
		fxFrameDelayCount[idx]++;
	}
}


//- All one colour, but level set by fadeTable 0 1 2 3 2 1 0 1 2 3 2 1 0 - around all bulbs
//	- variations: rotate bulbs / slowly invert fade / rotate & invert
//	              gap between each level for another colour 0 D 1 C 2 B 3 A 3 B 2 C 1 D 0
//				  rotate in opps directions
//				  no gap so colour add up at peak
void ProgramRotatingCircles(byte idx) {
	if(fxInitialised[idx] == false) {
		lcd.setCursor(0, 0);
		lcd.print("Rotating Circles");
		fxIntVars[idx][0] = random(1536); // Random hue
		fxIntVars[idx][1] = (fxIntVars[idx][1] + 768) % 1536; // complementary hue
		fxIntVars[idx][2] = 0; //frame count

		fxFrameDelay[idx] = 2; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; // Effect initialized
	}

	byte *ptr = &imgData[idx][0];
	int color;

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) { //only do once every delay frames
		for(int i=0; i<NUM_PIXELS; i++) {
			if (i % 2 == 1) {
				color = HSVtoRGB(fxIntVars[idx][0], 255, GetSmoothFade9((i+fxIntVars[idx][2]) % 9), 0);
			} else {
				color = HSVtoRGB(fxIntVars[idx][1], 255, GetSmoothFade9((18-i+fxIntVars[idx][2]) % 9), 0);
			}

			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}

		fxIntVars[idx][2]++;

		fxFrameDelayCount[idx] = 0;
	} else {
		fxFrameDelayCount[idx]++;
	}
}


// ToDo: Rainbow - with white shooting in opps direction
void ProgramRainbowWhite(byte idx) {
	if(fxInitialised[idx] == false) { // Initialize effect?
		lcd.setCursor(0, 0);
		lcd.print("Rainbow White   ");
		fxIntVars[idx][0] = 0; //white position
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

		fxInitialised[idx] = true; // Effect initialized
	}

	byte *ptr = &imgData[idx][0];
	int color, i, wht;

	//wht = GetSimpleOscillatePos(fxIntVars[idx][6], 10, 5) ;

	for(i=0; i<NUM_PIXELS; i++) {
		color = HSVtoRGB(fxIntVars[idx][3] + fxIntVars[idx][1] * i / NUM_PIXELS,
			255, 31, fxIntVars[idx][5]);


	//note: in reverse fade order, so that brightest 'wins' when can be either
		if (i == GetSimpleOscillatePos(fxIntVars[idx][0] - 3, 25, 20)) {
			color = HSVtoRGB(fxIntVars[idx][3] + fxIntVars[idx][1] * i / NUM_PIXELS,
			127, 31, fxIntVars[idx][5]);
		}

		if (i == GetSimpleOscillatePos(fxIntVars[idx][0] - 2, 25, 20)) {
			color = HSVtoRGB(fxIntVars[idx][3] + fxIntVars[idx][1] * i / NUM_PIXELS,
			63, 63, fxIntVars[idx][5]);
		}

		if (i == GetSimpleOscillatePos(fxIntVars[idx][0] - 1, 25, 20)) {
			color = HSVtoRGB(fxIntVars[idx][3] + fxIntVars[idx][1] * i / NUM_PIXELS,
			31, 127, fxIntVars[idx][5]);
		}

		if (i == GetSimpleOscillatePos(fxIntVars[idx][0], 25, 20)) {
			color = HSVtoRGB(fxIntVars[idx][3] + fxIntVars[idx][1] * i / NUM_PIXELS,
			15, 255, fxIntVars[idx][5]);
		}

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
	
	fxIntVars[idx][0]++; //white position
}

//Random splash - ToDo: add ripple effect
//Programmed by MEO from scratch
void ProgramRandomSplash(byte idx){
	short bulbArray;
	if(fxInitialised[idx] == false) { // Initialize effect?
		lcd.setCursor(0, 0);
		lcd.print("Splash          ");
		fxIntVars[idx][0] = random(3) * 512; //Colour on color wheel
		fxIntVars[idx][1] = 0; //add bulb to splash (not yet randomised)
		fxIntVars[idx][2] = 0; //add frame for the new bulb to splash
		fxIntVars[idx][3] = 0; //add bulb to splash (random version)
		fxIntVars[idx][4] = 20; //a new splash every x frames

		for (bulbArray = 0;bulbArray < 10 ; bulbArray++ ){
			fxArrVars[idx][0][bulbArray] = -1; //reset cache bulbs
			fxArrVars[idx][1][bulbArray] = -1; //reset cache frames
		}
		fxFrameCount[idx] = 0; //overall frame/time

		fxFrameDelay[idx] = 0; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; //end initialise
	}

	byte *ptr = &imgData[idx][0];

	//make code easier to read
	int newBulbNonRand, newFrame, newBulbRand, splashDelay;
	newBulbNonRand = fxIntVars[idx][1];
	newFrame = fxIntVars[idx][2];
	newBulbRand = fxIntVars[idx][3];
	splashDelay = fxIntVars[idx][4];

	newBulbRand = GetRandom(newBulbNonRand, NUM_PIXELS);

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) {//only do once every delay frames
		int color, splash;

		if ((fxFrameCount[idx] % splashDelay) == 0){ //new splash every fxI32Vars[idx][4] frames
			newFrame = fxFrameCount[idx];
			newBulbNonRand++;

			//insert newest flash at start, and move rest along
			for (bulbArray = 8; bulbArray >= 0 ; bulbArray--) {
				fxArrVars[idx][0][bulbArray + 1] = fxArrVars[idx][0][bulbArray]; //shift bulbs in cache
				fxArrVars[idx][1][bulbArray + 1] = fxArrVars[idx][1][bulbArray]; //shift frames in cache
			}
			fxArrVars[idx][0][0] = newBulbRand; // insert new bulb into cache
			fxArrVars[idx][1][0] = newFrame; // insert new frame into cache
		}

		for(int i = 0; i < NUM_PIXELS; i++) {
			splash = 0;

			for (bulbArray = 0; bulbArray < 10 ; bulbArray++ ){ // 0; <10; ++
				if (fxArrVars[idx][0][bulbArray] >= 0){ //ignore cache items not yet set					
					splash = splash + GetSplash(i, fxFrameCount[idx], fxArrVars[idx][0][bulbArray], fxArrVars[idx][1][bulbArray], 0.20);
				}
			}
			if (splash > 255){
				splash = 255;
			}
			//to do: make only the level accumulate, so that whites stand out more. (If possible!)
			//can change color, if use hsv2rgb((fxIntVars[idx][0] + splash * 10) % 1536,...
			color = HSVtoRGB(fxIntVars[idx][0], 255 - splash, splash, 0);
			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;
		}

		//increase overall frame counter
		fxFrameCount[idx]++;

		//reset at end of bulbs;
		if (newBulbNonRand == NUM_PIXELS)
		{
			newBulbNonRand = 0;
		}
	} else {
		fxFrameDelayCount[idx]++;
	}

	//put friendly vars back
	fxIntVars[idx][1] = newBulbNonRand;
	fxIntVars[idx][2] = newFrame;
	fxIntVars[idx][3] = newBulbRand;
	fxIntVars[idx][4] = splashDelay;
}


//Comet
// Programmed by MEO from scratch
//- rainbow fade: (https://www.youtube.com/watch?v=xTkiNIJkWrY   end of http://www.youtube.com/watch?v=9wZhDc0PnWg)
//  primary/secondary colours from 255 to 0 brightness before next colour
//  - or, use Hue, and Trail - like commets, one after the other or on their own
//  - constant stream (like one way larson) - or fill (building up at end) - multicolour options
void ProgramComet(byte idx){
	if(fxInitialised[idx] == false) { // Initialize effect?
		lcd.setCursor(0, 0);
		lcd.print("Comet           ");
		fxIntVars[idx][0] = NUM_PIXELS; //position - start one loop in, so can count backwards
		fxIntVars[idx][1] = random(6) * 256; //Colour on color wheel

		// Frame-to-frame hue increment (speed) -- may be positive or negative,
		// but magnitude shouldn't be so small as to be boring.  It's generally
		// still less than a full pixel per frame, making motion very smooth.
		fxIntVars[idx][2] = 5;//4 + random(fxIntVars[idx][1]) / NUM_PIXELS;  //1 was 4
		// Reverse speed and hue shift direction half the time.
		if(random(2) == 0) fxIntVars[idx][1] = -fxIntVars[idx][1];
		if(random(2) == 0) fxIntVars[idx][2] = -fxIntVars[idx][2];
		fxIntVars[idx][3] = 0; // Current position
		fxIntVars[idx][4] = random(4); // full rainbow or one of the lines
		fxIntVars[idx][5] = random(2); //whether to rainbow, or fixed colour

		fxIntVars[idx][7] = NUM_PIXELS - 1; // this will get decreased by one each comet shoot, for fill version, so gradully fills up
		
		fxFrameDelay[idx] = 0; //delay frame count
		fxFrameDelayCount[idx] = 0; //delay frame

		fxInitialised[idx] = true; //end initialise
	}

	//ToDo: version where next trail starts straight after fade (i.e. 27 bulbs behind)
	//		- variation, with multi colours

	byte *ptr = &imgData[idx][0];

	if (fxFrameDelayCount[idx] == fxFrameDelay[idx]) {//only do once every delay frames
		int color, offset;

		for(int i = 0; i < NUM_PIXELS; i++) {
			//do backwards trail offset, so brighter overrides dimmer when overlap
			color = HSVtoRGB(0,0,0,0); //background

			for (offset = 27; offset >= 0; offset--) { // works with GetSmoothFade9, but overkill
				
				if (i == GetSimpleOscillatePos(fxIntVars[idx][0] - offset, fxIntVars[idx][7], 0)) {
					color = HSVtoRGB(fxIntVars[idx][1], 255, GetSmoothFade27(offset), 0);
				} 
			}

			//the already previously filled bulbs - these build up (after end point)
			if (i > fxIntVars[idx][7]) {
				color = HSVtoRGB(fxIntVars[idx][1], 255, 255, 0);
			}

/* Larson - 5 x version
			if (i%50 == GetSimpleOscillatePos(fxIntVars[idx][0] - offset, 19, 19)) {
				color = HSVtoRGB(fxIntVars[idx][1], 255, GetSmoothFade9(offset), 0);
			} 
*/

			*ptr++ = color >> 16; *ptr++ = color >> 8; *ptr++ = color;







		}

		//for rainbow version - move through rainbow
		fxIntVars[idx][3] += fxIntVars[idx][2];

		//increase oscillate step
		fxIntVars[idx][0]++;


		//for 'fill' version
		if (fxIntVars[idx][0] % fxIntVars[idx][7] == 0) {
			fxIntVars[idx][0] = 0;
			Serial.print(fxIntVars[idx][0]); Serial.print(" : "); Serial.println(fxIntVars[idx][7]);
			
			//reduce end point each time
			fxIntVars[idx][7]--;

			if (fxIntVars[idx][7] == 0) { //reset
				fxIntVars[idx][7] = NUM_PIXELS - 1;
				fxIntVars[idx][1] = (fxIntVars[idx][1] + 256 ) % 1536;
			}
		}




		fxFrameDelayCount[idx] = 0;
	} else {
		fxFrameDelayCount[idx]++;
	}



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

// Straight left-to-right or right-to-left wipe
void crossfadeWipe(void) {
	int x, y, b;
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
	int fade;
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
byte gammaTable[]  = 
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
241, 243, 245, 247, 249, 251, 253, 255 };

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
int HSVtoRGB(int h, byte s, byte v, int wheelLine) {
	byte r, g, b, lo;
	int  s1;
	int v1;

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
	// 1 to allow shifts, and upgrade to int makes other conversions implicit.
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

char FixedSine(int angle) {
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

char FixedCosine(int angle) {
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

byte randomTable050[]= 
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

// This function gets the fixed non-repeating random number
inline byte GetRandom(byte x, byte size) {
	switch (size)
	{
	case 50:
		return pgm_read_byte(&randomTable050[x]);
		break;
	case 100:
		return pgm_read_byte(&randomTable100[x]);
		break;
	case 160:
		return pgm_read_byte(&randomTable160[x]);
		break;
	}
}

//Pleasing fade of bulbs - like tungsten filament light bulbs
//fade levels - adjust until looks pleasing
//ToDo: extra parameter of fade levels: e.g. GetSmoothFade27(blah, 27)
//      with different fadeTables
byte fadeTable27[27]  = {255, 223, 191, 159, 127, 111, 95, 79, 63, 55, 47, 
39, 31, 27, 23, 19, 15, 13, 11, 9, 7, 6, 5, 4, 3, 2, 1};
// This function gets the fade level
inline byte GetSmoothFade27(byte x) {
	if (x < 28) {
		return pgm_read_byte(&fadeTable27[x]);
	} else {
		return 0;
	}
}
byte fadeTable9[9]  = {255, 127, 63, 31, 15, 7, 4, 2, 1};
// This function gets the fade level
inline byte GetSmoothFade9(byte x) {
	if (x < 10) {
		return pgm_read_byte(&fadeTable9[x]);
	} else {
		return 0;
	}
}

// Simplex noise support functions:
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

/*//Add one, because programs using this will be 0 based
//ToDo: fix so ...
int GetQuadraticLevel(int pos, int length, bool half) {
	float topIndex;
	float iQuad;
	float fPos = float(pos);
	float fLen = float(length);
	if (half) {
		topIndex = (float)length;
		iQuad = ((fPos + 1.0)* (fPos + 1.0)) + fPos + 1.0;
	} else { //... this part works evenly
		topIndex = fLen / 2.0;
		if (fPos > topIndex) {
			fPos = fLen - fPos;
			iQuad = ((fPos - 1.0)* (fPos - 1.0)) + fPos - 1.0;
		} else {
			iQuad = ((fPos + 1.0)* (fPos + 1.0)) + fPos + 1.0;
		}
	}

	//Serial.print(fPos);  Serial.print(" ");


	float hQuad = (topIndex * topIndex) + topIndex;

	return int((iQuad/hQuad)*255.0);
}*/



//at it's simplest, provides all Larson Scanner position data (timestep, 99, 99)
//but with different vals for forward, back, will do a zig zag effect
// t=time, a = forward steps, b = backward steps
// Thanks to Mohit Bakshi from Quora for providing equation:
// https://www.quora.com/Mathematics/What-is-the-equation-for-a-moving-zig-zag-type-oscillation
// using this allows me to work out previous positions so that I can do smooth fades
int GetSimpleOscillatePos(int t, int a, int b) {
	int s, n;
	n = t / (a + b);

	if ((n * (a + b) <= t) && (t <= ((n + 1) * a) + (n * b))) {
		s = t - (2 * n * b);
	} else if ((((n + 1) * a) + (n * b) <= t) && (t <= (n + 1) * (a + b))) {
		s = (2 * (n + 1) * a) - t;
	}
	return s % NUM_PIXELS;
}


//tstBlb[0] = 25; timBlb[0] = 0; // turn into tables of random bulbs, with time gap between: 5, 30; 18,60; 45,90 (every 30 frames)
 
/*for (i=0;i<NUM_PIX;i++) {
	for (offset=8;offset>0;offset--) {
		if (i == GetSplsh(timeStep, tstBulb[0], timBulb[0])){ 
				c = h2r(1024, 255 - level(offset), level(offset);
		}
	}
}
timStep++;*/

//info for a splash effect - to do: ripple?
int GetSplash(int bulbOut, int frameOut, int bulbStart, int frameStart, float velocity) {
	float amplitudeOut; //the return value before adjustment
	int frameRelative; //relative time, i.e. time into the effect
	float distance; // distance effect has travelled on one side

	short frame = frameOut - frameStart;

	distance = velocity * (float)frame;

	float level = 0.0;
	if (frame < 100) { //100 is size of damping table
		//amplitudeOut = pow(damping, (float)frame); //pow(x,y) is really really slow!
		//level = ((float)MAX_LEVEL * amplitudeOut);
		level = ((float)MAX_LEVEL * dampingTable[frame]);
	}
	

	int finalOutput = 0;
	if (((float)bulbOut >= ((float)bulbStart - distance)) && ((float)bulbOut <= ((float)bulbStart + distance))) {
		if (level > 1.0) {
			finalOutput = (long)(level - 1); //adjust to zero-based
		}
	}
	return finalOutput;
}

//Chaser support functions

void FillChaserSeq(int count, int sequence, int span_size, int startColor, 
						   int (*sequence_func)(int sequence, int startColor), byte idx)
{
	//begin, count, sequence, span, func, idx)
	while (count--)
	{
		SetChaserColor(count, sequence_func(sequence++ / span_size, startColor), idx);
	}
}

void SetChaserColor(int bulb, int color, byte idx)
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
int ChaseRGB(int sequence, int startColor)
{
    sequence = sequence % 3;
    if (sequence == 0)
    {
        return (HSVtoRGB(0, 255, 255, 0));
    }
    if (sequence == 1)
    {
        return (HSVtoRGB(512, 255, 255, 0));
    }
    return (HSVtoRGB(1024, 255, 255, 0));
} 

int ChaseRotateCompliment(int sequence, int startColor)
{
	int positionP, positionC;
	positionP = (startColor + sequence) % 1536;
	positionC = (startColor + sequence + 768) % 1536; // + 768 = 180 degrees
    sequence = sequence % 5;
    if (sequence == 0)
    {
        return (HSVtoRGB(positionC, 255, 255, 0)); // Complimetary color
    } else {
        return (HSVtoRGB(positionP, 255, 255, 0)); // Primary colour
    }
}

int ChaseRotateAnalogic45(int sequence, int startColor)
{
	int positionP1, positionP2, positionP3;
	positionP1 = (startColor + sequence) % 1536;
	positionP2 = (startColor + sequence + 192) % 1536; // + 192 = 45 degrees
	positionP3 = (startColor + sequence +1344) % 1536; // -192 = -45 degrees (added 1344 is equiv)
    sequence = sequence % 4;
    if (sequence == 0)
    {
        return (HSVtoRGB(positionP2, 255, 255, 0)); // 45 degrees anti-clockwise
    }
	if ((sequence == 1) || (sequence == 3))
	{
        return (HSVtoRGB(positionP3, 255, 255, 0)); // Primary colour
    }
	return (HSVtoRGB(positionP1, 255, 255, 0)); //45 degrees clockwise
}

int ChaseRotateAccentedAnalogic30(int sequence, int startColor)
{
	int positionP1, positionP2, positionP3, positionC;
	positionP1 = (startColor + sequence) % 1536;
	positionP2 = (startColor + sequence + 128) % 1536; // + 128 = 30 degrees
	positionP3 = (startColor + sequence + 1280) % 1536; // -128 = -30 degrees (added 1280 is equiv)
	positionC = (startColor + sequence + 768) % 1536; // + 768 = 180 degrees
    sequence = sequence % 6;
    if (sequence == 0)
    {
        return (HSVtoRGB(positionP2, 255, 255, 0)); // 30 degrees anti-clockwise
    }
	if ((sequence == 1) || (sequence == 5))
	{
        return (HSVtoRGB(positionP1, 255, 255, 0)); // Primary colour
    }
	if ((sequence == 2) || (sequence == 4))
	{
        return (HSVtoRGB(positionP3, 255, 255, 0)); // Primary colour
    }
	return (HSVtoRGB(positionC, 255, 255, 0)); //30 degrees clockwise
}