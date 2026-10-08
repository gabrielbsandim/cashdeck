import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Holds a tab's place until its screens are built.
class ComingSoon extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CdEmptyState(
      icon: Symbols.design_services_rounded,
      title: l10n.comingSoonTitle,
      message: l10n.comingSoonMessage,
    );
  }
}
