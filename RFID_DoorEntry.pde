
// Don't forget to unplug the ID-20 connection to the Arduino Rx pin before uploading (or you'll get errors during the upload)
// Connect Pin 9 (D0) from the ID-20 to Rx (Pin 0) in the Arduino
// The ID-20 returns 16 bytes. The first byte is 0x02 which means a 12 byte RFID sequence is about to follow
// After the 12 bytes RFID, there's a 0x0D, 0x0A and 0x03. I'm just flushing the final characters, but if you want more
// thorough check, you could ensure the final three bytes match these. 

#include <EEPROM.h>    // We're going to store RFID ID tags (that aren't hard coded) here

int i = 0;   // Don't know why, but if the clockPin etc. #defines appear first, then the compile fails!

#define clockPin 8
#define latchPin 10
#define dataPin 12

#define switchPin 4

#define failMode 0
#define dayMode 7
#define singleMode 1
#define resetMode 4            // If presented it will erase any tags stored in EEPROM
#define masterMode 9

#define tagDelay 3000          // On valid RFID Tag, hold door open for 3 seconds

#define amberLED B00010000     // RFID Tag Successfully Read
#define greenLED B00001000     // RFID Tag Recognised
#define redLED   B00000100     // RFID Tag Not Recognised
#define blueLED  B00000010     // RFID TAG is a Master Tag (for programming other tags)
#define entryLED B00100000     // Entry Authorised
#define openDoor B01000000     // Open the Door so they don't have to press the Button

char tagString[13];            // When a RFID Tag is read, this is where it gets stored
int tagID = 0;                 // The TagID number (0 - n) which we use to look in the allowedTags and tagName arrays
int tagPresented = 0;          // was an RFID tag just presented?
unsigned long tagPresentedTime = 0;
int dayModeActive = 0;         // If an IT Team Member opens the door during working hours then engage day mode which will allow the door to be opened by pressing the switch

char allowedTags[][13] = {
  "XXXXXXXXXXXX",   // FAIL - Should never get this
  "30008BF41659",   // Master Card
  "4400B091284D",   // Anthony
  "X400B091294C",   // Lynne
  "30008BD91C7E",   // Reset Card
  "IT-Slot 04  ",   // IT Team Slot 04
  "IT-Slot 05  ",   // IT Team Slot 05
  "IT-Slot 06  ",   // IT Team Slot 06
  "IT-Slot 07  ",   // IT Team Slot 07
  "IT-Slot 08  ",   // IT Team Slot 08
  "IT-Slot 09  ",   // IT Team Slot 09
  "IT-Slot 10  ",   // IT Team Slot 10
  "------------",   // Spare Slot 01 - Load an RFID from EEPROM in here onwards
  "------------",   // Spare Slot 02 - Load an RFID from EEPROM in here onwards
  "------------",   // Spare Slot 03 - Load an RFID from EEPROM in here onwards
  "------------",   // Spare Slot 04 - Load an RFID from EEPROM in here onwards
  "------------",   // Spare Slot 05 - Load an RFID from EEPROM in here onwards
  "------------",   // Spare Slot 06 - Load an RFID from EEPROM in here onwards
  "------------",   // Spare Slot 07 - Load an RFID from EEPROM in here onwards
  "------------",   // Spare Slot 08 - Load an RFID from EEPROM in here onwards
  "------------",   // Spare Slot 09 - Load an RFID from EEPROM in here onwards
  "------------"    // Spare Slot 10 - Load an RFID from EEPROM in here onwards
};

