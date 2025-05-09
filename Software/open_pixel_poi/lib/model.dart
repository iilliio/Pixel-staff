import 'package:open_pixel_poi/hardware/poi_hardware_state.dart';
import 'package:open_pixel_poi/patterndb.dart';
import 'hardware/poi_hardware.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Model extends ChangeNotifier {
  List<PoiHardware>? connectedPoi;
  PoiHardwareState hardwareState = PoiHardwareState();
  PatternDB patternDB = PatternDB();

  int _maxPatternHeight = 80;

  int get maxPatternHeight => _maxPatternHeight;

  void setMaxPatternHeight(int value) {
    _maxPatternHeight = value;
    notifyListeners();
  }
}
