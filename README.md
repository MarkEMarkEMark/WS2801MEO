WS2801MEO
=========

LPD8806 code running on WS2801 and Arduino Due

This code is Adafruit's LPD8806 Examples (https://github.com/adafruit/LPD8806)

but with Adafruit's WS2801 Driver (https://github.com/adafruit/Adafruit-WS2801-Library)

Setup for an Ardunino Due

This has been tested SPI only, so note that the SPI pins are the block of 6 marked SPI. If you letter them from the top left A to F, then C is the clock and D is the Data.

SPI
[A][B]
[C][D]
[E][F]

In order to get this running, I had to remove the Timer1 interrupt call (Ownedelongs' idea elsewhere on this forum)

I also had to alter a few SPI code lines, and also change all the flash memory stuff to Byte. There are not that many changes, but it took a lot of trial and error to get to this point.

I've tried it up to 240 frames per second without breaking a sweat (but it's too fast, so put it back to 60)

Now includes 3 new complex programs: Random Strobe / Simplex Noise (based on happyinmontion's) / Color Phasing
Also includes elmerfud's Larson scanner and pulse
