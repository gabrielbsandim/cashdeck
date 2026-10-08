import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A surfaceContainerLow card with an outlineVariant border. [tone] fills it
/// with a status container instead, for a card that is itself a warning.
class CdCard extends StatelessWidget {
  const new({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
    this.onTap,
    this.tone,
    this.selected = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final ToneColors? tone;

  /// A chosen option: primary container and a primary border.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = this.tone;
    final background = switch ((selected, tone)) {
      (true, _) => palette.primaryContainer,
      (false, final ToneColors colors) => colors.background,
      (false, null) => palette.surfaceContainerLow,
    };
    final border = switch ((selected, tone)) {
      (true, _) => BorderSide(color: palette.primary, width: 2),
      (false, ToneColors()) => BorderSide.none,
      (false, null) => BorderSide(color: palette.outlineVariant),
    };
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: border,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
