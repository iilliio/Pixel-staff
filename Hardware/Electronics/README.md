# Hardware BOM
This is just the main parts, and does not include all the tools needed. Each single poi will require all these parts

1. Seeed XIAO ESP32C3
    - This is the main controller and BMS
    - [Available VIA Digikey](https://www.digikey.com/short/m92tvzmz)
1. Adafruit MiniBoost 5v TPS61023
    - This converts the battery voltage into 5v for the LEDs and consumes almost no power when disabled
    - [Available VIA Adafruit](https://www.adafruit.com/product/4654?gclid=CjwKCAjwvdajBhBEEiwAeMh1Uznfns69tg1DL2T3nRDSrLh92zifudsJNuze98svYVw0b18dM4SEiRoC5s8QAvD_BwE)
1. WS2812B LEDs 144 leds per meter
    - each poi uses 20 x 3 (60) LEDs, so a single meter, as they are typically sold, is enough for two.
    - Lots of vendors, find your own source
1. 18650 Li-Ion Battery (Flat top)
    - Any battery should do, our draw is only about 1A - 2A, so higher capacity options are viable. Tho you should get great battery life even with a lower capacity cell if you stick to the lower brightness settings, which still hurt my eyes.
1. Stripboard
    - This typically comes in large pieces which i cut down to a 8x4 square for each poi
    - Stripboard is like protoboard/perfboard, but all the pins are joined in horizontal stips.
    - Regular protoboard can work, but you'll have to join all the pins in rows.
    - The wires can also be joined without the board, I just find it easier to join as many as 8 wires using this.
    - Lots of vendors, find your own source
1. Copper Tape or Nickel Stip
    - This is for the battery terminals.
    - Nickle strip intuitively seems like it aught to be better, but copper tape has been holding up fine for me and is easier to work with.
    - 1/4" wide tape with conductive adhesive
    - 8mm x 0.1mm tin stip (Must be soldered to itself to form a loop)
    - Lots of vendors, find your own source
1. Wires
    - Ive been using 26AWG Silicone Stranded wire.
    - This might be a little thin for the main battery leads/5v leads, but I haven't noticed any issued yet. It should be fine for everything else.
    - Lots of vendors, find your own source
1. Resistors
    - 1x 10kohm (To disable the regulator when esp is sleeping)
    - 2x 220kohm (For voltage divider to sample the battery voltage)
