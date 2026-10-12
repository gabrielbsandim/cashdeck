import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_budget_bar.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_refresh.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:cashdeck/features/budgets/presentation/budget_labels.dart';
import 'package:cashdeck/features/budgets/presentation/budget_limit_sheet.dart';
import 'package:cashdeck/features/budgets/presentation/budgets_controller.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Opens the suggestion flow for [month].
void openBudgetSuggestions(BuildContext context, YearMonth month) =>
    context.push(AppRoutes.budgetSuggestionsFor(month.iso));

/// A month of budgets of the person or the company: the total, every
/// category against its limit, and the categories spending without one.
class BudgetsScreen extends ConsumerStatefulWidget {
  const new({this.initialMonth, super.key});

  static const previousKey = Key('budgets-previous');
  static const nextKey = Key('budgets-next');
  static const suggestKey = Key('budgets-suggest');
  static const copyKey = Key('budgets-copy');

  static Key entityKey(EntityKind entity) => Key('budgets-${entity.name}');

  static Key itemKey(String id) => Key('budget-$id');

  static Key unbudgetedKey(String categoryId) =>
      Key('budget-unbudgeted-$categoryId');

  final YearMonth? initialMonth;

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  late YearMonth _month =
      widget.initialMonth ?? ref.read(currentBudgetMonthProvider);

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    final failure = await ref
        .read(budgetMonthControllerProvider(_month).notifier)
        .copyToNext();
    if (!mounted) return;
    if (failure == null) setState(() => _month = _month.add(1));
    await showOutcomeToast(context, failure, success: l10n.budgetsCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = budgetMonthControllerProvider(_month);
    final budgets = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.budgetsTitle)),
      body: Column(
        children: [
          const _EntityToggle(),
          _MonthSwitcher(
            month: _month,
            onChanged: (month) => setState(() => _month = month),
          ),
          Expanded(
            child: switch (budgets) {
              AsyncData(:final value) when value.isEmpty => _EmptyMonth(
                month: value,
                onSuggest: () => openBudgetSuggestions(context, _month),
              ),
              AsyncData(:final value) => CdRefresh(
                providers: [provider],
                child: _MonthList(month: value, onCopy: _copy),
              ),
              AsyncError(:final error) => CdErrorState(
                failure: failureOf(error),
                onRetry: () => ref.invalidate(provider),
              ),
              _ => const CdSkeleton(parts: [CdSkeletonCards(count: 4)]),
            },
          ),
        ],
      ),
    );
  }
}

/// Switches the home scope between the person and the company, the two
/// entities that keep budgets.
class _EntityToggle extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        0,
      ),
      child: CdSegmented<EntityKind>(
        segments: [
          CdSegment(
            EntityKind.personal,
            l10n.entityPersonal,
            key: BudgetsScreen.entityKey(EntityKind.personal),
          ),
          CdSegment(
            EntityKind.company,
            l10n.entityCompany,
            key: BudgetsScreen.entityKey(EntityKind.company),
          ),
        ],
        selected: ref.watch(budgetEntityProvider),
        onChanged: (entity) =>
            ref.read(entityScopeProvider.notifier).select(switch (entity) {
              EntityKind.personal => EntityScope.personal,
              EntityKind.company => EntityScope.company,
            }),
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const new({required this.month, required this.onChanged});

  final YearMonth month;
  final ValueChanged<YearMonth> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          IconButton(
            key: BudgetsScreen.previousKey,
            tooltip: l10n.budgetsPreviousMonth,
            icon: const Icon(Symbols.chevron_left_rounded),
            onPressed: () => onChanged(month.add(-1)),
          ),
          Expanded(
            child: Text(
              monthTitle(l10n, month),
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMd.copyWith(
                color: context.palette.onSurface,
              ),
            ),
          ),
          IconButton(
            key: BudgetsScreen.nextKey,
            tooltip: l10n.budgetsNextMonth,
            icon: const Icon(Symbols.chevron_right_rounded),
            onPressed: () => onChanged(month.add(1)),
          ),
        ],
      ),
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  const new({required this.month, required this.onSuggest});

  final BudgetMonth month;
  final VoidCallback onSuggest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        CdEmptyState(
          icon: Symbols.donut_small_rounded,
          title: l10n.budgetsEmptyTitle,
          message: l10n.budgetsEmptyMessage,
          actionLabel: l10n.budgetsSuggest,
          actionIcon: Symbols.auto_awesome_rounded,
          onAction: onSuggest,
        ),
        _Unbudgeted(month: month),
      ],
    );
  }
}

