import 'dart:math' as math;

import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Income and expenses as two bars on one scale, growing together.
class CdFlowBars extends StatelessWidget {
  const new({
    required this.income,
    required this.expenses,
    required this.incomeLabel,
    required this.expensesLabel,
    required this.incomeAmount,
    required this.expensesAmount,
    super.key,
  });

  final double income;
  final double expenses;
  final String incomeLabel;
  final String expensesLabel;
  final Widget incomeAmount;
  final Widget expensesAmount;

  @override
  Widget build(BuildContext context) {
    final money = context.money;
    final top = math.max(math.max(income, expenses), 1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.chartDraw),
      curve: AppMotion.emphasizedDecelerate,
      builder: (context, progress, _) => Column(
        children: [
          _FlowRow(
            icon: Symbols.south_west_rounded,
            color: money.income,
            label: incomeLabel,
            amount: incomeAmount,
            fraction: income / top * progress,
          ),
          const SizedBox(height: AppSpacing.md),
          _FlowRow(
            icon: Symbols.north_east_rounded,
            color: money.expense,
            label: expensesLabel,
            amount: expensesAmount,
            fraction: expenses / top * progress,
          ),
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.color,
    required this.label,
    required this.amount,
    required this.fraction,
  });

  final IconData icon;
  final Color color;
  final String label;
  final Widget amount;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.xs + 2),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ),
            amount,
          ],
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        Container(
          height: 10,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: palette.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(5),
          ),
          child: FractionallySizedBox(
            widthFactor: fraction.clamp(0, 1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
