import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Sweeps a soft highlight across the placeholder shapes of [child], left
/// to right, so a loading screen reads as alive. Reduced motion keeps the
/// shapes still.
class CdShimmer extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<CdShimmer> createState() => _CdShimmerState();
}

class _CdShimmerState extends State<CdShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: AppMotion.skeletonPulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _sweep.stop();
      return;
    }
    if (!_sweep.isAnimating) _sweep.repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return widget.child;
    final palette = context.palette;
    final base = palette.surfaceContainerHigh;
    final highlight = palette.surfaceContainerLowest;
    return AnimatedBuilder(
      animation: _sweep,
      child: widget.child,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [base, highlight, base],
          stops: const [0.35, 0.5, 0.65],
          transform: _Slide(_sweep.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

/// Moves the gradient from one bounds width left of the box to one right.
final class _Slide extends GradientTransform {
  const new(this.progress);

  final double progress;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
}