class _MonthList extends ConsumerWidget {
  const new({required this.month, required this.onCopy});

  final BudgetMonth month;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        BudgetTotalCard(total: month.total),
        const SizedBox(height: AppSpacing.sectionGap),
        CdSectionHeader(title: l10n.budgetsCategories),
        const SizedBox(height: AppSpacing.sm),
        CdCard(
          child: Column(
            children: [
              for (final item in month.items)
                InkWell(
                  key: BudgetsScreen.itemKey(item.id),
                  onTap: () => showBudgetLimitSheet(
                    context,
                    month: month.month,
                    category: item.category,
                    item: item,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CdBudgetBar(
                        icon: spendCategoryIcon(item.category),
                        name: spendCategoryName(l10n, item.category),
                        spent: item.usage.spent,
                        limit: item.usage.available,
                      ),
                      Text(
                        l10n.budgetsTotal(
                          MoneyFormat.whole(item.usage.spent, hide: hide),
                          MoneyFormat.whole(item.usage.available, hide: hide),
                        ),
                        style: AppTextStyles.bodyMd.copyWith(
                          color: context.palette.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _Unbudgeted(month: month),
        const SizedBox(height: AppSpacing.sectionGap),
        CdButton.tonal(
          key: BudgetsScreen.suggestKey,
          expand: true,
          icon: Symbols.auto_awesome_rounded,
          label: l10n.budgetsSuggest,
          onPressed: () => openBudgetSuggestions(context, month.month),
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          key: BudgetsScreen.copyKey,
          expand: true,
          icon: Symbols.content_copy_rounded,
          label: l10n.budgetsCopy(monthTitle(l10n, month.month.add(1))),
          onPressed: onCopy,
        ),
      ],
    );
  }
}

class _Unbudgeted extends ConsumerWidget {
  const new({required this.month});

  final BudgetMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    if (month.unbudgeted.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CdSectionHeader(
            title: l10n.budgetsUnbudgeted,
            subtitle: Text(
              l10n.budgetsUnbudgetedHelp,
              style: AppTextStyles.bodyMd.copyWith(
                color: context.palette.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final spend in month.unbudgeted)
            CdListRow(
              key: BudgetsScreen.unbudgetedKey(spend.category.id),
              icon: spendCategoryIcon(spend.category),
              title: spendCategoryName(l10n, spend.category),
              subtitle: l10n.budgetsSpentSoFar(
                MoneyFormat.whole(spend.spent, hide: hide),
              ),
              chevron: true,
              onTap: () => showBudgetLimitSheet(
                context,
                month: month.month,
                category: spend.category,
              ),
            ),
        ],
      ),
    );
  }
}

/// Spent against everything the month allows, and what is left.
class BudgetTotalCard extends ConsumerWidget {
  const new({required this.total, this.child, super.key});

  final BudgetUsage total;

  /// Shown under the total, such as the categories close to the limit.
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final money = context.money;
    final hide = ref.watch(hideAmountsProvider);
    final fill = switch (total.level) {
      BudgetLevel.reached => money.overdue,
      BudgetLevel.near => money.pending,
      BudgetLevel.ok => palette.primary,
    };
    final child = this.child;
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.budgetsTotal(
              MoneyFormat.whole(total.spent, hide: hide),
              MoneyFormat.whole(total.available, hide: hide),
            ),
            style: AppTextStyles.titleMd.copyWith(color: palette.onSurface),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: (total.percent / 100).clamp(0, 1),
              minHeight: 8,
              color: fill,
              backgroundColor: palette.surfaceContainerHigh,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            total.over
                ? l10n.budgetsOver(
                    MoneyFormat.whole(-total.remaining, hide: hide),
                  )
                : l10n.budgetsLeft(
                    MoneyFormat.whole(total.remaining, hide: hide),
                  ),
            style: AppTextStyles.bodyMd.copyWith(
              color: total.over ? money.overdue : palette.onSurfaceVariant,
            ),
          ),
          if (child != null) ...[const SizedBox(height: AppSpacing.md), child],
        ],
      ),
    );
  }
}
