import 'package:cashdeck/app/router/app_router.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_theme.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CashdeckApp extends ConsumerWidget {
  const new({super.key});

  static const fallbackLocale = Locale('pt');

  /// The device language when the app speaks it, Portuguese otherwise.
  static Locale resolveLocale(Locale? device, Iterable<Locale> supported) {
    final match = supported
        .where((locale) => locale.languageCode == device?.languageCode)
        .firstOrNull;
    return match ?? fallbackLocale;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      displayPreferencesProvider.select((prefs) => prefs.themeMode),
    );
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      localeResolutionCallback: resolveLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
