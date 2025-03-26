import 'package:flutter/material.dart';
import 'package:open_pixel_poi/pages/pattern_creators/create_check.dart';
import 'package:open_pixel_poi/pages/pattern_creators/create_fade.dart';
import 'package:provider/provider.dart';

import '../model.dart';
import '../widgets/connection_state_indicator.dart';
import 'pattern_creators/create_solid_color.dart';


class CreatePage extends StatefulWidget {
  const CreatePage({super.key});

  @override
  _CreateState createState() => _CreateState();
}

class _CreateState extends State<CreatePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Custom Pattern"),
        actions: [
          ...Provider.of<Model>(context)
              .connectedPoi!
              .map((e) => ConnectionStateIndicator(Provider.of<Model>(context).connectedPoi!.indexOf(e)))
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                child: const Text("Solid Color", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) {
                    return CreateSolidColorPage();
                  }),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                child: const Text("Check", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) {
                    return CreateCheckPage();
                  }),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                child: const Text("Fade", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) {
                    return CreateFadePage();
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}