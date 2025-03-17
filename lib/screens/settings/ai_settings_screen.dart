import 'package:flutter/material.dart';

class AiSettingsScreen extends StatelessWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Settings'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // Navigate to the AI settings screen

          },
          child: const Text('AI Settings'),
        ),
      ),
    );
  }
}