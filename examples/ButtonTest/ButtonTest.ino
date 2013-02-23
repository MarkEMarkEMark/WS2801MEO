//Includes multiple button handling by ladyada: http://www.adafruit.com/blog/2009/10/20/example-code-for-multi-button-checker-with-debouncing/

//Buttons initialisation
//if you want, you can even run the button checker in the background, which can make for a very easy interface. Remember that you’ll need to clear “just pressed”, etc. after checking or it will be “stuck” on
#define DEBOUNCE 10  // button debouncer, how many ms to debounce, 5+ ms is usually plenty
// here is where we define the buttons that we'll use. button "1" is the first, button "6" is the 6th, etc
byte buttons[] = {22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32}; // the analog A0-15 pins are also known as 54+ on Mega
// This handy macro lets us determine how big the array up above is, by checking the size
#define NUMBUTTONS sizeof(buttons)
// we will track if a button is just pressed, just released, or 'currently pressed'
volatile byte pressed[NUMBUTTONS], justpressed[NUMBUTTONS], justreleased[NUMBUTTONS];

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

void setup() {
	//Buttons
	byte i;
	 
	// Make input & enable pull-up resistors on switch pins
	for (i=0; i< NUMBUTTONS; i++)
	{
		pinMode(buttons[i], INPUT);
		digitalWrite(buttons[i], HIGH);
	}

	startTimer(TC0, 0, TC0_IRQn, 67); //(67Hz = approx 15ms)

	Serial.begin(115200);
}
 
void loop() {
	//Buttons
	for (byte myButton = 0; myButton < NUMBUTTONS; myButton++) {
		if (justpressed[myButton]) {
			justpressed[myButton] = 0;
			switch (myButton){
				case 0: //program Up
					Serial.println("Program Up");
					break;
				case 1: //program Down
					Serial.println("Program Down");
					break;
				case 2: //variation up
					Serial.println("Variation Up");
					break;
				case 3: //variation down
					Serial.println("Variation Down");
					break;
				case 4: //brightness up
					Serial.println("Brightness Up");
					break;
				case 5: //brighness down
					Serial.println("Brightness Down");
					break;
				case 6: //toggle random program
					Serial.println("Randomise");
					break;
				case 7: //toggle off / on
					Serial.println("On / Off");
					break;
			}
		}
	}
}
 
//Debounce buttons - nothing to do with lights...
void TC0_Handler() {
	// You must do TC_GetStatus to "accept" interrupt
	// As parameters use the first two parameters used in startTimer (TC1, 0 in this case)
	TC_GetStatus(TC0, 0);

	check_switches();
}
 
void check_switches() {
	static byte previousstate[NUMBUTTONS];
	static byte currentstate[NUMBUTTONS];
	static long lasttime;
	byte index;
	 
	if (millis() < lasttime) {
		// we wrapped around, lets just try again
		lasttime = millis();
	}
	 
	if ((lasttime + DEBOUNCE) > millis()) {
		// not enough time has passed to debounce
		return;
	}
	 
	// ok we have waited DEBOUNCE milliseconds, lets reset the timer
	lasttime = millis();
	 
	for (index = 0; index < NUMBUTTONS; index++) {
		currentstate[index] = digitalRead(buttons[index]);   // read the button
		if (currentstate[index] == previousstate[index]) {
			if ((pressed[index] == LOW) && (currentstate[index] == LOW)) {
				// just pressed
				justpressed[index] = 1;
			}
			else if ((pressed[index] == HIGH) && (currentstate[index] == HIGH)){
				// just released
				justreleased[index] = 1;
			}
			pressed[index] = !currentstate[index];  // remember, digital HIGH means NOT pressed
		}
		previousstate[index] = currentstate[index];   // keep a running tally of the buttons
	}
}