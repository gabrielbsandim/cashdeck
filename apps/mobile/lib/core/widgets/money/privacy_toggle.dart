import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The eye in the top bar that hides or shows every amount.
class PrivacyToggle extends ConsumerWidget {
  const new({super.key});

  static const buttonKey = Key('privacy-toggle');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hidden = ref.watch(
      displayPreferencesProvider.select((prefs) => prefs.hideAmounts),
    );
    return IconButton(
      key: buttonKey,
      tooltip: hidden ? l10n.showAmounts : l10n.hideAmounts,
      icon: Icon(
        hidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
      ),
      onPressed: () =>
          ref.read(displayPreferencesProvider.notifier).toggleHideAmounts(),
    );
  }
}
