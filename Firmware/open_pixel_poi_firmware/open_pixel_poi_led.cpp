#ifndef _OPEN_PIXEL_POI_LED
#define _OPEN_PIXEL_POI_LED

#include "open_pixel_poi_config.cpp"

// LED
#include <Adafruit_NeoPixel.h>

//#define DEBUG  // Comment this line out to remove printf statements in released version
#ifdef DEBUG
#define debugf(...) Serial.print("  <<led>> ");Serial.printf(__VA_ARGS__);
#define debugf_noprefix(...) Serial.printf(__VA_ARGS__);
#else
#define debugf(...)
#define debugf_noprefix(...)
#endif

class OpenPixelPoiLED {
  private:
    OpenPixelPoiConfig& config;
    int brightness = 0;
    uint8_t red;
    uint8_t green;
    uint8_t blue;

    // Declare our NeoPixel strip object:
    Adafruit_NeoPixel led_strip{22, D8, NEO_GRB + NEO_KHZ800};
    
  public:
    OpenPixelPoiLED(OpenPixelPoiConfig& _config): config(_config) {}    
    int frameIndex;
    void setup(){
      debugf("Setup begin\n");


      // LED Setup:
      led_strip.begin();
      frameIndex = 0;

      debugf("LED setup complete\n");
    }

    void loop(){

      led_strip.clear();
      if(config.displayState == DS_PATTERN){
        for (int j=0; j<20; j++){
          red = config.pattern[frameIndex*config.frameHeight*3 + j%config.frameHeight*3 + 0];
          green = config.pattern[frameIndex*config.frameHeight*3 + j%config.frameHeight*3 + 1];
          blue = config.pattern[frameIndex*config.frameHeight*3 + j%config.frameHeight*3 + 2];
          led_strip.setPixelColor(j, led_strip.Color(red, green, blue));
        }
        frameIndex += 1;
        if(frameIndex >= config.frameCount){
          frameIndex = 0;
        }
      }else if(config.displayState == DS_WAITING || config.displayState == DS_WAITING2 || config.displayState == DS_WAITING3){
        // 500ms or till interupted
        if(config.displayState == DS_WAITING){
          // Blue for blinky!
          red = 0x00;
          green = 0x00;
          blue = 0xff;
        }else if(config.displayState == DS_WAITING2){
          // White for brightness!
          red = 0x88;
          green = 0x88;
          blue = 0x88;
        }else if(config.displayState == DS_WAITING3){
          // RED for speed!
          red = 0xFF;
          green = 0x00;
          blue = 0x00;
        }
        for(int j=0; j<20; j++){
          if(j == (millis() - config.displayStateLastUpdated)/50 || 20 - j == (millis() - config.displayStateLastUpdated)/50){
            led_strip.setPixelColor(j, led_strip.Color(red, green, blue));
          }else{
            led_strip.setPixelColor(j, led_strip.Color(0x00, 0x00, 0x00));
          }
        }
      }else if(config.displayState == DS_VOLTAGE){
        if(config.batteryPercent > 0.75){
          red = 0x00;
          green = 0xff;
          blue = 0x00;
        }else if(config.batteryPercent > 0.30){
          red = 0xAA;
          green = 0xAA;
          blue = 0x00;
        }else{
          red = 0xFF;
          green = 0x00;
          blue = 0x00;
        }
        for (int j=0; j<config.batteryPercent * 20; j++){
          led_strip.setPixelColor(20-j, led_strip.Color(red, green, blue));
        }
      }else if(config.displayState == DS_SHUTDOWN){
        // 2000ms
        // Crappy but simple shutdown animation for now
        red = /*strobe*/((millis() - config.displayStateLastUpdated) % 200 > 100) * /*color*/0xFF * /*fade out*/((2000-(millis() - config.displayStateLastUpdated))/2000.0);
        for(int j=0; j<20; j++){
          led_strip.setPixelColor(j, led_strip.Color(red, 0x00, 0x00));
        }
      }else if(config.displayState == DS_BRIGHTNESS){
        // Override brightness without saving it. Button will save it upon release.
        if(millis() - config.displayStateLastUpdated < 500){
          config.ledBrightness = 1;
        }else if(millis() - config.displayStateLastUpdated < 1000){
          config.ledBrightness = 4;
        }else if(millis() - config.displayStateLastUpdated < 1500){
          config.ledBrightness = 10;
        }else if(millis() - config.displayStateLastUpdated < 2000){
          config.ledBrightness = 25;
        }else{
          config.ledBrightness = 100;
        }
        red = 0xFF;
        green = 0xFF;
        blue = 0xFF;
        for (int j=0; j< 20; j++){
          led_strip.setPixelColor(j, led_strip.Color(red, green, blue));
        }
      }else if(config.displayState == DS_SPEED){
        red = 0xFF;
        for (int j=0; j< (millis() - config.displayStateLastUpdated)/500; j++){
          led_strip.setPixelColor(j, led_strip.Color(red, green, blue));
        }
      }
      
      led_strip.setBrightness(config.ledBrightness * config.brightnessLimiter);
      led_strip.show();
      delay(1000/(config.animationSpeed*2));
      
    }
};

#endif