char* tagName[] = {
  "FAIL",        // Should never get this
  "Master",
  "Anthony",
  "Lynne",
  "Reset",
  "IT Team Slot 04",
  "IT Team Slot 05",
  "IT Team Slot 06",
  "IT Team Slot 07",
  "IT Team Slot 08",
  "IT Team Slot 09",
  "IT Team Slot 10",
  "Spare 01",            // Programmed Cards will be loaded here
  "Spare 02",            // Programmed Cards will be loaded here
  "Spare 03",            // Programmed Cards will be loaded here
  "Spare 04",            // Programmed Cards will be loaded here
  "Spare 05",            // Programmed Cards will be loaded here
  "Spare 06",            // Programmed Cards will be loaded here
  "Spare 07",            // Programmed Cards will be loaded here
  "Spare 08",            // Programmed Cards will be loaded here
  "Spare 09",            // Programmed Cards will be loaded here
  "Spare 10"             // Programmed Cards will be loaded here
};

int tagMode[] = {
  failMode,      // Fail
  masterMode,    // Master Card to program new RFID Tags
  dayMode,       // Anthony - IT Team Member
  dayMode,       // Lynne - IT Team Member
  resetMode,     // Reset Card - erases the EEPROM
  failMode,      // IT Team Slot 04
  failMode,      // IT Team Slot 05
  failMode,      // IT Team Slot 06
  failMode,      // IT Team Slot 07
  failMode,      // IT Team Slot 08
  failMode,      // IT Team Slot 09
  failMode,      // IT Team Slot 10
  failMode,      // Spare Slot 01
  failMode,      // Spare Slot 02
  failMode,      // Spare Slot 03
  failMode,      // Spare Slot 04
  failMode,      // Spare Slot 05
  failMode,      // Spare Slot 06
  failMode,      // Spare Slot 07
  failMode,      // Spare Slot 08
  failMode,      // Spare Slot 09
  failMode       // Spare Slot 10
};

int numberOfTags = sizeof(allowedTags) / sizeof(allowedTags[0]);


void setup () {
  pinMode(clockPin, OUTPUT);
  pinMode(latchPin, OUTPUT);
  pinMode(dataPin, OUTPUT);
  
  pinMode(switchPin, INPUT);
  digitalWrite(switchPin, HIGH);   // Activate the Pull-Up Resistor
  
  Serial.begin(9600);
  Serial.println("The RFID Door Entry System is Ready");

  setLED(0x00);
  
  loadStoredTags();
}

void loop() {
  byte val;
  
  if (digitalRead(switchPin) == 0 && dayModeActive == 1) {
    setLED(openDoor);
    delay(tagDelay);
    setLED(0x00 + (dayModeActive * entryLED));
    delay(500);
    return;
  }
  
  if (tagPresented == 1) {   // A tag was resently presented
    if ((millis() - tagPresentedTime) > tagDelay) {    // Allow a few seconds to get through the door
      tagPresented = 0;
      setLED(0x00 + (dayModeActive * entryLED));
      return;
    } else {
      Serial.flush();    // Don't accept any other cards for the moment
      return;
    }
  }

  if (Serial.available()) {
    int RFID_Status = get_RFID();    // 0 means got a RFID Tag, anything else is an error
    
    tagPresented = 0;  // Make sure this is clear

    switch (RFID_Status) {
      case 0: {
        Serial.println("RFID Tag Successfully Read");
        processTag();   // Got an RFID Tag - Let's decide what to do
        tagPresented = 1;
        tagPresentedTime = millis();
        return;
      }
              
      case 1: {
        Serial.println("No Serial Data Available");
        errorLED();
        return;
      }
      case 2: {
        Serial.println("Bad RFID Data Sequence - Expecting 0x02 at the start");
        errorLED();
        return;
      }
      case 3: {
        Serial.println("Timeout (0.5 Seconds). Didn't receive all data in expected time-frame");
        errorLED();
        return;
      }
      otherwise: {
        Serial.print(RFID_Status);
        Serial.println(": Unknown Error");
        errorLED();
        return;
      }
    }
    
  }
}


