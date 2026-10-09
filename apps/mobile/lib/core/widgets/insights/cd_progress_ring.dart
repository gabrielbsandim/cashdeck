import 'dart:math' as math;

import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A ring of up to three parts, each a fraction of the whole, swept
/// clockwise from 12 o'clock, with [center] in the middle.
class CdProgressRing extends StatelessWidget {
  const new({
    required this.parts,
    required this.semanticsLabel,
    this.size = 48,
    this.stroke = 6,
    this.center,
    super.key,
  });

  final List<(double, Color)> parts;
  final String semanticsLabel;
  final double size;
  final double stroke;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final track = context.palette.surfaceContainerHigh;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.of(context, AppMotion.ringSweep),
          curve: AppMotion.emphasizedDecelerate,
          builder: (context, progress, child) => CustomPaint(
            painter: RingPainter(
              parts: parts,
              track: track,
              stroke: stroke,
              progress: progress,
            ),
            child: child,
          ),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  const new({
    required this.parts,
    required this.track,
    required this.stroke,
    required this.progress,
  });

  final List<(double, Color)> parts;
  final Color track;
  final double stroke;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );
    Paint paint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint(track));
    var start = -math.pi / 2;
    for (final (fraction, color) in parts) {
      final sweep = fraction.clamp(0, 1) * math.pi * 2 * progress;
      canvas.drawArc(rect, start, sweep, false, paint(color));
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.parts != parts;
}
