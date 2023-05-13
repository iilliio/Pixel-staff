#ifndef _OPEN_POI_LED
#define _OPEN_POI_LED

#define DEBUG  // Comment this line out to remove printf statements in released version
#ifdef DEBUG
#define debugf(...) Serial.print("<<patterns>> ");Serial.printf(__VA_ARGS__);
#define debugf_noprefix(...) Serial.printf(__VA_ARGS__);
#else
#define debugf(...)
#define debugf_noprefix(...)
#endif

// R = 0xff 0x00 0x00     // Red
// G = 0x00 0xff 0x00     // Green
// B = 0x00 0x00 0xff     // Blue
// b = 0x00 0x00 0x80     // Navy
// F = 0xff 0x00 0xff     // Fuschia
// P = 0x80 0x00 0x80     // Purple
// . = 0x00 0x00 0x00     // Black
// W = 0xFF 0xFF 0xFF     // White
// O = 0xFF 0x8C 0x00     // Orange
// G = 0xC0 0xC0 0xC0     // Light Grey
// g = 0x80 0x80 0x80     // Dark Grey
// C = 0x00 0xFF 0xFF     // Cyan
// t = 0x00 0x80 0x80     // Teal


#endif
