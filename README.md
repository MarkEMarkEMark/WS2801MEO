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

I also had to alter a few SPI code lines, and also change all the flash memory stuff to Byte. There are not that many changes, but it took a lot of trial and error to get to this point.

I've tried it up to 240 frames per second without breaking a sweat (but it's too fast, so put it back to 60)

Now includes a number of new complex programs including: Random Strobe / Simplex Noise (based on happyinmontion's) / Color Phasing
Also includes elmerfud's pulse

The 'hsv2rgb' function has been update to allow 'color lines' as well as the default color wheel. That is, Blue -> Magenta -> Red -> Magenta -> Blue, for example.

There is a bog standard 'chaser' function , but to keep it interesting, rather than doing the usual Red/Green/Blue type chases, I have opted for color schemes based on the color wheel (e.g. 30 degrees either side of main color). Whilst the color wheel isn't a true color wheel, the color schemes are still pleasing. (Chase function based on DigitalMisery's work)

There is a fire pattern based on Christopher De Vries code. I hope to improve this with interpolation in the future.

------

Adafruit invests time and resources providing this open source code, 
  please support Adafruit and open-source hardware by purchasing 
  products from Adafruit!

  Written by Limor Fried/Ladyada for Adafruit Industries.  
  BSD license, all text above must be included in any redistribution
