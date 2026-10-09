import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The two radial glows behind the home header, in the colours of the
/// entity in scope; switching entity cross-fades them.
class CdEntityGlow extends StatelessWidget {
  const new({required this.colors, this.height = 460, super.key});

  final (Color, Color) colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (first, second) = colors;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: AppMotion.of(context, const Duration(milliseconds: 300)),
        child: SizedBox(
          key: ValueKey(colors),
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.44, -0.3),
                    radius: 0.9,
                    colors: [first, first.withValues(alpha: 0)],
                    stops: const [0, 0.7],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.64, -0.5),
                    radius: 0.75,
                    colors: [second, second.withValues(alpha: 0)],
                    stops: const [0, 0.72],
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
