import 'dart:math' as math;

import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

final class CdBarGroup {
  const new(this.label, this.income, this.expense);

  final String label;
  final double income;
  final double expense;
}

/// Income against expense per period, two bars a group, with a legend.
class CdBarChart extends StatelessWidget {
  const new({
    required this.groups,
    required this.incomeLabel,
    required this.expenseLabel,
    required this.semanticsLabel,
    this.height = 120,
    super.key,
  });

  final List<CdBarGroup> groups;
  final String incomeLabel;
  final String expenseLabel;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final money = context.money;
    final peak = groups.isEmpty
        ? 1.0
        : groups.map((g) => math.max(g.income, g.expense)).reduce(math.max);
    final caption = AppTextStyles.bodyMd.copyWith(
      fontSize: 12,
      color: palette.onSurfaceVariant,
    );
    Widget bar(double value, Color color) => Expanded(
      child: FractionallySizedBox(
        heightFactor: peak == 0 ? 0 : value / peak,
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
      ),
    );
    Widget legend(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: caption),
      ],
    );
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final group in groups)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          bar(group.income, money.income),
                          const SizedBox(width: 2),
                          bar(group.expense, money.expense),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (final group in groups)
                Expanded(
                  child: Text(
                    group.label,
                    textAlign: TextAlign.center,
                    style: caption,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            children: [
              legend(money.income, incomeLabel),
              legend(money.expense, expenseLabel),
            ],
          ),
        ],
      ),
    );
  }
}
