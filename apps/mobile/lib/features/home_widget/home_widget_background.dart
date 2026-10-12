import 'dart:ui';

import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/network/dio_factory.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/core/session/credential_store.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/bills/data/api_bills_repository.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/home_widget/application/refresh_home_widget.dart';
import 'package:cashdeck/features/home_widget/data/platform_home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/domain/home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/domain/widget_sources.dart';
import 'package:cashdeck/features/home_widget/presentation/widget_values_controller.dart';
import 'package:cashdeck/features/insights/data/api_insights_repository.dart';
import 'package:cashdeck/features/insights/data/fake_insights_repository.dart';
import 'package:cashdeck/features/outlook/data/api_outlook_repository.dart';
import 'package:cashdeck/features/outlook/data/fake_outlook_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What `WidgetRefreshWorker.kt` sends every few hours, on boot and when the
/// widget is added.
final Uri homeWidgetRefreshUri = Uri.parse('cashdeck://widget/refresh');

/// The background refresh wired for [config]: the session in secure storage
/// and the API, or the demo session and the fake repositories.
RefreshHomeWidget backgroundRefreshFor(
  AppConfig config, {
  HomeWidgetPublisher publisher = const PlatformHomeWidgetPublisher(),
  Clock clock = const SystemClock(),
}) => RefreshHomeWidget(
  credentials: switch (config.backend) {
    Backend.fake => InMemoryCredentialStore(ServerCredentials.demo),
    Backend.api => const SecureCredentialStore(),
  },
  open: (session) => widgetSourcesFor(config, session, clock),
  publisher: publisher,
  clock: clock,
);

/// A fresh client per refresh, so the token lives only as long as it.
WidgetSources widgetSourcesFor(
  AppConfig config,
  ServerCredentials session,
  Clock clock,
) {
  switch (config.backend) {
    case Backend.fake:
      return WidgetSources(
        outlook: FakeOutlookRepository(clock),
        bills: FakeBillsRepository(clock),
        insights: FakeInsightsRepository(clock),
      );
    case Backend.api:
      final dio = createApiDio(config, session: session);
      return WidgetSources(
        outlook: ApiOutlookRepository(dio),
        bills: ApiBillsRepository(dio),
        insights: ApiInsightsRepository(dio),
        close: dio.close,
      );
  }
}

/// Runs in the isolate the `home_widget` worker starts while the app may be
/// closed, so it builds what it needs instead of reading providers.
@pragma('vm:entry-point')
Future<void> refreshHomeWidgetInBackground(Uri? uri) async {
  if (uri != homeWidgetRefreshUri) return;
  DartPluginRegistrant.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  // The worker keeps its isolate between runs; the app may have changed them.
  await preferences.reload();
  await backgroundRefreshFor(AppConfig.fromEnvironment())(
    savedWidgetSettings(SharedPreferencesStore(preferences)),
  );
}
