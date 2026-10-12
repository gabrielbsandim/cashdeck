import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home_widget/domain/widget_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('widgetShowsAmounts', () {
    final cases = [
      (privacy: false, zone: false, choice: null, shows: true),
      (privacy: false, zone: true, choice: null, shows: false),
      (privacy: true, zone: false, choice: null, shows: false),
      (privacy: false, zone: true, choice: true, shows: true),
      (privacy: false, zone: false, choice: false, shows: false),
      (privacy: true, zone: false, choice: true, shows: false),
    ];
    for (final each in cases) {
      test('privacy ${each.privacy}, zone ${each.zone}, '
          'choice ${each.choice}: ${each.shows}', () {
        expect(
          widgetShowsAmounts(
            privacyMode: each.privacy,
            hasSafeZone: each.zone,
            choice: each.choice,
          ),
          each.shows,
        );
      });
    }
  });

  test('WidgetSettings applies the same rule and compares by value', () {
    const settings = WidgetSettings(
      hasSafeZone: true,
      choice: true,
      scope: EntityScope.company,
    );

    expect(settings.showsAmounts, isTrue);
    expect(const WidgetSettings().showsAmounts, isTrue);
    expect(const WidgetSettings(privacyMode: true).showsAmounts, isFalse);
    expect(
      settings,
      const WidgetSettings(
        hasSafeZone: true,
        choice: true,
        scope: EntityScope.company,
      ),
    );
  });
}
