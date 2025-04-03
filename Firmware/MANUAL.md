# Open Pixel Poi User Manual


## Quirks & Features
Open pixel poi have a single button menu which gives access to

1. Power on/off
1. 5 pattern slots
1. 5 Brightness levels
1. 10 speeds
1. Auto patten cycle mode
1. Voltage display

Note: a freshly flashed firmware will have no pattens and display
a yellow strobe for all 5 of the pattern slots, untill they are 
filled via the app.

Also Note: The lowest brightness level can only display primary 
colors, this means patterns and color based battery level will 
have very low fidelity. Because the LEDs are powered on at the 
lowest possible level, it is not possible for it to do partial 
brightness to blend colors. The second to lowest level can also
struggle a little.

## Power On/Off
When off, a single button press will turn the poi on.
When on, a single press and hold will turn the poi off.

Note: When turning the poi off, the press andhold will initially
show the blue dot animation, followed by a green/yellow/red battery
level indicator, and finally a blinking red fade out, which is
the shut down animation. You can release the button once the red
blinking animation starts.

## Changing Patterns
A single button press will show the blue dot animation, and then
change to the next pattern. After the last pattern, the poi will
loop back to the first pattern.

## Changing Brightness
A single press, followed by a press and hold will show the white
dot animation, and then ramp up through the brightness levels.
Release the hold at the desired brightness level to select it.

## Changing Speed
A double press, followed by a press and hold will show the red
dot animation, and then ramp up through the speed levels.
Release the hold at the desired speed level to select it.

## Auto pattern cycling
Pressing the button 4 times which will show the magenta dot 
animation and begin automatically cycling through all 5 patterns.

## Battery level monitoring
A single press and hold will show the battery level as a color.
Green is full, red is empty, shades of yellow inbetween.
If you hold too long, it will go into the shutdown sequence.

Pressing the button 4 times which will show the green->red dot 
animation and enter the voltage display mode. In this mode the 
blue leds represent the integer value of the cell voltage, and
remanining leds represent the tenths of a volt fraction. The 
remaining leds are group into 3s for easier counting, and the
color varies from green to red based on the battery level.

## Low battery
When the battery level gets low (below 3.45v) the brightness will
be limited to level 3 max.

When the battery level gets critical (below 3.33v) the poi will
only display 2 red pixels at either end, at the miniumum level.

When the battery level gets even lower (3.25v) the poi will
automatically shut down.