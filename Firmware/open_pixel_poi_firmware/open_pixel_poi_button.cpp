#ifndef _OPEN_PIXEL_POI_BUTTON
#define _OPEN_PIXEL_POI_BUTTON

#include "open_pixel_poi_config.cpp"
#include <driver/rtc_io.h>
#include <driver/gpio.h>
#include "esp_sleep.h"

//#define DEBUG  // Comment this line out to remove printf statements in released version
#ifdef DEBUG
#define debugf(...) Serial.print("<<button>> ");Serial.printf(__VA_ARGS__);
#define debugf_noprefix(...) Serial.printf(__VA_ARGS__);
#else
#define debugf(...)
#define debugf_noprefix(...)
#endif

enum ButtonState {
  BS_INITIAL,
  BS_CLICK_DOWN,
  BS_CLICK_UP,
  BS_HOLD,
  BS_CLICK_CLICK_DOWN,
  BS_CLICK_CLICK_UP,
  BS_CLICK_HOLD,
  BS_CLICK_CLICK_CLICK_DOWN,
  BS_CLICK_CLICK_CLICK_UP,
  BS_CLICK_CLICK_HOLD,
  BS_SHUTDOWN
};

class OpenPixelPoiButton {

private:
  OpenPixelPoiConfig& config;

  int filteredButtonInput = 1000;
  int buttonState = 0;
  long downTime = 0;
  bool regulatorEnabled = true;

  float battVoltage = 3.7;

  long shutDownAt = 0;

public:
  OpenPixelPoiButton(OpenPixelPoiConfig& _config): config(_config) {}    

  void setup() {
    // Voltage Input
    pinMode(A0, INPUT);

    //Button Input
    pinMode(A1,INPUT_PULLUP);

    // Regulator Output
    pinMode(D7, OUTPUT);
    regulatorEnabled = true;
    digitalWrite(D7, HIGH);

  }

