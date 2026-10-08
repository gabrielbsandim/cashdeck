import 'dart:math' as math;

import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// A balance over time: the line, its area, a dashed safety floor and a ring
/// on the lowest point. Labels arrive formatted so privacy can mask them.
class CdLineChart extends StatelessWidget {
  const new({
    required this.values,
    required this.xLabels,
    required this.semanticsLabel,
    this.floor,
    this.height = 112,
    super.key,
  });

  final List<double> values;
  final List<String> xLabels;
  final String semanticsLabel;

  /// The minimum safety balance, drawn dashed.
  final double? floor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: CustomPaint(
              painter: _LinePainter(
                values: values,
                floor: floor,
                line: palette.primary,
                area: palette.primaryContainer.withValues(alpha: 0.7),
                floorColor: context.money.expense,
                axis: palette.outlineVariant,
                ring: palette.surfaceContainerLow,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in xLabels)
                Text(
                  label,
                  style: AppTextStyles.bodyMd.copyWith(
                    fontSize: 12,
                    color: palette.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const new({
    required this.values,
    required this.floor,
    required this.line,
    required this.area,
    required this.floorColor,
    required this.axis,
    required this.ring,
  });

  final List<double> values;
  final double? floor;
  final Color line;
  final Color area;
  final Color floorColor;
  final Color axis;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final floor = this.floor;
    final top = values.reduce(math.max);
    final lowest = [...values, ?floor].reduce(math.min);
    final range = top - lowest == 0 ? 1.0 : top - lowest;
    final bottom = lowest - range * 0.25;
    double y(double value) =>
        4 + (top - value) / (top - bottom) * (size.height - 8);
    double x(int index) => index * size.width / (values.length - 1);
    final path = Path()..moveTo(0, y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas
      ..drawPath(fill, Paint()..color = area)
      ..drawLine(
        Offset(0, size.height),
        Offset.zero,
        Paint()
          ..color = axis
          ..strokeWidth = 1,
      )
      ..drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    if (floor != null) {
      final dash = Paint()
        ..color = floorColor
        ..strokeWidth = 1.2;
      for (var start = 0.0; start < size.width; start += 6) {
        canvas.drawLine(
          Offset(start, y(floor)),
          Offset(math.min(start + 3, size.width), y(floor)),
          dash,
        );
      }
    }
    final minIndex = values.indexOf(values.reduce(math.min));
    final point = Offset(x(minIndex), y(values[minIndex]));
    canvas
      ..drawCircle(point, 4.5, Paint()..color = ring)
      ..drawCircle(
        point,
        4.5,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.line != line;
}
