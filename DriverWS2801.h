class DriverWS2801 {

 public:

  // Use SPI hardware; specific pins only:
  DriverWS2801(uint16_t n);
  // Release memory (as needed):
  ~DriverWS2801();

  void
    begin(void),
    show(void),
    setPixelColor(uint16_t n, uint8_t r, uint8_t g, uint8_t b),
    setPixelColor(uint16_t n, uint32_t c);
  uint16_t
    numPixels(void);
//uint32_t
//	getPixelColor(uint16_t n),
//	Color(byte r, byte g, byte b);

 private:

  uint16_t
    numLEDs;
  uint8_t
    *pixels;   // Holds color values for each LED (3 bytes each)
  void
    alloc(uint16_t n),
    startSPI(void);
};