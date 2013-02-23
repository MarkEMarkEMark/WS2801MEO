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

void setup(){
  // Start timer. Parameters are:

  // TC1 : timer counter. Can be TC0, TC1 or TC2
  // 0   : channel. Can be 0, 1 or 2
  // TC3_IRQn: irq number. See table.
  // 40  : frequency (in Hz)
  // The interrupt service routine is TC3_Handler. See table.

  startTimer(TC1, 0, TC3_IRQn, 1);

  // Paramters table:
  // TC0, 0, TC0_IRQn  =>  TC0_Handler()
  // TC0, 1, TC1_IRQn  =>  TC1_Handler()
  // TC0, 2, TC2_IRQn  =>  TC2_Handler()
  // TC1, 0, TC3_IRQn  =>  TC3_Handler()
  // TC1, 1, TC4_IRQn  =>  TC4_Handler()
  // TC1, 2, TC5_IRQn  =>  TC5_Handler()
  // TC2, 0, TC6_IRQn  =>  TC6_Handler()
  // TC2, 1, TC7_IRQn  =>  TC7_Handler()
  // TC2, 2, TC8_IRQn  =>  TC8_Handler()
  Serial.begin(115200);
}

void loop(){
}

//volatile boolean l;

// This function is called every 1/40 sec.
void TC3_Handler()
{
  // You must do TC_GetStatus to "accept" interrupt
  // As parameters use the first two parameters used in startTimer (TC1, 0 in this case)
  TC_GetStatus(TC1, 0);

  //digitalWrite(13, l = !l);
	Serial.println("Tick");
}