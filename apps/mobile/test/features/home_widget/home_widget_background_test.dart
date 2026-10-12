import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/bills/data/api_bills_repository.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/home_widget/application/refresh_home_widget.dart';
import 'package:cashdeck/features/home_widget/domain/widget_settings.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:cashdeck/features/home_widget/home_widget_background.dart';
import 'package:cashdeck/features/insights/data/api_insights_repository.dart';
import 'package:cashdeck/features/outlook/data/api_outlook_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/builders.dart';
import 'home_widget_support.dart';

const _api = AppConfig(
  backend: Backend.api,
  apiBaseUrl: 'https://cashdeck.example.test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clock = FixedClock(testNow);

  test('the API sources share one client that closes with them', () {
    final sources = widgetSourcesFor(_api, ServerCredentials.demo, clock);

    expect(sources.outlook, isA<ApiOutlookRepository>());
    expect(sources.bills, isA<ApiBillsRepository>());
    expect(sources.insights, isA<ApiInsightsRepository>());
    expect(sources.close, returnsNormally);
  });

  test('the fake backend refreshes from the demo data', () async {
    final publisher = FakeHomeWidgetPublisher();
    const fake = AppConfig(backend: Backend.fake, apiBaseUrl: '');

    expect(
      widgetSourcesFor(fake, ServerCredentials.demo, clock).bills,
      isA<FakeBillsRepository>(),
    );
    final outcome = await backgroundRefreshFor(
      fake,
      publisher: publisher,
      clock: clock,
    )(const WidgetSettings());

    expect(outcome, WidgetRefresh.refreshed);
    expect(publisher.last!.values[WidgetKeys.updatedTime], '12:00');
  });

  test('the API backend reads the session from secure storage', () async {
    const storage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(storage, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(storage, null));
    final publisher = FakeHomeWidgetPublisher();

    final outcome = await backgroundRefreshFor(
      _api,
      publisher: publisher,
      clock: clock,
    )(const WidgetSettings());

    expect(outcome, WidgetRefresh.signedOut);
    expect(publisher.cleared, 1);
  });

  group('refreshHomeWidgetInBackground', () {
    const channel = MethodChannel('home_widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    setUp(() {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
    });

    tearDown(() {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('ignores any other link', () async {
      SharedPreferences.setMockInitialValues({});

      await refreshHomeWidgetInBackground(Uri.parse('cashdeck://widget/bills'));
      await refreshHomeWidgetInBackground(null);

      expect(calls, isEmpty);
    });

    test('masks the widget without fetching when amounts are off', () async {
      SharedPreferences.setMockInitialValues({'hide_amounts': true});

      await refreshHomeWidgetInBackground(homeWidgetRefreshUri);

      expect(calls.map((call) => call.method), [
        'saveWidgetData',
        'updateWidget',
      ]);
      expect(calls.first.arguments, {'id': WidgetKeys.hidden, 'data': true});
    });
  });
}
