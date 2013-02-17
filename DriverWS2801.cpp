#include "SPI.h"
#include "DriverWS2801.h"

// Example to control WS2801-based RGB LED Modules in a strand or strip
// Written by Adafruit - MIT license
/*****************************************************************************/

// Constructor for use with hardware SPI (specific clock/data pins):
DriverWS2801::DriverWS2801(uint16_t n) {
	alloc(n);
}

// Allocate 3 bytes per pixel, init to RGB 'off' state:
void DriverWS2801::alloc(uint16_t n) {
	numLEDs = ((pixels = (uint8_t *)calloc(n, 3)) != NULL) ? n : 0;
}

// Release memory (as needed):
DriverWS2801::~DriverWS2801(void) {
	if (pixels != NULL) {
		free(pixels);
	}
}

// Activate hard/soft SPI as appropriate:
void DriverWS2801::begin(void) {
	startSPI();
}

// Enable SPI hardware and set up protocol details:
void DriverWS2801::startSPI(void) {
	SPI.begin();
	SPI.setBitOrder(MSBFIRST);
	SPI.setDataMode(SPI_MODE0);
	SPI.setClockDivider(42); // SPI_CLOCK_DIV8  1 MHz max, else flicker
}

uint16_t DriverWS2801::numPixels(void) {
	return numLEDs;
}

void DriverWS2801::show(void) {
	uint16_t i, nl3 = numLEDs * 3; // 3 bytes per LED
	uint8_t  bit;

	// Write 24 bits per pixel:
		for(i=0; i<nl3; i++) {
			SPI.transfer(pixels[i]);
		}
	//delay(1); // Data is latched by holding clock pin low for 1 millisecond
}

// Set pixel color from separate 8-bit R, G, B components:
void DriverWS2801::setPixelColor(uint16_t n, uint8_t r, uint8_t g, uint8_t b) {
	if(n < numLEDs) { // Arrays are 0-indexed, thus NOT '<='
		uint8_t *p = &pixels[n * 3];
		*p++ = r;
		*p++ = g;
		*p++ = b;
	}
}

/*

///### Commented out, but kept in case required in the future ###

// Set pixel color from 'packed' 32-bit RGB value:
void DriverWS2801::setPixelColor(uint16_t n, uint32_t c) {
	if(n < numLEDs) { // Arrays are 0-indexed, thus NOT '<='
		uint8_t *p = &pixels[n * 3];
		*p++ = c >> 16; // Red
		*p++ = c >>  8; // Green
		*p++ = c;       // Blue
	}
}

// Query color from previously-set pixel (returns packed 32-bit RGB value)
uint32_t DriverWS2801::getPixelColor(uint16_t n) {
	if(n < numLEDs) {
		uint16_t ofs = n * 3;
		return (((uint32_t)pixels[ofs] << 16) | ((uint16_t) pixels[ofs + 1] <<  8) | pixels[ofs + 2]);
	}
	return 0; // Pixel # is out of bounds
}

// Convert separate R,G,B into combined 32-bit RGB color:
uint32_t DriverWS2801::Color(byte r, byte g, byte b) {
	return ((uint32_t)(r) << 16) |
		((uint32_t)(g) <<  8) |
		b;
}
*/