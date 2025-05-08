#ifndef _OPEN_PIXEL_POI_CONFIG
#define _OPEN_PIXEL_POI_CONFIG

#include <FS.h>
#include <SPIFFS.h>
#include <Preferences.h>

#define DEBUG  // Comment this line out to remove printf statements in released version
#ifdef DEBUG
#define debugf(...) Serial.print("  <<config>> ");Serial.printf(__VA_ARGS__);
#define debugf_noprefix(...) Serial.printf(__VA_ARGS__);
#else
#define debugf(...)
#define debugf_noprefix(...)
#endif

enum DisplayState {
  DS_PATTERN,
  DS_PATTERN_ALL,
  DS_PATTERN_ALL_ALL,
  DS_WAITING,
  DS_WAITING2,
  DS_WAITING3,
  DS_WAITING4,
  DS_WAITING5,
  DS_VOLTAGE,
  DS_VOLTAGE2,
  DS_BANK,
  DS_BRIGHTNESS,
  DS_SPEED,
  DS_SHUTDOWN
};

#define BATTERY_LATCH 0.05
#define BATTERY_VOLTAGE_LOW 3.45
#define BATTERY_VOLTAGE_CRITICAL 3.33
#define BATTERY_VOLTAGE_SHUTDOWN 3.25

#define PATTERN_BANK_SIZE 5
#define PATTERN_BANK_COUNT 3 

// Default number of LEDs if not configured
#define DEFAULT_NUMBER_OF_LEDS 80
// Maximum number of frames to store
#define MAX_FRAMES 400
// Calculate pattern buffer size: 3 bytes (RGB) * number of LEDs * max frames
#define PATTERN_BUFFER_SIZE (3 * DEFAULT_NUMBER_OF_LEDS * MAX_FRAMES)

enum BatteryState {
  BAT_OK,
  BAT_LOW,
  BAT_CRITICAL,
  BAT_SHUTDOWN,
};
  
class OpenPixelPoiConfig {
  private:
    Preferences preferences;
    
  public:
    // Runtime State
    float batteryVoltage = BATTERY_VOLTAGE_LOW;
    BatteryState batteryState = BAT_OK;
    DisplayState displayState = DS_PATTERN;
    long displayStateLastUpdated = 0;
    // Settings (come in from the app)
    uint8_t ledBrightness; 
    uint8_t animationSpeed;
    uint8_t patternSlot;
    uint8_t patternBank;
    uint8_t numberOfLeds = DEFAULT_NUMBER_OF_LEDS;
    // Pattern
    uint8_t frameHeight; 
    uint16_t frameCount;
    uint8_t *pattern = (uint8_t *) malloc(PATTERN_BUFFER_SIZE);
    uint16_t patternLength;

    // Variables
    long configLastUpdated;

    void setLedBrightness(uint8_t ledBrightness) {
      debugf("Save Brightness = %d\n", ledBrightness);
      this->ledBrightness = ledBrightness;
      preferences.putChar("brightness", this->ledBrightness);
      this->configLastUpdated = millis();
    }
    
    void setAnimationSpeed(uint8_t animationSpeed) {
      debugf("Save Speed = %d\n", animationSpeed * 2);
      this->animationSpeed = animationSpeed;
      preferences.putChar("animationSpeed", this->animationSpeed);
      this->configLastUpdated = millis();
    }

    void setPatternSlot(uint8_t patternSlot, bool save) {
      debugf("Save Pattern Slot = %d\n", patternSlot);
      this->patternSlot = patternSlot;
      if(save){
        preferences.putChar("patternSlot", this->patternSlot);
      }

      loadFrameHeight();
      loadFrameCount();
      fillDefaultPattern();
      loadPattern();

      debugf("- frame\n");
      debugf("  - height = %d\n", this->frameHeight);
      debugf("  - count = %d\n", this->frameCount);
      
      this->configLastUpdated = millis();
    }

    void setPatternBank(uint8_t patternBank, bool save) {
      this->patternBank = patternBank;
      if(save){
        preferences.putChar("patternBank", this->patternBank);
      }
      loadFrameHeight();
      loadFrameCount();
      fillDefaultPattern();
      loadPattern();
      
      this->configLastUpdated = millis();
    }
    
    void setFrameHeight(uint8_t frameHeight) {
      this->frameHeight = frameHeight;
      String key = "p";
      key += this->patternSlot + (this->patternBank * PATTERN_BANK_SIZE);
      key += "Height";
      preferences.putChar(key.c_str(), this->frameHeight);
      this->configLastUpdated = millis();
    }
    
    void setFrameCount(uint16_t frameCount) {
      this->frameCount = frameCount;
      String key = "p";
      key += this->patternSlot + (this->patternBank * PATTERN_BANK_SIZE);
      key += "FCount";
      preferences.putUShort(key.c_str(), this->frameCount);
      this->configLastUpdated = millis();
    }
    
    void savePattern() {
      debugf("Save Pattern\n");
      debugf("- length = %d", this->patternLength);
      for (int i=0; i<this->patternLength; i+=3) {
        if (i%this->frameHeight*3 == 0) {
          debugf_noprefix("\n");
          debugf("  ");
        }
        debugf_noprefix("0x%02X%02X%02X ", this->pattern[i], this->pattern[i+1], this->pattern[i+2]);
      }
      debugf_noprefix("\n");

      File file = SPIFFS.open(String("/pattern") + (this->patternSlot + (this->patternBank * PATTERN_BANK_SIZE)) + ".oppp", FILE_WRITE);
      if(!file || file.isDirectory()){
        debugf("− failed to open file for reading\n");
      }else{
        debugf(" - opened file for writing: %d\n");
        
        int written = file.write(pattern, patternLength);
        file.close();
        debugf(" - this much written: %d\n", written);
      }
      
      this->configLastUpdated = millis();
    }

