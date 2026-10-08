import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:flutter/material.dart';

/// An account with its institution monogram, how fresh its data is and the
/// balance. [syncTone] colors the freshness line.
class CdAccountCard extends StatelessWidget {
  const new({
    required this.monogram,
    required this.name,
    required this.balance,
    required this.syncIcon,
    required this.syncLabel,
    this.syncTone = MoneyTone.paid,
    this.onTap,
    super.key,
  });

  final String monogram;
  final String name;
  final Money balance;
  final IconData syncIcon;
  final String syncLabel;
  final MoneyTone syncTone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = context.tone(syncTone);
    return CdCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Text(
              monogram,
              style: AppTextStyles.labelMd.copyWith(
                color: palette.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    Icon(syncIcon, size: 16, color: tone.foreground),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        syncLabel,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: tone.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          CdAmount(balance, size: CdAmountSize.row),
        ],
      ),
    );
  }
}
