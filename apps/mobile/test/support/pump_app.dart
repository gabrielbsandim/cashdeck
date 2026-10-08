import 'package:cashdeck/core/theme/app_theme.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations l10n = lookupAppLocalizations(const Locale('pt'));

extension PumpApp on WidgetTester {
  /// A 400 by 2000 phone, so long screens build without scrolling.
  void useTallScreen() {
    view
      ..physicalSize = const Size(1200, 6000)
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
  }

  Future<void> pumpApp(
    Widget child, {
    List<Override> overrides = const [],
    bool dark = false,
  }) {
    useTallScreen();
    return pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          locale: const Locale('pt'),
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: child),
        ),
      ),
    );
  }
}
