import 'dart:math' as math;

import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

final class CdDonutSlice {
  const new(this.label, this.fraction, this.color);

  final String label;
  final double fraction;
  final Color color;
}

/// Shares of a whole with the total in the middle and a legend below.
class CdDonut extends StatelessWidget {
  const new({
    required this.slices,
    required this.centerValue,
    required this.centerCaption,
    this.size = 132,
    super.key,
  });

  final List<CdDonutSlice> slices;
  final String centerValue;
  final String centerCaption;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: [
        '$centerValue $centerCaption',
        for (final slice in slices)
          '${slice.label} ${(slice.fraction * 100).round()}%',
      ].join(', '),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _DonutPainter(slices),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerValue,
                      style: AppTextStyles.titleMd.copyWith(
                        color: palette.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      centerCaption,
                      style: AppTextStyles.bodyMd.copyWith(
                        fontSize: 12,
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            alignment: WrapAlignment.center,
            children: [
              for (final slice in slices)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: slice.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      slice.label,
                      style: AppTextStyles.bodyMd.copyWith(
                        fontSize: 12,
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const new(this.slices);

  final List<CdDonutSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    const gap = 0.03;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = slice.fraction * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        math.max(0, sweep - gap),
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) => oldDelegate.slices != slices;
}

/// How a whole splits between parts, as one rounded bar.
class CdSplitBar extends StatelessWidget {
  const new({required this.parts, super.key});

  final List<(double, Color)> parts;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final (index, (fraction, color)) in parts.indexed) ...[
              if (index > 0) const SizedBox(width: 2),
              Expanded(
                flex: math.max(1, (fraction * 1000).round()),
                child: ColoredBox(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
