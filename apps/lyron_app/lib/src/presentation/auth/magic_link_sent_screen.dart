import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class MagicLinkSentScreen extends StatelessWidget {
  const MagicLinkSentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.magicLinkSentTitle)),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(AppStrings.magicLinkSentMessage),
      ),
    );
  }
}
