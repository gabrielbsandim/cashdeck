import 'package:cashdeck/core/widgets/states/coming_soon.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).chatTitle)),
      body: const ComingSoon(),
    );
  }
}
