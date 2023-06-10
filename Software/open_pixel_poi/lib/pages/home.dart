import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:open_pixel_poi/hardware/models/led_pattern.dart';
import 'package:open_pixel_poi/hardware/models/rgb_value.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tuple/tuple.dart';

import '../database/dbimage.dart';
import '../hardware/models/comm_code.dart';
import '../model.dart';
import '../widgets/connection_state_indicator.dart';
import '../widgets/pattern_import_button.dart';
import '../widgets/remixer_slider.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Open Pixel Poi"),
        actions: [
          PatternImportButton(() {
            setState(() {});
          }),
          ...Provider.of<Model>(context)
              .connectedPoi!
              .map((e) => ConnectionStateIndicator(Provider.of<Model>(context).connectedPoi!.indexOf(e)))
        ],
      ),
      body: getButtons(context),
    );
  }

  Widget getButtons(BuildContext buildContext) {
    return Container(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            getPrimarySettings(buildContext),
            getImagesList(buildContext),
          ],
        ),
      ),
    );
  }

  Widget getPrimarySettings(BuildContext buildContext) {
    return Card(
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListTile(
          title: const Text('Primary Settings',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              )),
          subtitle: Column(
            children: [
              RemixerSlider(
                "Brightness: ${Provider.of<Model>(context, listen: false).hardwareState.settings!.brightness}%",
                CommCode.CC_SET_BRIGHTNESS,
                () => Provider.of<Model>(context, listen: false).hardwareState.settings!.brightness,
                (int newValue) {
                  setState(() {
                    Provider.of<Model>(context, listen: false).hardwareState.settings!.brightness = newValue;
                  });
                },
                // minValue: 1,
                // maxValue: 100,
                scaler: 1,
              ),
              const Divider(
                height: 1,
                thickness: 1,
                indent: 0,
                endIndent: 0,
              ),
              RemixerSlider(
                "Speed: ${Provider.of<Model>(context, listen: false).hardwareState.settings!.speed * 2}hz",
                CommCode.CC_SET_SPEED,
                () => Provider.of<Model>(context, listen: false).hardwareState.settings!.speed,
                (int newValue) {
                  setState(() {
                    Provider.of<Model>(context, listen: false).hardwareState.settings!.speed = newValue;
                  });
                },
                minValue: 1,
                maxValue: 255,
                scaler: 1,
                suffixGenerator: (value) => "${value.toInt() * 2}hz",
              ),
              const Divider(
                height: 1,
                thickness: 1,
                indent: 0,
                endIndent: 0,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ListTile(
                  title: const Text("Pattern Slots", style: TextStyle(color: Colors.blue)),
                  subtitle: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton(
                            child: const Text("1", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            onPressed: () => Provider.of<Model>(context, listen: false).connectedPoi!.forEach((poi) => poi.sendInt8(0, CommCode.CC_SET_PATTERN_SLOT)),
                          ),
                          const VerticalDivider(width: 8.0),
                          ElevatedButton(
                            child: const Text("2", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            onPressed: () => Provider.of<Model>(context, listen: false).connectedPoi!.forEach((poi) => poi.sendInt8(1, CommCode.CC_SET_PATTERN_SLOT)),
                          ),
                          const VerticalDivider(width: 8.0),
                          ElevatedButton(
                            child: const Text("3", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            onPressed: () => Provider.of<Model>(context, listen: false).connectedPoi!.forEach((poi) => poi.sendInt8(2, CommCode.CC_SET_PATTERN_SLOT)),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            child: const Text("4", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            onPressed: () => Provider.of<Model>(context, listen: false).connectedPoi!.forEach((poi) => poi.sendInt8(3, CommCode.CC_SET_PATTERN_SLOT)),
                          ),
                          const VerticalDivider(width: 8.0),
                          ElevatedButton(
                            child: const Text("5", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            onPressed: () => Provider.of<Model>(context, listen: false).connectedPoi!.forEach((poi) => poi.sendInt8(4, CommCode.CC_SET_PATTERN_SLOT)),
                          ),
                        ],
                      ),

                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget getImagesList(BuildContext buildContext) {
    return Card(
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListTile(
          title: const Text(
            'Patterns',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: FutureBuilder<List<Tuple2<Widget, DBImage>>>(
            future: Provider.of<Model>(context).getImages(context),
            builder: (BuildContext context, AsyncSnapshot<List<Tuple2<Widget, DBImage>>> snapshot) {
              List<Widget> children;
              if (snapshot.hasData) {
                List<Tuple2<Widget, DBImage>>? tuples = snapshot.data;
                tuples ??= List.empty();
                List<Widget> widgets = List.empty(growable: true);
                for (var tuple in tuples) {
                  widgets.add(
                    InkWell(
                      onTap: () {
                        for (var poi in Provider.of<Model>(context, listen: false).connectedPoi!) {
                          poi.sendPattern2(tuple.item2);
                        }
                      },
                      onLongPress: () => showDialog<void>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                          title: const Text("Edit/Delete Pattern"),
                          content: const Text('Pretty self explanatory really -_-'),
                          actionsPadding: const EdgeInsets.all(0.0),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.pop(context, 'Cancel'),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context, 'Flip');
                                Provider.of<Model>(context, listen: false).invertImage(tuple.item2.id!).then((value) => setState(() {}));
                              },
                              child: const Text('Flip'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context, 'Mirror');
                                Provider.of<Model>(context, listen: false).reverseImage(tuple.item2.id!).then((value) => setState(() {}));
                              },
                              child: const Text('Mirror'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context, 'Delete');
                                Provider.of<Model>(context, listen: false).deleteImage(tuple.item2.id!).then((value) => setState(() {}));
                              },
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 80,
                              child: tuple.item1,
                            ),
                            const SizedBox(
                              width: 100,
                              height: 8,
                            ),
                            const Divider(
                              height: 1,
                              thickness: 1,
                              indent: 0,
                              endIndent: 0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                children = widgets;
              } else if (snapshot.hasError) {
                children = <Widget>[
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 60,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text('Error Loading Patterns: ${snapshot.error}'),
                  ),
                ];
              } else {
                children = const <Widget>[
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('Loading patterns...'),
                  ),
                ];
              }
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: children,
                ),
              );

              // return imagesList(buildContext, images);
            },
          ),
        ),
      ),
    );
  }
}
