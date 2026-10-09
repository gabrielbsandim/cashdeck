import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

final class CdBarSegment {
  const new(this.value, this.color);

  /// Any non-negative weight; the bar splits by share of the total.
  final double value;
  final Color color;
}

/// A stacked bar, one segment per institution or category, with a 3dp gap.
/// It fills segment by segment, biggest first, unless motion is reduced.
class CdSegmentBar extends StatelessWidget {
  const new({
    required this.segments,
    required this.semanticsLabel,
    this.height = 10,
    super.key,
  });

  final List<CdBarSegment> segments;
  final String semanticsLabel;
  final double height;

  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shown = [
      for (final segment in segments)
        if (segment.value > 0) segment,
    ];
    final total = shown.fold<double>(0, (sum, segment) => sum + segment.value);
    final fill = AppMotion.segmentFill * shown.length;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: total == 0
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              )
            : TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: AppMotion.of(
                  context,
                  fill > AppMotion.ringSweep ? AppMotion.ringSweep : fill,
                ),
                curve: AppMotion.emphasizedDecelerate,
                builder: (context, progress, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, segment) in shown.indexed) ...[
                      if (index > 0) const SizedBox(width: _gap),
                      Expanded(
                        flex: (segment.value / total * 1000).round().clamp(
                          1,
                          1000,
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: segment.color,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

/// The text legend under a segment bar: a dot and a label per entry, so the
/// split never depends on colour alone.
class CdSegmentLegend extends StatelessWidget {
  const new({required this.entries, super.key});

  final List<(Color, String)> entries;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        for (final (color, label) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontSize: 13, color: palette.onSurfaceVariant),
              ),
            ],
          ),
      ],
    );
  }
}
