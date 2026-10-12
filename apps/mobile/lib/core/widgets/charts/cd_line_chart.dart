import 'dart:math' as math;

import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/charts/cd_chart_scrub.dart';
import 'package:flutter/material.dart';

/// A balance over time: the line, its area, a dashed safety floor and a ring
/// on the lowest point. Labels arrive formatted so privacy can mask them.
/// With [pointLabel], dragging across reads each point.
class CdLineChart extends StatelessWidget {
  const new({
    required this.values,
    required this.xLabels,
    required this.semanticsLabel,
    this.floor,
    this.height = 112,
    this.pointLabel,
    super.key,
  });

  final List<double> values;
  final List<String> xLabels;
  final String semanticsLabel;

  /// The minimum safety balance, drawn dashed.
  final double? floor;
  final double height;

  /// The date and value of point `index`, for the scrub tooltip.
  final String Function(int index)? pointLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pointLabel = this.pointLabel;
    final chart = CustomPaint(
      painter: _LinePainter(
        values: values,
        floor: floor,
        line: palette.primary,
        area: palette.primaryContainer.withValues(alpha: 0.7),
        floorColor: context.money.expense,
        axis: palette.outlineVariant,
        ring: palette.surfaceContainerLow,
      ),
    );
    final scale = values.length < 2 ? null : LineScale.of(values, floor);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: pointLabel == null || scale == null
                ? chart
                : CdChartScrub(
                    count: values.length,
                    labelOf: pointLabel,
                    pointOf: (index, size) =>
                        scale.at(index, values[index], size),
                    child: chart,
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

/// Where each value of a line chart sits, shared by the painter and the
/// scrub: the top value at the top, a quarter of the range below the lowest.
final class LineScale {
  const new({required this.top, required this.bottom, required this.count});

  factory of(List<double> values, double? floor) {
    final top = values.reduce(math.max);
    final lowest = [...values, ?floor].reduce(math.min);
    final range = top - lowest == 0 ? 1.0 : top - lowest;
    return LineScale(
      top: top,
      bottom: lowest - range * 0.25,
      count: values.length,
    );
  }

  final double top;
  final double bottom;
  final int count;

  double y(double value, Size size) =>
      4 + (top - value) / (top - bottom) * (size.height - 8);

  double x(int index, Size size) => index * size.width / (count - 1);

  Offset at(int index, double value, Size size) =>
      Offset(x(index, size), y(value, size));
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
    final scale = LineScale.of(values, floor);
    double y(double value) => scale.y(value, size);
    double x(int index) => scale.x(index, size);
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
