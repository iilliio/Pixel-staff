import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/dbimage.dart';
import '../../hardware/models/rgb_value.dart';
import '../../model.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/connection_state_indicator.dart';


class CreateFadePage extends StatefulWidget {
  const CreateFadePage({super.key});

  @override
  _CreateFadeState createState() => _CreateFadeState();
}

class _CreateFadeState extends State<CreateFadePage> {
  bool flagFirst = true;
  late int fadeSize = 10;
  late RGBValue colorOne;
  late RGBValue colorTwo;
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    if(flagFirst){
      flagFirst = false;
      var random = Random();
      colorOne = RGBValue([random.nextInt(2) * 255, random.nextInt(2) * 255, random.nextInt(2) * 255]);
      colorTwo = RGBValue([random.nextInt(2) * 255, random.nextInt(2) * 255, random.nextInt(2) * 255]);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("Grid Pattern Creator"),
        actions: [
          ...Provider.of<Model>(context)
              .connectedPoi!
              .map((e) => ConnectionStateIndicator(Provider.of<Model>(context).connectedPoi!.indexOf(e)))
        ],
      ),
      body: saving ? getSaving() : getForm(),
    );
  }

  Widget getForm() {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: ListTile(
            title: Text(
              "Fade width: $fadeSize",
              style: TextStyle(
                color: Colors.blue,
              ),
            ),
            subtitle: Slider(
              value: fadeSize.toDouble(),
              max: 400,
              min: 10,
              divisions: 195,
              label: "$fadeSize",
              onChanged: (double value) {
                setState(() {
                  fadeSize = value.toInt();
                });
              },
              onChangeEnd: (double value) {
                fadeSize = value.toInt();
              },
            ),
          ),
        ),
        ColorPicker(
          "Start Color",
          colorOne.red.toDouble(),
          colorOne.green.toDouble(),
          colorOne.blue.toDouble(),
              (RGBValue color) => colorOne = color,
        ),
        ColorPicker(
          "End Color",
          colorTwo.red.toDouble(),
          colorTwo.green.toDouble(),
          colorTwo.blue.toDouble(),
              (RGBValue color) => colorTwo = color,
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            width: double.infinity,
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 8.0),
                Expanded(
                  child: ElevatedButton(
                    child: const Text(
                      "Save",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () async {
                      saving = true;
                      await makeAndStorePattern(context);
                      if(context.mounted) { // Do we actually want this check?
                        Navigator.pop(context);
                      }
                      saving = false;
                    },
                  ),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget getSaving() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              "Saving...",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(
              height: 30,
            ),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Future<void> makeAndStorePattern(BuildContext context) async{
    var rgbList = Uint8List(fadeSize * 3);
    var rgbOffset = 0;
    var percent = 0.0;
    for(int column = 0; column < fadeSize/2; column++){
      percent = column / (fadeSize/2);
      rgbOffset = column * 3;
      rgbList[rgbOffset] = ((colorOne.red * percent) + (colorTwo.red * (1 - percent))).toInt();
      rgbList[rgbOffset + 1] = ((colorOne.green * percent) + (colorTwo.green * (1 - percent))).toInt();
      rgbList[rgbOffset + 2] = ((colorOne.blue * percent) + (colorTwo.blue * (1 - percent))).toInt();
    }

    var rgbHalfway = (fadeSize/2).toInt() * 3;
    for(int column = (fadeSize/2).toInt(); column < fadeSize; column++){
      rgbOffset = column * 3;
      rgbList[rgbOffset] = rgbList[(rgbHalfway - (rgbOffset - rgbHalfway)) - 3];
      rgbList[rgbOffset + 1] = rgbList[(rgbHalfway - (rgbOffset - rgbHalfway)) - 2];
      rgbList[rgbOffset + 2] = rgbList[(rgbHalfway - (rgbOffset - rgbHalfway)) - 1];
    }
    var pattern = DBImage(
      id: null,
      height: 1,
      count: fadeSize,
      bytes: rgbList,
    );

    var model = Provider.of<Model>(context, listen: false);
    await model.patternDB.insertImage(pattern);
  }
}