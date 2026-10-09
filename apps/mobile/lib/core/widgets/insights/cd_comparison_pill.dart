import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Whether a rise is good news: savings up is, spending up is not.
enum GoodWhen { up, down }

/// An arrow and a value in a tinted pill, then a muted label. The tone comes
/// from [goodWhen], so the same arrow can be green or orange.
class CdComparisonPill extends StatelessWidget {
  const new({
    required this.direction,
    required this.value,
    this.goodWhen = GoodWhen.down,
    this.label,
    super.key,
  });

  /// Positive for a rise, negative for a fall, zero for no change.
  final int direction;

  /// Already formatted, such as `12%` or `R$ 10,00`.
  final String value;
  final GoodWhen goodWhen;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final money = context.money;
    final good = switch (goodWhen) {
      GoodWhen.up => direction > 0,
      GoodWhen.down => direction < 0,
    };
    final colors = switch ((direction == 0, good)) {
      (true, _) => (palette.onSurfaceVariant, palette.surfaceContainerHigh),
      (false, true) => (money.paid, money.paidContainer),
      (false, false) => (money.overdue, money.overdueContainer),
    };
    final icon = switch (direction.sign) {
      1 => Symbols.arrow_upward_rounded,
      -1 => Symbols.arrow_downward_rounded,
      _ => Symbols.remove_rounded,
    };
    final label = this.label;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      children: [
        Container(
          height: 24,
          padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
          decoration: BoxDecoration(
            color: colors.$2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colors.$1),
              const SizedBox(width: 2),
              Text(
                value,
                style: AppTextStyles.labelMd.copyWith(
                  fontSize: 13,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: colors.$1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (label != null)
          Text(
            label,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
