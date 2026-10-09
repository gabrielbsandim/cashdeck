import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:flutter/material.dart';

/// One chart series: the fill for marks, the text tint for labels and
/// monograms, and the container behind a monogram.
@immutable
final class SeriesColors {
  const new({
    required this.fill,
    required this.foreground,
    required this.container,
  });

  final Color fill;
  final Color foreground;
  final Color container;
}

/// Series slots for institutions and categories, plus the chart guides.
@immutable
final class AppChartColors extends ThemeExtension<AppChartColors> {
  const new({
    required this.series,
    required this.grid,
    required this.previous,
    required this.today,
    required this.card,
    required this.cardBorder,
  });

  static final light = AppChartColors(
    series: const [
      SeriesColors(
        fill: Color(0xFF4C7DD9),
        foreground: Color(0xFF305EB7),
        container: Color(0xFFDDEEFF),
      ),
      SeriesColors(
        fill: Color(0xFF00978A),
        foreground: Color(0xFF00786C),
        container: Color(0xFFCCF7F1),
      ),
      SeriesColors(
        fill: Color(0xFFB46E00),
        foreground: Color(0xFF945000),
        container: Color(0xFFFFE8CD),
      ),
      SeriesColors(
        fill: Color(0xFF9565C7),
        foreground: Color(0xFF7847A6),
        container: Color(0xFFF4E6FF),
      ),
      SeriesColors(
        fill: Color(0xFF008FBA),
        foreground: Color(0xFF00709A),
        container: Color(0xFFCEF4FF),
      ),
      SeriesColors(
        fill: Color(0xFFCA545A),
        foreground: Color(0xFFA8353E),
        container: Color(0xFFFFE2E0),
      ),
    ],
    grid: AppPalette.light.outlineVariant,
    previous: AppPalette.light.outline,
    today: AppPalette.light.onSurface.withValues(alpha: 0.5),
    card: AppPalette.light.surfaceContainerLowest,
    cardBorder: AppPalette.light.outlineVariant,
  );

  static final dark = AppChartColors(
    series: const [
      SeriesColors(
        fill: Color(0xFF6FA2FF),
        foreground: Color(0xFF93BEFF),
        container: Color(0xFF202E47),
      ),
      SeriesColors(
        fill: Color(0xFF26BDAE),
        foreground: Color(0xFF6ED2C6),
        container: Color(0xFF053631),
      ),
      SeriesColors(
        fill: Color(0xFFDC932E),
        foreground: Color(0xFFECB16A),
        container: Color(0xFF3E290F),
      ),
      SeriesColors(
        fill: Color(0xFFBB8AEF),
        foreground: Color(0xFFD0AAFC),
        container: Color(0xFF342742),
      ),
      SeriesColors(
        fill: Color(0xFF22B5E1),
        foreground: Color(0xFF6CCCF0),
        container: Color(0xFF0A3341),
      ),
      SeriesColors(
        fill: Color(0xFFF47A7D),
        foreground: Color(0xFFFF9D9E),
        container: Color(0xFF442323),
      ),
    ],
    grid: AppPalette.dark.outlineVariant,
    previous: AppPalette.dark.outline,
    today: AppPalette.dark.onSurface.withValues(alpha: 0.5),
    card: AppPalette.dark.surfaceContainerLow,
    cardBorder: const Color(0xFF16181D),
  );

  final List<SeriesColors> series;
  final Color grid;
  final Color previous;
  final Color today;
  final Color card;
  final Color cardBorder;

  /// The slot of the [index]th series, wrapping past the last one.
  SeriesColors at(int index) => series[index % series.length];

  /// The slot whose fill hue is nearest to [color], so a bank's own colour
  /// lands on a harmonious, legible tint.
  SeriesColors nearest(Color color) {
    final hue = HSLColor.fromColor(color).hue;
    double distance(SeriesColors slot) {
      final gap = (HSLColor.fromColor(slot.fill).hue - hue).abs();
      return gap > 180 ? 360 - gap : gap;
    }

    return series.reduce((a, b) => distance(b) < distance(a) ? b : a);
  }

  @override
  AppChartColors copyWith() => this;

  @override
  AppChartColors lerp(AppChartColors? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

/// The two radial glows behind the home header, per entity.
@immutable
final class AppEntityGlow extends ThemeExtension<AppEntityGlow> {
  const new({
    required this.personal,
    required this.company,
    required this.consolidated,
  });

  static const light = AppEntityGlow(
    personal: (Color(0xB39BBEFF), Color(0x99D1C4FD)),
    company: (Color(0xB390DFD4), Color(0x99B6E4CA)),
    consolidated: (Color(0xA6A4C5FF), Color(0xA69CE1D7)),
  );

  static const dark = AppEntityGlow(
    personal: (Color(0xB31957D2), Color(0x806034AC)),
    company: (Color(0xA6007E72), Color(0x7300683D)),
    consolidated: (Color(0x99235BC8), Color(0x8C007E72)),
  );

  final (Color, Color) personal;
  final (Color, Color) company;
  final (Color, Color) consolidated;

  (Color, Color) of(EntityTone entity) => switch (entity) {
    EntityTone.personal => personal,
    EntityTone.company => company,
    EntityTone.consolidated => consolidated,
  };

  @override
  AppEntityGlow copyWith() => this;

  @override
  AppEntityGlow lerp(AppEntityGlow? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

extension ChartColorsContext on BuildContext {
  AppChartColors get charts => Theme.of(this).extension<AppChartColors>()!;

  AppEntityGlow get glow => Theme.of(this).extension<AppEntityGlow>()!;
}
