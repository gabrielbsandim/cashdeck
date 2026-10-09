import 'dart:math' as math;

import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// Cumulative spending of this period over the dashed previous one, with a
/// "today" marker on the last point. The line draws left to right once.
class CdSpendChart extends StatelessWidget {
  const new({
    required this.current,
    required this.previous,
    required this.xLabels,
    required this.todayLabel,
    required this.semanticsLabel,
    this.height = 120,
    super.key,
  });

  /// One cumulative value per elapsed day.
  final List<double> current;

  /// One cumulative value per day of the whole previous period.
  final List<double> previous;
  final List<String> xLabels;
  final String todayLabel;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final charts = context.charts;
    final labelStyle = AppTextStyles.bodyMd.copyWith(
      fontSize: 12,
      color: palette.onSurfaceVariant,
    );
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.of(context, AppMotion.chartDraw),
              curve: AppMotion.emphasizedDecelerate,
              builder: (context, progress, _) => CustomPaint(
                painter: SpendPainter(
                  current: current,
                  previous: previous,
                  progress: progress,
                  line: palette.primary,
                  previousColor: charts.previous,
                  today: charts.today,
                  grid: charts.grid,
                  ring: charts.card,
                  todayLabel: todayLabel,
                  labelStyle: labelStyle.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in xLabels) Text(label, style: labelStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class SpendPainter extends CustomPainter {
  const new({
    required this.current,
    required this.previous,
    required this.progress,
    required this.line,
    required this.previousColor,
    required this.today,
    required this.grid,
    required this.ring,
    required this.todayLabel,
    required this.labelStyle,
  });

  final List<double> current;
  final List<double> previous;
  final double progress;
  final Color line;
  final Color previousColor;
  final Color today;
  final Color grid;
  final Color ring;
  final String todayLabel;
  final TextStyle labelStyle;

  static void dashed(
    Canvas canvas,
    List<Offset> points,
    Paint paint, {
    double dash = 4,
    double gap = 4,
  }) {
    var drawing = true;
    var left = dash;
    for (var i = 1; i < points.length; i++) {
      var from = points[i - 1];
      final to = points[i];
      var remaining = (to - from).distance;
      while (remaining > 0) {
        final step = math.min(left, remaining);
        final next = Offset.lerp(from, to, step / remaining)!;
        if (drawing) canvas.drawLine(from, next, paint);
        remaining -= step;
        left -= step;
        from = next;
        if (left > 0) continue;
        drawing = !drawing;
        left = drawing ? dash : gap;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final days = math.max(math.max(previous.length, current.length), 2);
    final top = [...current, ...previous, 1.0].reduce(math.max);
    const labelHeight = 18.0;
    double x(int day) => day * size.width / (days - 1);
    double y(double value) =>
        size.height - 4 - value / top * (size.height - labelHeight - 8);
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    if (previous.length > 1) {
      dashed(
        canvas,
        [for (final (i, v) in previous.indexed) Offset(x(i), y(v))],
        Paint()
          ..color = previousColor
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
    if (current.isEmpty) return;
    final points = [for (final (i, v) in current.indexed) Offset(x(i), y(v))];
    final last = points.last;
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, 0, last.dx * progress + 6, size.height));
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final area = Path.from(path)
      ..lineTo(last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas
      ..drawPath(area, Paint()..color = line.withValues(alpha: 0.14 * progress))
      ..drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..restore();
    if (progress < 1) return;
    dashed(
      canvas,
      [Offset(last.dx, labelHeight), Offset(last.dx, size.height)],
      Paint()
        ..color = today
        ..strokeWidth = 1,
      dash: 2,
      gap: 3,
    );
    final label = TextPainter(
      text: TextSpan(text: todayLabel, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelX = math.min(last.dx + 4, size.width - label.width);
    label.paint(canvas, Offset(math.max(labelX, 0), 0));
    canvas
      ..drawCircle(last, 5, Paint()..color = ring)
      ..drawCircle(
        last,
        5,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(SpendPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.current != current ||
      oldDelegate.previous != previous ||
      oldDelegate.line != line;
}
