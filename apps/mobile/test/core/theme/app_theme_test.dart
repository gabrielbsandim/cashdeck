import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_theme.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark come from the same token source', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.extension<AppPalette>(), AppPalette.light);
    expect(dark.extension<AppPalette>(), AppPalette.dark);
    expect(light.extension<AppMoneyColors>(), AppMoneyColors.light);
    expect(dark.extension<AppEntityColors>(), AppEntityColors.dark);
    expect(light.textTheme.bodyMedium?.fontFamily, 'Geist');
  });

  test('every money tone has a distinct foreground and background', () {
    for (final colors in [AppMoneyColors.light, AppMoneyColors.dark]) {
      final foregrounds = {
        for (final tone in MoneyTone.values) colors.tone(tone).foreground,
      };
      for (final tone in MoneyTone.values) {
        expect(
          colors.tone(tone).foreground,
          isNot(colors.tone(tone).background),
        );
      }
      expect(foregrounds.length, greaterThan(MoneyTone.values.length - 2));
    }
  });

  test('every entity has its own tint', () {
    for (final colors in [AppEntityColors.light, AppEntityColors.dark]) {
      final tints = {for (final entity in EntityTone.values) colors.of(entity)};
      expect(tints, hasLength(EntityTone.values.length));
    }
  });

  test('extensions swap whole instead of cross-fading', () {
    const light = AppPalette.light;
    final money = AppMoneyColors.light;
    const entities = AppEntityColors.light;

    expect(light.copyWith(), light);
    expect(light.lerp(null, 1), light);
    expect(light.lerp(AppPalette.dark, 0.2), light);
    expect(light.lerp(AppPalette.dark, 0.8), AppPalette.dark);
    expect(money.copyWith(), money);
    expect(money.lerp(null, 1), money);
    expect(money.lerp(AppMoneyColors.dark, 0.2), money);
    expect(money.lerp(AppMoneyColors.dark, 0.8), AppMoneyColors.dark);
    expect(entities.copyWith(), entities);
    expect(entities.lerp(null, 1), entities);
    expect(entities.lerp(AppEntityColors.dark, 0.2), entities);
    expect(entities.lerp(AppEntityColors.dark, 0.8), AppEntityColors.dark);
    expect(AppPalette.dark.isDark, isTrue);
  });

  test('charts and glows ship per theme and swap whole', () {
    expect(AppTheme.dark().extension<AppChartColors>(), AppChartColors.dark);
    expect(AppTheme.light().extension<AppEntityGlow>(), AppEntityGlow.light);
    expect(AppPalette.dark.surface, const Color(0xFF000000));
    final charts = AppChartColors.light;
    expect(charts.at(7), charts.series[1]);
    expect(charts.copyWith(), charts);
    expect(charts.lerp(null, 1), charts);
    expect(charts.lerp(AppChartColors.dark, 0.8), AppChartColors.dark);
    expect(charts.lerp(AppChartColors.dark, 0.2), charts);
    const glow = AppEntityGlow.dark;
    expect(glow.of(EntityTone.personal), glow.personal);
    expect(glow.of(EntityTone.company), glow.company);
    expect(glow.of(EntityTone.consolidated), glow.consolidated);
    expect(glow.copyWith(), glow);
    expect(glow.lerp(null, 1), glow);
    expect(glow.lerp(AppEntityGlow.light, 0.8), AppEntityGlow.light);
    expect(glow.lerp(AppEntityGlow.light, 0.2), glow);
  });

  test('a bank colour lands on the nearest series slot', () {
    final charts = AppChartColors.dark;
    expect(charts.nearest(const Color(0xFF00A859)), charts.series[1]);
    expect(charts.nearest(const Color(0xFFCC092F)), charts.series[5]);
    expect(charts.nearest(const Color(0xFFFF7A00)), charts.series[2]);
    expect(charts.nearest(const Color(0xFF820AD1)), charts.series[3]);
  });

  test('light casts shadows, dark steps up tonal surfaces', () {
    const light = AppPalette.light;
    const dark = AppPalette.dark;

    expect(AppElevation.shadow(light, 1), AppElevation.level1);
    expect(AppElevation.shadow(light, 2), AppElevation.level2);
    expect(AppElevation.shadow(light, 3), AppElevation.level3);
    expect(AppElevation.shadow(light, 0), AppElevation.level0);
    expect(AppElevation.shadow(dark, 3), AppElevation.level0);
    expect(AppElevation.surface(light, 3), light.surfaceContainerLow);
    expect(AppElevation.surface(dark, 2), dark.surfaceContainer);
    expect(AppElevation.surface(dark, 3), dark.surfaceContainerHigh);
    expect(AppElevation.surface(dark, 1), dark.surfaceContainerLow);
  });

  testWidgets('motion drops to zero when the device asks', (tester) async {
    late Duration normal;
    late Duration reduced;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          normal = AppMotion.of(context, AppMotion.medium);
          return MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                reduced = AppMotion.of(context, AppMotion.medium);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );

    expect(normal, AppMotion.medium);
    expect(reduced, Duration.zero);
  });

  testWidgets('switches follow the selection colors', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Column(
              children: [
                Switch(value: true, onChanged: null),
                Switch(value: false, onChanged: null),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(Switch), findsNWidgets(2));
      final style = theme.switchTheme;
      final palette = theme.extension<AppPalette>()!;
      expect(
        style.thumbColor!.resolve({WidgetState.selected}),
        palette.onPrimary,
      );
      expect(style.thumbColor!.resolve({}), palette.outline);
      expect(
        style.trackColor!.resolve({WidgetState.selected}),
        palette.primary,
      );
      expect(style.trackColor!.resolve({}), palette.surfaceContainerHigh);
      expect(
        style.trackOutlineColor!.resolve({WidgetState.selected}),
        palette.primary,
      );
      expect(style.trackOutlineColor!.resolve({}), palette.outline);
    }
  });
}