  void loop() {
    filteredButtonInput = (filteredButtonInput * 0.80) + (analogRead(A1) * .20);
    if(filteredButtonInput < 100){
      if(buttonState == BS_INITIAL){ // Single Click
        downTime = millis();
        buttonState = BS_CLICK_DOWN;
        // Trigger Waiting Animation
        config.displayState = DS_WAITING;
        config.displayStateLastUpdated = millis();
      }else if(buttonState == BS_CLICK_UP){ // Double Click
        downTime = millis();
        buttonState = BS_CLICK_CLICK_DOWN;
        // Trigger Waiting Animation
        config.displayState = DS_WAITING2;
        config.displayStateLastUpdated = millis();
      }else if(buttonState == BS_CLICK_CLICK_UP){ // Triple Click
        downTime = millis();
        buttonState = BS_CLICK_CLICK_CLICK_DOWN;
        // Trigger Waiting Animation
        config.displayState = DS_WAITING3;
        config.displayStateLastUpdated = millis();
      }else if(buttonState == BS_CLICK_DOWN && millis() - downTime >= 500){ // Hold
        buttonState = BS_HOLD;
        // Trigger voltage display
        config.displayState = DS_VOLTAGE;
        config.displayStateLastUpdated = millis();// TODO: add voltage state
      }else if(buttonState == BS_HOLD && millis() - downTime >= 3000){ // Long Hold
        buttonState = BS_SHUTDOWN;
        config.displayState = DS_SHUTDOWN;
        config.displayStateLastUpdated = millis();
        shutDownAt = millis();
      }else if(buttonState == BS_CLICK_CLICK_DOWN && millis() - downTime >= 500){ // Click Hold
        buttonState = BS_CLICK_HOLD;
        // Trigger voltage display
        config.displayState = DS_BRIGHTNESS;
        config.displayStateLastUpdated = millis();// TODO: add voltage state
      }else if(buttonState == BS_CLICK_CLICK_CLICK_DOWN && millis() - downTime >= 500){ // Click Click Hold
        buttonState = BS_CLICK_CLICK_HOLD;
        // Trigger voltage display
        config.displayState = DS_SPEED;
        config.displayStateLastUpdated = millis();// TODO: add voltage state
      }
    }else{
      if(buttonState == BS_CLICK_DOWN){
        buttonState = BS_CLICK_UP;
      }else if(buttonState == BS_CLICK_CLICK_DOWN){
        buttonState = BS_CLICK_CLICK_UP;
      }else if(buttonState == BS_CLICK_CLICK_CLICK_DOWN){
        buttonState = BS_CLICK_CLICK_CLICK_UP;
      }else if(buttonState == BS_HOLD){
        buttonState = BS_INITIAL;
        config.displayState = DS_PATTERN;
        config.displayStateLastUpdated = millis();
      }else if(buttonState == BS_CLICK_HOLD){
        if(millis() - downTime < 1000){
          config.setLedBrightness(1);
        }else if(millis() - downTime < 1500){
          config.setLedBrightness(4);
        }else if(millis() - downTime < 2000){
          config.setLedBrightness(10);
        }else if(millis() - downTime < 2500){
          config.setLedBrightness(25);
        }else{
          config.setLedBrightness(100);
        }
        buttonState = BS_INITIAL;
        config.displayState = DS_PATTERN;
        config.displayStateLastUpdated = millis();
      }else if(buttonState == BS_CLICK_CLICK_HOLD){
        if((millis() - config.displayStateLastUpdated) / 500 <= 5){
          config.setAnimationSpeed((millis() - config.displayStateLastUpdated) / 500);
        }else if((millis() - config.displayStateLastUpdated) / 500 <= 10){
          config.setAnimationSpeed(((millis() - config.displayStateLastUpdated) / 500) * 2);
        }else if((millis() - config.displayStateLastUpdated) / 500 <= 15){
          config.setAnimationSpeed(((millis() - config.displayStateLastUpdated) / 500) * 5);
        }else if((millis() - config.displayStateLastUpdated) / 500 <= 20){
          config.setAnimationSpeed(((millis() - config.displayStateLastUpdated) / 500) * 10);
        }else{
          config.setAnimationSpeed(0xFF);
        }
        buttonState = BS_INITIAL;
        config.displayState = DS_PATTERN;
        config.displayStateLastUpdated = millis();
      }
    }

    // Single press detected after timeout
    if(buttonState == BS_CLICK_UP && millis() - downTime >= 500){
      config.setPatternSlot((config.patternSlot + 1) %5);
      config.displayState = DS_PATTERN;
      config.displayStateLastUpdated = millis();
      buttonState = BS_INITIAL;
    }
    // Double press detected after timeout
    if(buttonState == BS_CLICK_CLICK_UP && millis() - downTime >= 500){
      // Do Nothing
      config.displayState = DS_PATTERN;
      config.displayStateLastUpdated = millis();
      buttonState = BS_INITIAL;
    }
    // Tripple press detected after timeout
    if(buttonState == BS_CLICK_CLICK_CLICK_UP && millis() - downTime >= 500){
      // Do Nothing
      config.displayState = DS_PATTERN;
      config.displayStateLastUpdated = millis();
      buttonState = BS_INITIAL;
    }

    battVoltage = (battVoltage * 0.95) + ((analogReadMilliVolts(A0)/500.0) * .05);
    if(battVoltage > 4){
      config.batteryPercent = 1;
    }else if(battVoltage < 3){
      config.batteryPercent = 0;
    }else{
      config.batteryPercent = battVoltage - 3;
    }
//    debugf("  - batt Voltage = %f\n", battVoltage);

    // do a shutdown if flaged
    if(shutDownAt != 0 && millis() - shutDownAt > 2000){
      // Regulator Shutdown
      digitalWrite(D7, LOW);
      //delay(100);
      
      //hold disable, isolate and power domain config functions may be unnecessary
      //gpio_deep_sleep_hold_dis();
      //esp_sleep_config_gpio_isolate();
      //esp_sleep_pd_config(ESP_PD_DOMAIN_RTC_PERIPH, ESP_PD_OPTION_ON);

      // ESP32 Shutdown sequence
      gpio_set_direction(gpio_num_t(3), GPIO_MODE_INPUT);
      esp_deep_sleep_enable_gpio_wakeup(0b001000, ESP_GPIO_WAKEUP_GPIO_LOW);
      esp_deep_sleep_start();
    }

  }

};

#endif
