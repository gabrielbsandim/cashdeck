import 'dart:async';

import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// A bill: what, when, how much, its status and where it is on the ladder.
/// [action] replaces the ladder hint when the user has something to do.
class CdBillCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.dueLabel,
    required this.amount,
    required this.status,
    this.ladderHint,
    this.action,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String dueLabel;
  final Money amount;
  final Widget status;
  final String? ladderHint;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hint = ladderHint;
    final action = this.action;
    return CdCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CdIconTile(icon, circle: false),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    Text(
                      dueLabel,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              CdAmount(amount, size: CdAmountSize.row),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              status,
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: action == null
                    ? Text(
                        hint ?? '',
                        textAlign: TextAlign.end,
                        style: AppTextStyles.bodyMd.copyWith(
                          fontSize: 13,
                          color: palette.onSurfaceVariant,
                        ),
                      )
                    : Align(alignment: Alignment.centerRight, child: action),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The compact bill line used inside a grouped card on Início.
class CdBillRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.amount,
    required this.dateLabel,
    required this.status,
    this.leading,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final Money amount;
  final String? dateLabel;
  final Widget status;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final date = dateLabel;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            leading ?? CdIconTile(icon, circle: false),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.titleSm.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  status,
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CdAmount(amount, size: CdAmountSize.row),
                if (date != null)
                  Text(
                    date,
                    style: AppTextStyles.bodyMd.copyWith(
                      fontSize: 13,
                      color: palette.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The paid moment: the badge springs in (springSnappy) with a haptic.
class CdPaidPop extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<CdPaidPop> createState() => _CdPaidPopState();
}

class _CdPaidPopState extends State<CdPaidPop>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController.unbounded(vsync: this);

  @override
  void initState() {
    super.initState();
    _controller
      ..value = 0.6
      ..animateWith(SpringSimulation(AppMotion.springSnappy, 0.6, 1, 0));
    unawaited(HapticFeedback.mediumImpact());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    return ScaleTransition(scale: _controller, child: widget.child);
  }
}
