import 'dart:ui' show lerpDouble;

import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A card that grows into the screen it opens: wrap the card and the body
/// of that screen with the same [tag]. The surface morphs from the card's
/// rounded rect to the body while the card fades out and the body fades in.
/// Reduced motion keeps the plain page transition.
class CdExpandHero extends StatelessWidget {
  const new({required this.tag, required this.child, super.key});

  static String tagOf(String kind, String id) => 'cd-expand-$kind-$id';

  final Object tag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return Hero(tag: tag, flightShuttleBuilder: expandShuttle, child: child);
  }
}

/// The flight between a card and the body it opens; [animation] reads 0 on
/// the card and 1 on the body in both directions.
Widget expandShuttle(
  BuildContext flight,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext from,
  BuildContext to,
) {
  final (card, body) = switch (direction) {
    HeroFlightDirection.push => (from, to),
    HeroFlightDirection.pop => (to, from),
  };
  final palette = flight.palette;
  final cardLayer = _Layer.of(card);
  final bodyLayer = _Layer.of(body);
  return Material(
    type: MaterialType.transparency,
    child: AnimatedBuilder(
      animation: animation,
      builder: (_, _) {
        final t = animation.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(lerpDouble(AppRadius.lg, 0, t)!),
          child: ColoredBox(
            color: Color.lerp(palette.surfaceContainerLow, palette.surface, t)!,
            child: Stack(
              fit: StackFit.expand,
              children: [
                cardLayer.at(opacity: (1 - t / 0.4).clamp(0, 1)),
                bodyLayer.at(opacity: ((t - 0.3) / 0.7).clamp(0, 1)),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// One side of the flight, laid out at the size it has on its own screen so
/// nothing reflows while the box between them grows.
final class _Layer {
  const new(this.child, this.size);

  factory of(BuildContext hero) {
    final box = hero.findRenderObject();
    return _Layer(
      (hero.widget as Hero).child,
      box is RenderBox && box.hasSize ? box.size : null,
    );
  }

  final Widget child;
  final Size? size;

  Widget at({required double opacity}) {
    final size = this.size;
    final faded = Opacity(opacity: opacity, child: child);
    if (size == null) return faded;
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: size.width,
      maxWidth: size.width,
      minHeight: size.height,
      maxHeight: size.height,
      child: faded,
    );
  }
}
