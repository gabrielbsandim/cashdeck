import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_budget_bar.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:cashdeck/features/budgets/presentation/budget_labels.dart';
import 'package:cashdeck/features/budgets/presentation/budgets_controller.dart';
import 'package:cashdeck/features/budgets/presentation/budgets_screen.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The month's budget on Início: total spent against the total limit and
/// the categories closest to theirs, or a way to build one.
class HomeBudgetCard extends ConsumerWidget {
  const new({super.key});

  static const seeAllKey = Key('home-budget-see-all');
  static const suggestKey = Key('home-budget-suggest');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(currentBudgetMonthProvider);
    final month = ref.watch(budgetMonthControllerProvider(current)).value;
    if (month == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdSectionHeader(
          title: l10n.budgetsOfMonth(monthName(l10n, current)),
          actionLabel: month.isEmpty ? null : l10n.seeAllButton,
          actionKey: seeAllKey,
          onAction: () => context.push(AppRoutes.budgets),
        ),
        const SizedBox(height: AppSpacing.md),
        if (month.isEmpty)
          const _NoBudget()
        else
          BudgetTotalCard(
            total: month.total,
            child: _NearLimit(items: month.nearLimit()),
          ),
      ],
    );
  }
}

class _NearLimit extends StatelessWidget {
  const new({required this.items});

  final List<BudgetItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (items.isEmpty) {
      return Text(
        l10n.homeBudgetAllCalm,
        style: AppTextStyles.bodyMd.copyWith(
          color: context.palette.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (final item in items)
          CdBudgetBar(
            icon: spendCategoryIcon(item.category),
            name: spendCategoryName(l10n, item.category),
            spent: item.usage.spent,
            limit: item.usage.available,
          ),
      ],
    );
  }
}

class _NoBudget extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Symbols.donut_small_rounded,
                color: palette.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.homeBudgetEmpty,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CdButton.tonal(
            key: HomeBudgetCard.suggestKey,
            icon: Symbols.auto_awesome_rounded,
            label: l10n.budgetsSuggest,
            onPressed: () => openBudgetSuggestions(
              context,
              ref.read(currentBudgetMonthProvider),
            ),
          ),
        ],
      ),
    );
  }
}
