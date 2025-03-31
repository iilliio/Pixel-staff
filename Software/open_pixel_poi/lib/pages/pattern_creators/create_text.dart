import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../../database/dbimage.dart';
import '../../hardware/models/rgb_value.dart';
import '../../model.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/connection_state_indicator.dart';


class CreateTextPage extends StatefulWidget {
  const CreateTextPage({super.key});

  @override
  _CreateTextState createState() => _CreateTextState();
}

class _CreateTextState extends State<CreateTextPage> {
  bool flagFirst = true;
  String text = "";
  late RGBValue textColor, backgroundColor;
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    if(flagFirst){
      flagFirst = false;
      var random = Random();
      textColor = RGBValue([random.nextInt(256), random.nextInt(256), random.nextInt(256)]);
      backgroundColor = RGBValue([0,0,0]);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("Solid Color Pattern Creator"),
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
        ListTile(
          title: Text(
          "Text:",
            style: TextStyle(
              fontSize: 24,
              color: Colors.blue,
            ),
          ),
          subtitle: TextField(
            decoration: InputDecoration(border: OutlineInputBorder(), labelText: 'Your text'),
            onChanged: (newValue) => text = newValue,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter(RegExp("[0-9A-Z ]"), allow: true)
            ],
            maxLength: 18,
          ),
        ),
        ColorPicker(
          "Text Color",
          textColor.red.toDouble(),
          textColor.green.toDouble(),
          textColor.blue.toDouble(),
              (RGBValue color) {
                textColor = color;
          },
        ),
        ColorPicker(
          "Background Color",
          backgroundColor.red.toDouble(),
          backgroundColor.green.toDouble(),
          backgroundColor.blue.toDouble(),
              (RGBValue color) {
                backgroundColor = color;
          },
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
                        Navigator.pop(context, true);
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

    int width = (text.length * 18) + 60;
    final fontZipFile = Uint8List.sublistView(await rootBundle.load("fonts/max.zip"));
    final font = img.BitmapFont.fromZip(fontZipFile);
    final image = img.Image(width: width, height: 20);
    img.fill(image, color: img.ColorRgb8(backgroundColor.red, backgroundColor.green, backgroundColor.blue));
    img.drawString(image, text, font: font, x: 0, y: 0, color: img.ColorRgb8(textColor.red, textColor.green, textColor.blue));

    var rgbList = Uint8List((width*20)*3);
    for(var column = 0; column < width; column++) {
      for (var row = 0; row < 20; row++) {
        var columnOffset = column * 20 * 3;
        var rowOffset = row * 3;
        var pixel = image.getPixel(column, row);

        rgbList[columnOffset + rowOffset + 0] = (pixel.r).toInt();
        rgbList[columnOffset + rowOffset + 1] = (pixel.g).toInt();
        rgbList[columnOffset + rowOffset + 2] = (pixel.b).toInt();
      }
    }


    var model = Provider.of<Model>(context, listen: false);
    var pattern = DBImage(
      id: null,
      height: 20,
      count: width,
      bytes: rgbList,
    );
    await model.patternDB.insertImage(pattern);
  }
}