void processTag() {
  if (tagID == 0) {
    Serial.println("Unknown RFID Tag");
    setLED(amberLED | redLED);
    return;
  }
  
  if (tagMode[tagID] == failMode) {
    Serial.print(tagName[tagID]);
    Serial.println(" - Recognised Tag, but tagMode is Fail");
    errorLED();
    setLED(amberLED);
    return;
  }
  
  if (tagMode[tagID] == resetMode) {
    clearTagEEPROM();
    setLED(0x00);
    return;
  }
  
  Serial.print("Hello Authorized User: ");
  Serial.print(tagID);
  Serial.print(" - ");
  Serial.println(tagName[tagID]);

  if (tagMode[tagID] == masterMode) {
    setLED(amberLED | blueLED);
    unsigned long programStartTime = millis();    // Need to give them 10 seconds to present card to be programmed.
    while ((millis() - programStartTime) < 10000) {
      if (Serial.available()) break ;
    }
    if (Serial.available() == 0) {
      setLED(0x00);  // No new RFID tag was presented, so just return
      return;
    }
// Looks like a new tag is available, lets get it.    
    int newTag = get_RFID();
    if (newTag != 0) { // Something went wrong - whatever data we got wasn't a valid RFID Tag
      Serial.println("Didn't get a valid tag");
      setLED(0x00);
      errorLED();
      setLED(0x00);
      return;
    }
    
    if (tagID != 0) {  // Already got this RFID in our lookup table - don't want a duplicate
      Serial.println("Already have this RFID Tag in the table");
      errorLED();
      setLED(0x00);
      return;
    }
    
    Serial.print("Storing New RFID in EEPROM ");
    Serial.println(tagString);
    int eSlot = storeTagEEPROM(tagString);
    if (eSlot == 99) {  // Failed - probably no free slots)
      return;
    }
    setLED(greenLED);
    delay(1000);
    flashLED(amberLED | greenLED | redLED | blueLED, eSlot + 1);   // The first slot is zero, but we'll understand that it's actually 1
    delay(250);
    setLED(0x00);
    return;
  }
  
// Open the Door
  setLED(amberLED | greenLED | entryLED | openDoor);

// If it's a DayMode tag, then toggle the DayMode
  if (tagMode[tagID] == dayMode) {
// Should be a check here to see what time of day it is
    if (dayModeActive)
      dayModeActive = 0;
    else
      dayModeActive = 1;
  }
  
  delay(250); // Wait here for 1/4 second 
}


int get_RFID() {
  byte val = 0;
  byte byte_count = 0;
  
  tagID = 0;
    
  if (Serial.available() == 0) {
    return(1);   // No Serial data available - shouldn't ever get here!
  }
  
// If the first byte we get isn't a 0x02 then something has gone wrong. Best thing to do is flush the serial buffer and let them try again.
  if (Serial.read() != 0x02) {
    Serial.flush();
    return(2);   // Return an Error Number so the calling function knowns that we didn't get an RFID number
  }
    
// Make a note of the time - don't want to get stuck in here waiting for data that's never going to arrive
  unsigned long RFID_StartTime = millis();
  
  while (byte_count < 12) {
    if (Serial.available() == 0) {
      if ((millis() - RFID_StartTime) > 500) {   // Allow 0.5 seconds to read the RFID
        Serial.flush();
        return(3);
      }
      continue;
    }
      
    val = Serial.read();
    tagString[byte_count] = val;
    byte_count++;
  }
  tagString[12] = '\0';   // Terminate the RFID Tag string

  setLED(amberLED);  // Indicate that we've successfully read the RFID Tag
  
  Serial.print("\nRFID Card ID Number (STR): ");
  Serial.println(tagString);
  
  tagID = findTag(tagString);
  
  Serial.flush();
  
  return(0);    // The global variable tagID will tell calling function which RFID Tag was presented
}

int findTag(char tagValue[12]) {
// The first entry in allowedTags is FAIL, so we can ignore it (hence the loops starts at 1). If we return 0, then we know it's a fail  
  for (int thisCard = 1; thisCard < numberOfTags; thisCard++) {
    if (strcmp(tagValue, allowedTags[thisCard]) == 0) {
      return(thisCard);
    }
  }
  return(0);
}

