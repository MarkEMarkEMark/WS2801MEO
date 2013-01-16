#include "DriverWS2801.h"
#include "SPI.h"

// Example to control LPD8806-based RGB LED Modules in a myBulbString!
/*****************************************************************************/

#if defined(USB_SERIAL) || defined(USB_SERIAL_ADAFRUIT)
// this is for teensyduino support
int dataPin = 2;
int clockPin = 1;
#else 
// these are the pins we use for the LED belt kit using
// the Leonardo pinouts
int dataPin = 16;
int clockPin = 15;
#endif

#define NUM_PIXELS 100

// Set the first variable to the NUMBER of pixels. 32 = 32 pixels in a row
// The LED myBulbStrings are 32 LEDs per meter but you can extend/cut the myBulbString
//LPD8806 myBulbString = LPD8806(100);
DriverWS2801 myBulbString = DriverWS2801(NUM_PIXELS);



void setup() {
  // Start up the LED myBulbString
  myBulbString.begin();

  // Update the myBulbString, to start they are all 'off'
  myBulbString.show();
}

// function prototypes, do not remove these!
void colorChase(uint32_t c, uint8_t wait);
void colorWipe(uint32_t c, uint8_t wait);
void dither(uint32_t c, uint8_t wait);
void scanner(uint8_t r, uint8_t g, uint8_t b, uint8_t wait);
void wave(uint32_t c, int cycles, uint8_t wait);
void rainbowCycle(uint8_t wait);
uint32_t Wheel(uint16_t WheelPos);

void loop() {

  // Send a simple pixel chase in...
  colorChase(myBulbString.Color(127,127,127), 20); // white
  colorChase(myBulbString.Color(127,0,0), 20);     // red
  colorChase(myBulbString.Color(127,127,0), 20);   // yellow
  colorChase(myBulbString.Color(0,127,0), 20);     // green
  colorChase(myBulbString.Color(0,127,127), 20);   // cyan
  colorChase(myBulbString.Color(0,0,127), 20);     // blue
  colorChase(myBulbString.Color(127,0,127), 20);   // magenta

  // Fill the entire myBulbString with...
  colorWipe(myBulbString.Color(127,0,0), 20);      // red
  colorWipe(myBulbString.Color(0, 127,0), 20);     // green
  colorWipe(myBulbString.Color(0,0,127), 20);      // blue
  colorWipe(myBulbString.Color(0,0,0), 20);        // black

  // Color sparkles
  dither(myBulbString.Color(0,127,127), 50);       // cyan, slow
  dither(myBulbString.Color(0,0,0), 15);           // black, fast
  dither(myBulbString.Color(127,0,127), 50);       // magenta, slow
  dither(myBulbString.Color(0,0,0), 15);           // black, fast
  dither(myBulbString.Color(127,127,0), 50);       // yellow, slow
  dither(myBulbString.Color(0,0,0), 15);           // black, fast

  // Back-and-forth lights
  scanner(127,0,0, 30);        // red, slow
  scanner(0,0,127, 15);        // blue, fast

  // Wavy ripple effects
  wave(myBulbString.Color(127,0,0), 4, 20);        // candy cane
  wave(myBulbString.Color(0,0,100), 2, 40);        // icy

  // make a pretty rainbow cycle!
  rainbowCycle(0);  // make it go through the cycle fairly fast

  // Clear myBulbString data before start of next effect
  for (int i=0; i < myBulbString.numPixels(); i++) {
    myBulbString.setPixelColor(i, 0);
  }
}

// Cycle through the color wheel, equally spaced around the belt
void rainbowCycle(uint8_t wait) {
  uint16_t i, j;

  for (j=0; j < 384 * 5; j++) {     // 5 cycles of all 384 colors in the wheel
    for (i=0; i < myBulbString.numPixels(); i++) {
      // tricky math! we use each pixel as a fraction of the full 384-color
      // wheel (thats the i / myBulbString.numPixels() part)
      // Then add in j which makes the colors go around per pixel
      // the % 384 is to make the wheel cycle around
      myBulbString.setPixelColor(i, Wheel(((i * 384 / myBulbString.numPixels()) + j) % 384));
    }
    myBulbString.show();   // write all the pixels out
    delay(wait);
  }
}

// fill the dots one after the other with said color
// good for testing purposes
void colorWipe(uint32_t c, uint8_t wait) {
  int i;

  for (i=0; i < myBulbString.numPixels(); i++) {
      myBulbString.setPixelColor(i, c);
      myBulbString.show();
      delay(wait);
  }
}

// Chase a dot down the myBulbString
// good for testing purposes
void colorChase(uint32_t c, uint8_t wait) {
  int i;

  for (i=0; i < myBulbString.numPixels(); i++) {
    myBulbString.setPixelColor(i, 0);  // turn all pixels off
  }

  for (i=0; i < myBulbString.numPixels(); i++) {
      myBulbString.setPixelColor(i, c); // set one pixel
      myBulbString.show();              // refresh myBulbString display
      delay(wait);               // hold image for a moment
      myBulbString.setPixelColor(i, 0); // erase pixel (but don't refresh yet)
  }
  myBulbString.show(); // for last erased pixel
}

