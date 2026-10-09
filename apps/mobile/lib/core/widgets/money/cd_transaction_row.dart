import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:flutter/material.dart';

/// Min 64 high: category icon, title, a context line and the amount, with
/// the BRL equivalent below a foreign one.
class CdTransactionRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.kind = CdAmountKind.expense,
    this.converted,
    this.badge,
    this.onTap,
    this.leading,
    this.corner,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Money amount;
  final CdAmountKind kind;
  final Money? converted;
  final Widget? badge;
  final VoidCallback? onTap;

  /// Replaces the icon, for an entity badge.
  final Widget? leading;

  /// A small mark on the icon's corner, such as the institution's logo.
  final Widget? corner;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final badge = this.badge;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.transactionRowMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  leading ?? CdIconTile(icon),
                  if (corner case final corner?)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.surface, width: 2),
                        ),
                        child: corner,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CdAmount(
                    amount,
                    size: CdAmountSize.row,
                    kind: kind,
                    converted: converted,
                  ),
                  if (badge != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    badge,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
