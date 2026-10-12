import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:cashdeck/features/home_widget/home_widget_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/safe_mode_support.dart';
import '../home_widget_support.dart';

const _masked = 'R\$\u00A0${MoneyFormat.hidden}';

void main() {
  testWidgets('Início feeds the widget, masks it on privacy and clears it '
      'on sign-out', (tester) async {
    final publisher = FakeHomeWidgetPublisher();
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [homeWidgetPublisherProvider.overrideWithValue(publisher)],
    );

    final shown = publisher.last!.values;
    expect(shown[WidgetKeys.hidden], isFalse);
    expect(shown[WidgetKeys.updatedTime], '12:00');
    expect(shown[WidgetKeys.safeAmount], isA<String>());
    expect(shown[WidgetKeys.safeAmount], isNot(_masked));
    expect(shown[WidgetKeys.billPayee], isNotEmpty);
    expect(shown.keys, contains(WidgetKeys.cardAmount));

    app.read(displayPreferencesProvider.notifier).toggleHideAmounts();
    await settle(tester);
    final masked = publisher.last!.values;
    expect(masked[WidgetKeys.hidden], isTrue);
    expect(masked[WidgetKeys.safeAmount], _masked);
    expect(masked[WidgetKeys.billAmount], _masked);

    expect(publisher.cleared, 0);
    final published = publisher.published.length;
    await app.read(serverSessionProvider.notifier).signOut();
    await settle(tester);
    expect(publisher.cleared, 1);
    expect(publisher.published, hasLength(published));
  });

  testWidgets('a saved safe zone masks the widget even inside it', (
    tester,
  ) async {
    final publisher = FakeHomeWidgetPublisher();
    await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        ...safeModeOverrides(at: homePoint),
        homeWidgetPublisherProvider.overrideWithValue(publisher),
      ],
    );

    expect(publisher.last!.values[WidgetKeys.hidden], isTrue);
    expect(publisher.last!.values[WidgetKeys.safeAmount], _masked);
  });
}
