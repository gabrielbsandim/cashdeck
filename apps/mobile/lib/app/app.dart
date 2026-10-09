import 'dart:async';

import 'package:cashdeck/app/router/app_router.dart';
import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/security/app_lock.dart';
import 'package:cashdeck/core/share/share_intake.dart';
import 'package:cashdeck/core/theme/app_theme.dart';
import 'package:cashdeck/features/alerts/presentation/push_listener.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CashdeckApp extends ConsumerStatefulWidget {
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
  ConsumerState<CashdeckApp> createState() => _CashdeckAppState();
}

class _CashdeckAppState extends ConsumerState<CashdeckApp> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<LocalFile>? _shared;

  @override
  void initState() {
    super.initState();
    final lock = ref.read(appLockProvider.notifier);
    _lifecycle = AppLifecycleListener(onHide: lock.hidden, onShow: lock.shown);
    _shared = ref
        .read(shareIntakeProvider)
        .files()
        .listen(
          (file) => ref
              .read(appRouterProvider)
              .push(AppRoutes.sharedFile, extra: file)
              .ignore(),
        );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _shared?.cancel().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(
      displayPreferencesProvider.select((prefs) => prefs.themeMode),
    );
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      localeResolutionCallback: CashdeckApp.resolveLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(appRouterProvider),
      builder: (_, child) => PushListener(
        onOpen: (location) => ref.read(appRouterProvider).go(location),
        child: child ?? const SizedBox.shrink(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
