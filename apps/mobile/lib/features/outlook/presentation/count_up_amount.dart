import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A headline amount that counts up to [value] when it first shows and
/// glides to each new value; hidden amounts and reduced motion stay still.
class CountUpAmount extends ConsumerWidget {
  const new(this.value, {this.size = CdAmountSize.xl, this.color, super.key});

  final Money value;
  final CdAmountSize size;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(hideAmountsProvider);
    final style = CdAmount.styleOf(size)
        .copyWith(color: color ?? context.palette.onSurface);
    Text shown(Money amount) => Text(
      MoneyFormat.format(amount, hide: hide),
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    );
    if (hide) return shown(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.cents.toDouble()),
      duration: AppMotion.of(context, AppMotion.countUp),
      curve: AppMotion.emphasizedDecelerate,
      builder: (_, cents, _) =>
          shown(Money(cents.round(), currency: value.currency)),
    );
  }
}
