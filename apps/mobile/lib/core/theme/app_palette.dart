import 'package:flutter/material.dart';

/// The Material 3 surface, text and accent roles of the Cashdeck token sheet.
/// Screens read colors only through [PaletteContext].
@immutable
final class AppPalette extends ThemeExtension<AppPalette> {
  const new({
    required this.brightness,
    required this.surface,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.inverseSurface,
    required this.onInverseSurface,
  });

  static const light = AppPalette(
    brightness: Brightness.light,
    surface: Color(0xFFF9FAFD),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF3F5F9),
    surfaceContainer: Color(0xFFEEF0F4),
    surfaceContainerHigh: Color(0xFFE5E8ED),
    onSurface: Color(0xFF171B22),
    onSurfaceVariant: Color(0xFF535861),
    outline: Color(0xFF888C94),
    outlineVariant: Color(0xFFDBDEE3),
    primary: Color(0xFF3263C3),
    onPrimary: Color(0xFFFBFCFE),
    primaryContainer: Color(0xFFDAE9FF),
    onPrimaryContainer: Color(0xFF0C2D6F),
    inverseSurface: Color(0xFF252930),
    onInverseSurface: Color(0xFFF0F2F4),
  );

  // OLED: layered near-blacks give depth without shadows.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    surface: Color(0xFF000000),
    surfaceContainerLowest: Color(0xFF040506),
    surfaceContainerLow: Color(0xFF0C0E12),
    surfaceContainer: Color(0xFF15171C),
    surfaceContainerHigh: Color(0xFF1E2228),
    onSurface: Color(0xFFEDEEF1),
    onSurfaceVariant: Color(0xFFA7ABB1),
    outline: Color(0xFF6E7279),
    outlineVariant: Color(0xFF24272B),
    primary: Color(0xFF68A1FF),
    onPrimary: Color(0xFF020D29),
    primaryContainer: Color(0xFF072869),
    onPrimaryContainer: Color(0xFFD6E5FF),
    inverseSurface: Color(0xFFE2E5E9),
    onInverseSurface: Color(0xFF171B22),
  );

  final Brightness brightness;
  final Color surface;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color inverseSurface;
  final Color onInverseSurface;

  bool get isDark => brightness == Brightness.dark;

  @override
  AppPalette copyWith() => this;

  // Light and dark swap whole; a cross-fade between palettes adds nothing.
  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
