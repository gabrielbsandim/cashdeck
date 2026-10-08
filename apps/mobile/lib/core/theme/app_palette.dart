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

  static const dark = AppPalette(
    brightness: Brightness.dark,
    surface: Color(0xFF0D0F15),
    surfaceContainerLowest: Color(0xFF07090D),
    surfaceContainerLow: Color(0xFF14171D),
    surfaceContainer: Color(0xFF1A1E25),
    surfaceContainerHigh: Color(0xFF24282F),
    onSurface: Color(0xFFE9EBEF),
    onSurfaceVariant: Color(0xFFAAAEB6),
    outline: Color(0xFF71757C),
    outlineVariant: Color(0xFF31363D),
    primary: Color(0xFF8BB1F7),
    onPrimary: Color(0xFF07183A),
    primaryContainer: Color(0xFF1D3666),
    onPrimaryContainer: Color(0xFFD3E2FD),
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
