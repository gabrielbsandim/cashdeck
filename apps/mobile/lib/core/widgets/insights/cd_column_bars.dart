import 'dart:math' as math;

import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

final class CdBarColumn {
  const new({required this.label, required this.bars, this.caption});

  /// The month or period under the bars, such as `out`.
  final String label;

  /// A second line under the label, such as `2,2 mil`.
  final String? caption;

  /// One bar per series, side by side.
  final List<(double, Color)> bars;
}

/// Bars per month on one scale; tapping a column selects it and dims the
/// rest. The bars grow from the baseline, left to right.
class CdColumnBars extends StatelessWidget {
  const new({
    required this.columns,
    required this.semanticsLabel,
    this.selected,
    this.onSelect,
    this.height = 140,
    super.key,
  });

  static Key columnKey(int index) => Key('cd-column-$index');

  final List<CdBarColumn> columns;
  final String semanticsLabel;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final top = [
      1.0,
      for (final column in columns)
        for (final (value, _) in column.bars) value,
    ].reduce(math.max);
    final count = columns.length;
    return Semantics(
      label: semanticsLabel,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.of(
          context,
          AppMotion.barGrow + AppMotion.barStagger * count,
        ),
        curve: Curves.easeOutBack,
        builder: (context, progress, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (index, column) in columns.indexed)
              Expanded(
                child: _Column(
                  key: columnKey(index),
                  column: column,
                  top: top,
                  height: height,
                  growth: ((progress * count - index * 0.5) / (count * 0.5))
                      .clamp(0.0, 1.0),
                  dimmed: selected != null && selected != index,
                  selected: selected == index,
                  onTap: onSelect == null ? null : () => onSelect!(index),
                  palette: palette,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const new({
    required this.column,
    required this.top,
    required this.height,
    required this.growth,
    required this.dimmed,
    required this.selected,
    required this.onTap,
    required this.palette,
    super.key,
  });

  final CdBarColumn column;
  final double top;
  final double height;
  final double growth;
  final bool dimmed;
  final bool selected;
  final VoidCallback? onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final caption = column.caption;
    final labelStyle = AppTextStyles.bodyMd.copyWith(
      fontSize: 12,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? palette.onSurface : palette.onSurfaceVariant,
    );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: column.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: selected && onTap != null ? palette.surfaceContainer : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (index, (value, color))
                        in column.bars.indexed) ...[
                      if (index > 0) const SizedBox(width: 3),
                      Flexible(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 16),
                          height: math.max(
                            value <= 0 ? 0 : 2,
                            value / top * height * growth,
                          ),
                          decoration: BoxDecoration(
                            color: dimmed
                                ? color.withValues(alpha: 0.4)
                                : color,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(column.label, maxLines: 1, style: labelStyle),
              ),
              if (caption != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    caption,
                    maxLines: 1,
                    style: labelStyle.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
