import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light() =>
      _build(AppPalette.light, AppMoneyColors.light, AppEntityColors.light);

  static ThemeData dark() =>
      _build(AppPalette.dark, AppMoneyColors.dark, AppEntityColors.dark);

  static ThemeData _build(
    AppPalette palette,
    AppMoneyColors money,
    AppEntityColors entities,
  ) {
    final colorScheme = ColorScheme(
      brightness: palette.brightness,
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      primaryContainer: palette.primaryContainer,
      onPrimaryContainer: palette.onPrimaryContainer,
      secondary: palette.primary,
      onSecondary: palette.onPrimary,
      secondaryContainer: palette.primaryContainer,
      onSecondaryContainer: palette.onPrimaryContainer,
      error: money.failed,
      onError: palette.surface,
      errorContainer: money.failedContainer,
      onErrorContainer: money.failed,
      surface: palette.surface,
      onSurface: palette.onSurface,
      onSurfaceVariant: palette.onSurfaceVariant,
      surfaceContainerLowest: palette.surfaceContainerLowest,
      surfaceContainerLow: palette.surfaceContainerLow,
      surfaceContainer: palette.surfaceContainer,
      surfaceContainerHigh: palette.surfaceContainerHigh,
      surfaceContainerHighest: palette.surfaceContainerHigh,
      outline: palette.outline,
      outlineVariant: palette.outlineVariant,
      inverseSurface: palette.inverseSurface,
      onInverseSurface: palette.onInverseSurface,
      inversePrimary: palette.primaryContainer,
      surfaceTint: Colors.transparent,
    );
    final textTheme = const TextTheme(
      headlineMedium: AppTextStyles.headlineMd,
      titleLarge: AppTextStyles.titleLg,
      titleMedium: AppTextStyles.titleMd,
      titleSmall: AppTextStyles.titleSm,
      bodyLarge: AppTextStyles.bodyLg,
      bodyMedium: AppTextStyles.bodyMd,
      bodySmall: AppTextStyles.bodyMd,
      labelLarge: AppTextStyles.labelLg,
      labelMedium: AppTextStyles.labelMd,
      labelSmall: AppTextStyles.labelMd,
    ).apply(bodyColor: palette.onSurface, displayColor: palette.onSurface);
    const minimumSize = Size(
      AppSpacing.minTouchTarget,
      AppSpacing.minTouchTarget,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: palette.outline),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      fontFamily: AppTextStyles.fontFamily,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.surface,
      canvasColor: palette.surface,
      extensions: [palette, money, entities],
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppSpacing.lg,
        titleTextStyle: AppTextStyles.titleLg.copyWith(
          color: palette.onSurface,
          fontFamily: AppTextStyles.fontFamily,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: palette.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        disabledBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: palette.outlineVariant),
        ),
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: palette.primary, width: 2),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: money.failed),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: money.failed, width: 2),
        ),
        labelStyle: AppTextStyles.bodyLg.copyWith(
          color: palette.onSurfaceVariant,
        ),
        floatingLabelStyle: AppTextStyles.labelMd.copyWith(
          color: palette.primary,
        ),
        hintStyle: AppTextStyles.bodyLg.copyWith(
          color: palette.onSurfaceVariant,
        ),
        errorStyle: AppTextStyles.bodyMd.copyWith(color: money.failed),
        helperStyle: AppTextStyles.bodyMd.copyWith(
          color: palette.onSurfaceVariant,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: minimumSize,
          foregroundColor: palette.onSurface,
          iconSize: 24,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.onPrimary
              : palette.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.surfaceContainerHigh,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.outline,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.xs),
        ),
        side: BorderSide(color: palette.outline, width: 2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.inverseSurface,
        contentTextStyle: AppTextStyles.bodyMd.copyWith(
          color: palette.onInverseSurface,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: palette.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.surfaceContainerHigh,
      ),
      dividerTheme: DividerThemeData(
        color: palette.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
