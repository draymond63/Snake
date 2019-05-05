s// PROJECT: Snake Game
// PURPOSE: To program Snake in C before taking it to assembly
// DEVICE:  ATmega328p
// AUTHOR:  Daniel Raymond
// DATE:    2019-04-10

#define PLtch     PB5
#define PData     PB4
#define PClk      PB3
#define GLtch     PB2
#define GData     PB1
#define GClk      PB0

#define leftBtn   PC5
#define rightBtn  PC4
#define downBtn   PC3
#define upBtn     PC2

#define LEFT      0
#define RIGHT     1
#define UP        2
#define DOWN      4

#define T1ps64    0b00000011
#define T1ps256   0b00000100

uint8_t appleX;
uint8_t appleY;

uint8_t headX = 0;
uint8_t headY = 0;
uint8_t headDir = DOWN;

uint8_t tailX = 0;
uint8_t tailY = -3;

uint8_t snkLength = (headY - tailY) + (headX - tailX);
uint8_t mvIndex = 0;

boolean snakeMove = false;
boolean apple = false;
boolean btnPress = false;
boolean game = true;

uint8_t directions[64] = {
  DOWN, DOWN, DOWN
};

uint8_t LEDs[8] = {
  0b10000000,
  0b00000000,
  0b00000000,
  0b00000000,
  0b00000000,
  0b00000000,
  0b00000000,
  0b00000000,
};

void setup() {
  cli();                        // Disable global interrupt system while configuring
  TCCR1A = 0;                   // Normal Mode (start with the simplest)
  TCCR1B = T1ps256;             // Prescaler
  TIMSK1 = 1 << TOIE1;          // Enable Timer1 overflow interrupt ability
  EICRA = 1 << ISC00 | 1 << ISC01;// INT0 interrupt to detect RISING edge
  EIMSK = 1 << INT0;            // Enable 1st Ext. interrupt
  sei();                        // Re-enable global interrupt

  DDRB = 0xFF;
  randomSeed(analogRead(A0));
  spawnApple();
}

void loop() {
  if (btnPress)               // If the button hasn't been pressed, continue in the same direction
    changeDir();

  if (snakeMove && game) {      // If the timer Interrupt has triggered...
    snakeMove = false;
    moveHead();                 // Move the head in the right direction
    if (!apple && game)
      moveTail();               // If the apple hasn't been eaten, move the tail
    //    printArray(LEDs);
    //    printCoordinates();
    updateLength();
    if (snkLength == 10)        // Speeds the game up if the players has reached as certain snake length
      TCCR1B = T1ps64;
  }
  shiftArray(LEDs);             // Display the Array
}



/*                                                                                                                                          Snake Control Functions */
void moveHead() {
  if (headDir == LEFT && headX != 0)                     // Direction && Boundary
    headX -= 1;
  else if (headDir == RIGHT && headX != 7)
    headX += 1;
  else if (headDir == UP && headY != 0)
    headY -= 1;
  else if (headDir == DOWN && headY != 7)
    headY += 1;
  else
    lose();

  if (headX == appleX && headY == appleY)
    apple = true;
  else if (LEDs[headY] & 0x80 >> headX) // If the lead is already on, then you lose (hitting the snake)
    lose();

  LEDs[headY] |= 0x80 >> headX;
}
void moveTail() {
  uint8_t tailDir = directions[mvIndex];

  if (tailDir == LEFT)
    tailX -= 1;
  else if (tailDir == RIGHT)
    tailX += 1;
  else if (tailDir == UP)
    tailY -= 1;
  else if (tailDir == DOWN)
    tailY += 1;
  directions[mvIndex] = headDir;
  LEDs[tailY] &= ~(0x80 >> tailX);
}
void changeDir() {
  uint8_t prevDir = headDir;
  
  btnPress = false;
  for (uint8_t i = 0; i < 4; i++) {                     // Reads in all the inputs: if it's high, set the head direction
    if (PINC & (1 << (5 - i)))
      headDir = 0b100 >> i;
  }
  // To avoid players going back on the snake
  if (prevDir + headDir == UP + DOWN)                   // Only if either direction is up & the other is down will it ignore the input
    headDir = prevDir;
  else if (prevDir + headDir == LEFT + RIGHT)           // Only if either direction is left & the other is right will it ignore the input
    headDir = prevDir;

  if (!game) {                                          // If the game is over, pressing a button will restart it
    game = true;
    headX = 0;
    headY = 0;
    headDir = DOWN;
    tailX = 0;
    tailY = -3;
    mvIndex = 0;
    snkLength = 3;
    for (uint8_t i = 0; i < snkLength; i++)
      directions[i] = DOWN;
    for (uint8_t i = 0; i < 8; i++)
      LEDs[i] = 0;
    spawnApple();
    TCCR1B = T1ps256;
  }
}
void updateLength() {
  if (apple) {                                          // If the apple has been eaten, spawn another & increase the length
    snkLength++;                                        // Increases the length of the snake
    spawnApple();                                       // Spawns a new apple
    for (uint8_t i = snkLength - 1; i > mvIndex; i--)   // Shifts all the directions above to fill the open cell
      directions[i] = directions[i - 1];
  }
  directions[mvIndex] = headDir;                        // Sets the direction that the tail will move {snkLength} turns from now
  mvIndex++;                                            // Shifts the direction for the tail to the next one
  mvIndex %= snkLength;                                 // Reset index if it is equal to snake's length
}






