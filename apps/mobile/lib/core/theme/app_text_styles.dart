import 'package:flutter/painting.dart';

/// Sizes, weights and tracking only; colors come from the palette. Geist is
/// the theme font, so only [code] names a family.
abstract final class AppTextStyles {
  static const fontFamily = 'Geist';
  static const monoFamily = 'GeistMono';

  static const _tabular = [FontFeature.tabularFigures()];

  static const amountXl = TextStyle(
    fontSize: 40,
    height: 48 / 40,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.8,
    fontFeatures: _tabular,
  );
  static const amountLg = TextStyle(
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    fontFeatures: _tabular,
  );
  static const amountMd = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    fontFeatures: _tabular,
  );
  static const amountSm = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
    fontFeatures: _tabular,
  );

  /// The amount on a list row, sized like [titleSm].
  static const amountRow = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
  );

  static const headlineMd = TextStyle(
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );
  static const titleLg = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const titleMd = TextStyle(
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
  );
  static const titleSm = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
  );
  static const bodyLg = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );
  static const bodyMd = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );
  static const labelLg = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
  static const labelMd = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
  static const code = TextStyle(
    fontFamily: monoFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w500,
    fontFeatures: _tabular,
  );
}
