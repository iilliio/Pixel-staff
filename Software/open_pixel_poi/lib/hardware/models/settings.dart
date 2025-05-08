import 'dart:ui';

import '../parse_util.dart';

class Settings {
  int brightness = 0;
  int speed = 0;
  int maxPatternHeight = 20;
  Settings(List<int> data){
    brightness = ParseUtil.takeInt8(data);
    speed = ParseUtil.takeInt8(data);
    maxPatternHeight = ParseUtil.takeInt8(data);
  }

}