    void fillDefaultPattern(){
      for (int i=0; i < this->frameCount; i++) {
        for (int j=0; j < this->frameHeight; j++) {
          if(i % 2 == 1){
            pattern[(i * this->frameHeight * 3) + (j*3) + 0] = 0xFF;
            pattern[(i * this->frameHeight * 3) + (j*3) + 1] = 0xFF;
            pattern[(i * this->frameHeight * 3) + (j*3) + 2] = 0x00;
          }else{
            pattern[(i * this->frameHeight * 3) + (j*3) + 0] = 0x00;
            pattern[(i * this->frameHeight * 3) + (j*3) + 1] = 0x00;
            pattern[(i * this->frameHeight * 3) + (j*3) + 2] = 0x00;
          }
        }
      }
    }

    void loadPattern(){
      File file = SPIFFS.open(String("/pattern") + (this->patternSlot  + (this->patternBank * PATTERN_BANK_SIZE)) + ".oppp");
      if(!file || file.isDirectory()){
        debugf("− failed to open file for reading\n");
      }else{
        debugf(" - this much available: %d\n", file.available());
        file.read(pattern, file.available());
        file.close();
      }
    }

    void loadFrameHeight(){
      String key = "p";
      key += (this->patternSlot  + (this->patternBank * PATTERN_BANK_SIZE));
      key += "Height";
      this->frameHeight = preferences.getChar(key.c_str(), this->numberOfLeds);
    }

    void loadFrameCount(){
      String key = "p";
      key += (this->patternSlot  + (this->patternBank * PATTERN_BANK_SIZE));
      key += "FCount";
      debugf("key = %s\n", key);
      this->frameCount = preferences.getUShort(key.c_str(), 2);
    }

    void setNumberOfLeds(uint8_t numberOfLeds) {
      debugf("Save Number of LEDs = %d\n", numberOfLeds);
      this->numberOfLeds = numberOfLeds;
      preferences.putChar("numberOfLeds", this->numberOfLeds);
      this->configLastUpdated = millis();
    }
      
    
    void setup() {
      debugf("Setup begin\n");
      debugf("Load Config (setup)\n");

      if(!SPIFFS.begin(true)){
        debugf("SPIFFS Mount Failed\n");
      }

      preferences.begin("led_pattern", false);
      debugf("Preffs free entries: %d\n", preferences.freeEntries());

      this->ledBrightness = preferences.getChar("brightness", 0x0A);
      debugf("- brightness = %d\n", this->ledBrightness);

      this->animationSpeed = preferences.getChar("animationSpeed", 0x0A);
      debugf("- animation speed = %d frames per sec\n", this->animationSpeed * 2);

      this->numberOfLeds = preferences.getChar("numberOfLeds", DEFAULT_NUMBER_OF_LEDS);
      debugf("- number of LEDs = %d\n", this->numberOfLeds);

      this->patternSlot = preferences.getChar("patternSlot", 0x00);
      debugf("- pattern slot = %d\n", this->patternSlot);

      this->patternBank = preferences.getChar("patternBank", 0x00);
      debugf("- pattern bank = %d\n", this->patternBank);

      loadFrameHeight();
      loadFrameCount();
      debugf("- frame\n");
      debugf("  - height = %d\n", this->frameHeight);
      debugf("  - count = %d\n", this->frameCount);
      
      fillDefaultPattern();

      loadPattern();

      debugf("- pattern\n");
      for (int i = 0; i < this->frameHeight * this->frameCount; i+=3 ) {
        if (i%this->frameHeight*3 == 0) {
          debugf_noprefix("\n");
          debugf("    ");
        }
        debugf_noprefix("0x%02X%02X%02X ", this->pattern[i], this->pattern[i+1], this->pattern[i+2]);
      }
      debugf_noprefix("\n");
      
      debugf("Setup complete\n");
    }

    void loop(){
      // Pattern Cycling
      if((this->displayState == DS_PATTERN_ALL || this->displayState == DS_PATTERN_ALL_ALL) && millis() - this->displayStateLastUpdated >  10000){
        this->setPatternSlot((this->patternSlot + 1) % PATTERN_BANK_SIZE, false);
        if(this->patternSlot == 0 && this->displayState == DS_PATTERN_ALL_ALL){
          this->setPatternBank((this->patternBank + 1) % PATTERN_BANK_COUNT, false);
        }
        this->displayStateLastUpdated = millis();
      }

      // Battery latching state
      if(batteryVoltage <= BATTERY_VOLTAGE_SHUTDOWN || batteryState == BAT_SHUTDOWN){
        batteryState = BAT_SHUTDOWN;
      }else if(batteryVoltage <= BATTERY_VOLTAGE_CRITICAL || (batteryState == BAT_CRITICAL && batteryVoltage <= BATTERY_VOLTAGE_CRITICAL + BATTERY_LATCH)){
        batteryState = BAT_CRITICAL;
      }else if(batteryVoltage <= BATTERY_VOLTAGE_LOW || (batteryState == BAT_LOW && batteryVoltage <= BATTERY_VOLTAGE_LOW + BATTERY_LATCH)){
        batteryState = BAT_LOW;
      }else {
        batteryState = BAT_OK;
      }
      
    }
};

#endif
