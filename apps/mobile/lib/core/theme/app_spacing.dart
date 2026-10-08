import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  static const minTouchTarget = 48.0;
  static const double screenGutter = lg;
  static const double cardPadding = lg;
  static const double sectionGap = xl;
  static const listRowMinHeight = 56.0;
  static const transactionRowMinHeight = 64.0;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const sheet = 28.0;
  static const full = 999.0;
}

/// Light themes cast shadows; the dark theme steps up tonal surfaces instead.
abstract final class AppElevation {
  static const level0 = <BoxShadow>[];
  static const level1 = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 3),
  ];
  static const level2 = [
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 4), blurRadius: 12),
  ];
  static const level3 = [
    BoxShadow(color: Color(0x24000000), offset: Offset(0, -2), blurRadius: 24),
  ];

  static List<BoxShadow> shadow(AppPalette palette, int level) {
    if (palette.isDark) return level0;
    return switch (level) {
      1 => level1,
      2 => level2,
      3 => level3,
      _ => level0,
    };
  }

  static Color surface(AppPalette palette, int level) {
    if (!palette.isDark) return palette.surfaceContainerLow;
    return switch (level) {
      2 => palette.surfaceContainer,
      3 => palette.surfaceContainerHigh,
      _ => palette.surfaceContainerLow,
    };
  }
}

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 250);
  static const exitDuration = Duration(milliseconds: 150);

  static const standard = Cubic(0.2, 0, 0, 1);
  static const emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const exit = Cubic(0.3, 0, 1, 1);

  static const springSnappy = SpringDescription(
    mass: 1,
    stiffness: 700,
    damping: 40,
  );
  static const springGentle = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 30,
  );

  /// [duration], or zero when the device asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Duration.zero;
    }
    return duration;
  }
}