/*                                                                                                                                          Game Control Functions */
void lose() {
  for (uint8_t i = 0; i < 8; i++)                       // Stop timers from incrementing and turn the screen completely on
    LEDs[i] = 0xFF;
  game = false;
}
void spawnApple() {
  apple = false;
  do {                                                  // Gives the apple random coordinates
    appleX = random(0, 7);
    appleY = random(0, 7);
  } while ((LEDs[appleY] & 0x80 >> appleX));      // If the LED is already on, try again

  LEDs[appleY] |= 0x80 >> appleX;
}








/*                                                                                                                                          Printing Functions */
void printArray(uint8_t data[8]) {
  for (uint8_t i = 0; i < 8; i++) {
    for (uint8_t x = 1; x < 8; x++)
      if (data[i] < (1 << (x)))
        Serial.print('0');
    Serial.println(data[i], BIN);
  }
  Serial.println();
}
void printCoordinates() {
  Serial.print(tailX);
  Serial.print(", ");
  Serial.println(tailY);
  Serial.print(headX);
  Serial.print(", ");
  Serial.println(headY);
}




/*                                                                                                                                           ShiftOut Functions */
void shiftArray(uint8_t data[8]) {
  uint8_t mask = 128;
  for (uint8_t i = 0; i < 8; i++) {
    shiftZero(PLtch, PData, PClk);          // Ground the power SR
    shiftBits(GLtch, GData, GClk, ~mask);   // Change the ground column
    shiftBits(PLtch, PData, PClk, data[i]); // Send out the data for that row
    mask >>= 1;
  }
}
void shiftZero(uint8_t Latch, uint8_t Data, uint8_t Clock) {
  PORTB &= ~(1 << Latch);             // Set Latch low
  PORTB &= ~(1 << Data);              // Set Data low
  for (uint8_t i = 0; i < 8; i++) {   // Loop the clock: shift in zeroes
    PORTB &= ~(1 << Clock);
    PORTB |= 1 << Clock;
  }
  PORTB |= 1 << Latch;                // Set Latch high: Send out bits
}
void shiftBits(uint8_t Latch, uint8_t Data, uint8_t Clock, uint8_t Byte) {
  uint8_t bt;                         // Bit in question in the byte
  uint8_t mask = 1;                   // Cycling Mask
  PORTB &= ~(1 << Latch);             // Set latch low (Start readin in bits)

  for (uint8_t i = 0; i < 8; i++) {
    PORTB &= ~(1 << Clock);           // Set Clock low
    bt = (Byte & mask) >> i;          // bit = byte or'd with mask

    if (bt)                           // If the bit is a 1, set data pin high
      PORTB |= 1 << Data;
    else                              // otherwise, put it low
      PORTB &= ~(1 << Data);

    PORTB |= 1 << Clock;              // Set the clock pin high to store the bit
    mask <<= 1;                       // Shift the mask over by one
  }
  PORTB |= 1 << Latch;                // Set latch high
}






/*                                                                                                                                          Interrupt Functions */
ISR(TIMER1_OVF_vect) {
  snakeMove = true;
}

ISR(INT0_vect) {
  btnPress = true;
}