// An "ordered dither" fills every pixel in a sequence that looks
// sparkly and almost random, but actually follows a specific order.
void dither(uint32_t c, uint8_t wait) {

  // Determine highest bit needed to represent pixel index
  int hiBit = 0;
  int n = myBulbString.numPixels() - 1;
  for(int bit=1; bit < 0x8000; bit <<= 1) {
    if(n & bit) hiBit = bit;
  }

  int bit, reverse;
  for(int i=0; i<(hiBit << 1); i++) {
    // Reverse the bits in i to create ordered dither:
    reverse = 0;
    for(bit=1; bit <= hiBit; bit <<= 1) {
      reverse <<= 1;
      if(i & bit) reverse |= 1;
    }
    myBulbString.setPixelColor(reverse, c);
    myBulbString.show();
    delay(wait);
  }
  delay(250); // Hold image for 1/4 sec
}

// "Larson scanner" = Cylon/KITT bouncing light effect
void scanner(uint8_t r, uint8_t g, uint8_t b, uint8_t wait) {
  int i, j, pos, dir;

  pos = 0;
  dir = 1;

  for(i=0; i<((myBulbString.numPixels()-1) * 8); i++) {
    // Draw 5 pixels centered on pos.  setPixelColor() will clip
    // any pixels off the ends of the myBulbString, no worries there.
    // we'll make the colors dimmer at the edges for a nice pulse
    // look
    myBulbString.setPixelColor(pos - 2, myBulbString.Color(r/4, g/4, b/4));
    myBulbString.setPixelColor(pos - 1, myBulbString.Color(r/2, g/2, b/2));
    myBulbString.setPixelColor(pos, myBulbString.Color(r, g, b));
    myBulbString.setPixelColor(pos + 1, myBulbString.Color(r/2, g/2, b/2));
    myBulbString.setPixelColor(pos + 2, myBulbString.Color(r/4, g/4, b/4));

    myBulbString.show();
    delay(wait);
    // If we wanted to be sneaky we could erase just the tail end
    // pixel, but it's much easier just to erase the whole thing
    // and draw a new one next time.
    for(j=-2; j<= 2; j++) 
        myBulbString.setPixelColor(pos+j, myBulbString.Color(0,0,0));
    // Bounce off ends of myBulbString
    pos += dir;
    if(pos < 0) {
      pos = 1;
      dir = -dir;
    } else if(pos >= myBulbString.numPixels()) {
      pos = myBulbString.numPixels() - 2;
      dir = -dir;
    }
  }
}

// Sine wave effect
#define PI 3.14159265
void wave(uint32_t c, int cycles, uint8_t wait) {
  float y;
  byte  r, g, b, r2, g2, b2;

  // Need to decompose color into its r, g, b elements
  g = (c >> 16) & 0x7f;
  r = (c >>  8) & 0x7f;
  b =  c        & 0x7f; 

  for(int x=0; x<(myBulbString.numPixels()*5); x++)
  {
    for(int i=0; i<myBulbString.numPixels(); i++) {
      y = sin(PI * (float)cycles * (float)(x + i) / (float)myBulbString.numPixels());
      if(y >= 0.0) {
        // Peaks of sine wave are white
        y  = 1.0 - y; // Translate Y to 0.0 (top) to 1.0 (center)
        r2 = 127 - (byte)((float)(127 - r) * y);
        g2 = 127 - (byte)((float)(127 - g) * y);
        b2 = 127 - (byte)((float)(127 - b) * y);
      } else {
        // Troughs of sine wave are black
        y += 1.0; // Translate Y to 0.0 (bottom) to 1.0 (center)
        r2 = (byte)((float)r * y);
        g2 = (byte)((float)g * y);
        b2 = (byte)((float)b * y);
      }
      myBulbString.setPixelColor(i, r2, g2, b2);
    }
    myBulbString.show();
    delay(wait);
  }
}

/* Helper functions */

//Input a value 0 to 384 to get a color value.
//The colours are a transition r - g - b - back to r

uint32_t Wheel(uint16_t WheelPos)
{
  byte r, g, b;
  switch(WheelPos / 128)
  {
    case 0:
      r = 127 - WheelPos % 128; // red down
      g = WheelPos % 128;       // green up
      b = 0;                    // blue off
      break;
    case 1:
      g = 127 - WheelPos % 128; // green down
      b = WheelPos % 128;       // blue up
      r = 0;                    // red off
      break;
    case 2:
      b = 127 - WheelPos % 128; // blue down
      r = WheelPos % 128;       // red up
      g = 0;                    // green off
      break;
  }
  return(myBulbString.Color(r,g,b));
}