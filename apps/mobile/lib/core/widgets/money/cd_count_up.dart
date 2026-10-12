import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Builds [value] counting: up from zero when it first shows, then from the
/// figure on screen to each new one. Reduced motion lands on [value] at once.
class CdCountUp extends StatelessWidget {
  const new({required this.value, required this.builder, super.key});

  final Money value;
  final Widget Function(Money shown) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.cents.toDouble()),
      duration: AppMotion.of(context, AppMotion.countUp),
      curve: AppMotion.emphasizedDecelerate,
      builder: (_, cents, _) =>
          builder(Money(cents.round(), currency: value.currency)),
    );
  }
}
