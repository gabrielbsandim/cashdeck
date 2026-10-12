import 'package:cashdeck/features/home_widget/data/platform_home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  const snapshot = WidgetSnapshot({
    WidgetKeys.hidden: false,
    WidgetKeys.safeAmount: r'R$ 85,00',
  });

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  void answer(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  group('PlatformHomeWidgetPublisher', () {
    const publisher = PlatformHomeWidgetPublisher();

    test('saves each value, then redraws the widget', () async {
      answer((_) => true);

      await publisher.publish(snapshot);

      expect(calls.map((call) => call.method), [
        'saveWidgetData',
        'saveWidgetData',
        'updateWidget',
      ]);
      expect(calls[0].arguments, {'id': WidgetKeys.hidden, 'data': false});
      expect(calls[1].arguments, {
        'id': WidgetKeys.safeAmount,
        'data': r'R$ 85,00',
      });
      expect(
        (calls[2].arguments as Map)['qualifiedAndroidName'],
        PlatformHomeWidgetPublisher.provider,
      );
    });

    test('removes every key on clear', () async {
      answer((_) => true);

      await publisher.clear();

      final saved = calls.where((call) => call.method == 'saveWidgetData');
      expect(
        saved.map((call) => (call.arguments as Map)['id']),
        WidgetKeys.all,
      );
      expect(
        saved.every((call) => (call.arguments as Map)['data'] == null),
        isTrue,
      );
      expect(calls.last.method, 'updateWidget');
    });

    test('registers the background refresh it was given', () async {
      answer((_) => true);

      await const PlatformHomeWidgetPublisher(_background)
          .enableBackgroundRefresh();
      await publisher.enableBackgroundRefresh();

      expect(calls.map((call) => call.method), ['registerBackgroundCallback']);
      expect(calls.single.arguments, hasLength(2));
    });

    test('swallows a platform failure', () async {
      answer((_) => throw PlatformException(code: 'boom'));

      await expectLater(publisher.publish(snapshot), completes);
      await expectLater(publisher.clear(), completes);
      await expectLater(
        const PlatformHomeWidgetPublisher(_background)
            .enableBackgroundRefresh(),
        completes,
      );
    });

    test('swallows a missing plugin', () async {
      await expectLater(publisher.publish(snapshot), completes);
      await expectLater(publisher.clear(), completes);
    });
  });

  test('NoHomeWidgetPublisher never reaches the platform', () async {
    answer((_) => true);
    const publisher = NoHomeWidgetPublisher();

    await publisher.publish(snapshot);
    await publisher.clear();
    await publisher.enableBackgroundRefresh();

    expect(calls, isEmpty);
  });
}

Future<void> _background(Uri? uri) async {}