void setLED(byte ledStatus) {
  digitalWrite(latchPin, LOW);
  shiftOut(dataPin, clockPin, MSBFIRST, ledStatus);
  digitalWrite(latchPin, HIGH);
}

void errorLED() {
  for (int i = 0; i < 3; i++) {
    setLED(amberLED);
    delay(100);
    setLED(greenLED);
    delay(100);
    setLED(redLED);
    delay(100);
    setLED(blueLED);
    delay(100);
    setLED(redLED);
    delay(100);
    setLED(greenLED);
    delay(100);
  }
  setLED(0x00);  
}

void flashLED(int whichLED, int flashCount) {
  for (int flashLoop = 0; flashLoop < flashCount; flashLoop++) {
    setLED(whichLED);
    delay(200);
    setLED(0x00);
    delay(200);
  }
}

void loadStoredTags() {
  Serial.println("Loading any stored RFID Tags");
  for (int tagSlot = 0; tagSlot < 10; tagSlot++) {
    if (EEPROM.read((tagSlot * 12)) == 0) {
      continue;
    }
    Serial.print("Slot ");
    Serial.print(tagSlot);
    Serial.print(": ");
    for (int tagByte = 0; tagByte < 12; tagByte++) {
      Serial.print(EEPROM.read((tagSlot * 12) + tagByte));
      allowedTags[tagSlot + 12][tagByte] = EEPROM.read((tagSlot * 12) + tagByte);
      tagMode[tagSlot + 12] = singleMode;
    }
    Serial.println("");
  }
  
  showTagTable();
}

int storeTagEEPROM(char tagValue[12]) {
  int addr = 0;
  int tagSlot = 0;
  int tagByte = 0;

  // Find a Spare Slot in EEPROM
  for (tagSlot = 0; tagSlot < 10; tagSlot++) {
    addr = tagSlot * 12;
    if (EEPROM.read(addr) == 0x00) {
      break;
    }
  }
  if (tagSlot == 10) {
    Serial.println("No Spare Slots - Need to Erase them are start again");
    errorLED();
    flashLED(redLED, 7);
    return(99);
  }

  Serial.print("Storing the new RFID tag in slot ");
  Serial.println(tagSlot);
        
// Store the new RFID Tag in EEPROM
  for (tagByte = 0; tagByte < 12; tagByte++) {
    addr = (tagSlot * 12) + tagByte;
    EEPROM.write(addr, tagValue[tagByte]);
  }
  
// Stored the new RFID Tag in the lookup table so that'll it work straight away
  for (tagByte = 0; tagByte < 12; tagByte++) {
    allowedTags[tagSlot + 12][tagByte] = tagValue[tagByte];
    tagMode[tagSlot + 12] = singleMode;
  }
  
  showTagTable();

  return(tagSlot);
}

void clearTagEEPROM() {
  int addr = 0;
  int tagSlot = 0;
  int tagByte = 0;
  
  Serial.println("Erasing the EEPROM - This will clean any stored RFID Tags");
  delay(1000);
  
  for (tagSlot = 0; tagSlot < 10; tagSlot++) {
    flashLED(amberLED | blueLED, 1);
    for (tagByte = 0; tagByte < 12; tagByte++) {
      addr = (tagSlot * 12) + tagByte;
      EEPROM.write(addr, 0);
    }
  }

  for (tagSlot = 0; tagSlot < 10; tagSlot++) {
    flashLED(greenLED | redLED, 1);
    for (tagByte = 0; tagByte < 12; tagByte++) {
      allowedTags[tagSlot + 12][tagByte] = '-';
      tagMode[tagSlot + 12] = failMode;
    }
  }   
  showTagTable();
}

void showTagTable() {
  Serial.println("\nAllowedTags Table is:-");
  for (int tagSlot = 0; tagSlot < 22; Serial.println(allowedTags[tagSlot++]));
}

