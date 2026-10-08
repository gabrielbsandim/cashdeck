import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/feedback/tone_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CdAmountSize { xl, lg, md, sm, row }

/// [expense] stays in onSurface with a true minus so lists do not turn red;
/// [income] adds a plus and the arrow; [transfer] never carries a sign.
enum CdAmountKind { plain, expense, income, transfer }

/// An amount that follows the privacy toggle.
class CdAmount extends ConsumerWidget {
  const new(
    this.value, {
    this.size = CdAmountSize.md,
    this.kind = CdAmountKind.plain,
    this.converted,
    this.rateLabel,
    this.showIcon = false,
    this.color,
    this.textAlign = TextAlign.end,
    super.key,
  });

  final Money value;
  final CdAmountSize size;
  final CdAmountKind kind;

  /// The BRL equivalent of a foreign amount, shown below it.
  final Money? converted;
  final String? rateLabel;
  final bool showIcon;

  /// Overrides the kind's color, for chart totals and inverse surfaces.
  final Color? color;
  final TextAlign textAlign;

  static TextStyle styleOf(CdAmountSize size) => switch (size) {
    CdAmountSize.xl => AppTextStyles.amountXl,
    CdAmountSize.lg => AppTextStyles.amountLg,
    CdAmountSize.md => AppTextStyles.amountMd,
    CdAmountSize.sm => AppTextStyles.amountSm,
    CdAmountSize.row => AppTextStyles.amountRow,
  };

  static MoneySign signOf(CdAmountKind kind) => switch (kind) {
    CdAmountKind.income => MoneySign.plus,
    CdAmountKind.transfer => MoneySign.none,
    CdAmountKind.plain || CdAmountKind.expense => MoneySign.natural,
  };

  Money get _signed => switch (kind) {
    CdAmountKind.expense => Money(-value.cents.abs(), currency: value.currency),
    CdAmountKind.income => value.abs,
    CdAmountKind.plain || CdAmountKind.transfer => value,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(hideAmountsProvider);
    final palette = context.palette;
    final money = context.money;
    final tone = switch (kind) {
      CdAmountKind.income => MoneyTone.income,
      CdAmountKind.transfer => MoneyTone.transfer,
      CdAmountKind.plain || CdAmountKind.expense => null,
    };
    final foreground =
        color ??
        (tone == null ? palette.onSurface : money.tone(tone).foreground);
    final style = styleOf(size).copyWith(color: foreground);
    final text = Text(
      MoneyFormat.format(_signed, hide: hide, sign: signOf(kind)),
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
      textAlign: textAlign,
    );
    final converted = this.converted;
    final main = showIcon && tone != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tone.icon, size: style.fontSize, color: foreground),
              const SizedBox(width: AppSpacing.xs),
              Flexible(child: text),
            ],
          )
        : text;
    if (converted == null) return main;
    final rate = rateLabel;
    final approx = MoneyFormat.format(
      kind == CdAmountKind.expense ? Money(-converted.cents.abs()) : converted,
      hide: hide,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: textAlign == TextAlign.start
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        main,
        Text(
          rate == null ? '≈ $approx' : '≈ $approx · $rate',
          style: AppTextStyles.bodyMd.copyWith(
            color: palette.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Text with amounts inside it, such as an alert: [build] receives whether
/// amounts are hidden so every figure in the sentence can be masked.
class CdPrivateText extends ConsumerWidget {
  const new(this.textOf, {this.style, this.maxLines, super.key});

  // The flag is the builder's only input; naming it adds nothing.
  // ignore: avoid_positional_boolean_parameters
  final String Function(bool hide) textOf;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Text(
      textOf(ref.watch(hideAmountsProvider)),
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
