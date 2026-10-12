import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:cashdeck/features/budgets/presentation/budget_labels.dart';
import 'package:cashdeck/features/budgets/presentation/budgets_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// "Montar orçamento automático": a limit per category from the median of
/// the last three months, accepted in one tap or adjusted one by one.
class BudgetSuggestionsScreen extends ConsumerWidget {
  const new({required this.month, super.key});

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = budgetSuggestionsProvider(month);
    final suggestions = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.budgetsSuggestTitle)),
      body: switch (suggestions) {
        AsyncData(:final value) when value.items.isEmpty => CdEmptyState(
          icon: Symbols.auto_awesome_rounded,
          title: l10n.budgetsSuggestEmptyTitle,
          message: l10n.budgetsSuggestEmptyMessage,
        ),
        AsyncData(:final value) => _SuggestionList(suggestions: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(provider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _SuggestionList extends ConsumerStatefulWidget {
  const new({required this.suggestions});

  final BudgetSuggestions suggestions;

  @override
  ConsumerState<_SuggestionList> createState() => _SuggestionListState();
}

class _SuggestionListState extends ConsumerState<_SuggestionList> {
  late final Set<String> _chosen = {
    for (final item in widget.suggestions.items) item.category.id,
  };
  final Map<String, Money> _adjusted = {};
  var _saving = false;

  List<BudgetLimit> get _limits =>
      chosenLimits(widget.suggestions, chosen: _chosen, adjusted: _adjusted);

  Future<void> _adjust(BudgetSuggestion item) async {
    final l10n = AppLocalizations.of(context);
    final value = await showCdBottomSheet<Money>(
      context,
      title: spendCategoryName(l10n, item.category),
      builder: (_) =>
          _AdjustSheet(initial: _adjusted[item.category.id] ?? item.suggested),
    );
    if (value == null) return;
    setState(() {
      _adjusted[item.category.id] = value;
      _chosen.add(item.category.id);
    });
  }

  Future<void> _accept() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final month = widget.suggestions.month;
    final failure = await ref
        .read(budgetMonthControllerProvider(month).notifier)
        .accept(_limits);
    if (!mounted) return;
    setState(() => _saving = false);
    if (failure == null) context.pop();
    await showOutcomeToast(context, failure, success: l10n.budgetsAccepted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final limits = _limits;
    final total = limits.fold(
      const Money(0),
      (sum, entry) => sum + entry.limit,
    );
    final basedOn = widget.suggestions.basedOn
        .map((month) => monthTitle(l10n, month))
        .join(', ');
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.xl,
            ),
            children: [
              Text(
                l10n.budgetsSuggestIntro(basedOn),
                style: AppTextStyles.bodyMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final item in widget.suggestions.items) ...[
                _SuggestionRow(
                  item: item,
                  chosen: _chosen.contains(item.category.id),
                  value: _adjusted[item.category.id] ?? item.suggested,
                  hide: hide,
                  onChosen: (chosen) => setState(
                    () => chosen
                        ? _chosen.add(item.category.id)
                        : _chosen.remove(item.category.id),
                  ),
                  onAdjust: () => _adjust(item),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: CdButton.filled(
              key: BudgetSuggestionsKeys.acceptKey,
              expand: true,
              icon: Symbols.done_all_rounded,
              loading: _saving,
              label: l10n.budgetsAcceptAll(
                MoneyFormat.whole(total, hide: hide),
              ),
              onPressed: limits.isEmpty ? null : _accept,
            ),
          ),
        ),
      ],
    );
  }
}

abstract final class BudgetSuggestionsKeys {
  static const acceptKey = Key('budget-suggestions-accept');
  static const adjustValueKey = Key('budget-suggestion-adjust-value');
  static const adjustSaveKey = Key('budget-suggestion-adjust-save');

  static Key rowKey(String categoryId) => Key('budget-suggestion-$categoryId');

  static Key checkKey(String categoryId) =>
      Key('budget-suggestion-check-$categoryId');

  static Key adjustKey(String categoryId) =>
      Key('budget-suggestion-adjust-$categoryId');
}

class _SuggestionRow extends StatelessWidget {
  const new({
    required this.item,
    required this.chosen,
    required this.value,
    required this.hide,
    required this.onChosen,
    required this.onAdjust,
  });

  final BudgetSuggestion item;
  final bool chosen;
  final Money value;
  final bool hide;
  final ValueChanged<bool> onChosen;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final id = item.category.id;
    final history = item.months
        .map((spent) => MoneyFormat.whole(spent, hide: hide))
        .join(' · ');
    final current = item.current;
    return CdCard(
      key: BudgetSuggestionsKeys.rowKey(id),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Checkbox(
            key: BudgetSuggestionsKeys.checkKey(id),
            value: chosen,
            onChanged: (checked) => onChosen(checked ?? false),
          ),
          Icon(
            spendCategoryIcon(item.category),
            color: palette.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spendCategoryName(l10n, item.category),
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                Text(
                  history,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
                if (current != null)
                  Text(
                    l10n.budgetsSuggestCurrent(
                      MoneyFormat.whole(current, hide: hide),
                    ),
                    style: AppTextStyles.labelMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            key: BudgetSuggestionsKeys.adjustKey(id),
            onPressed: onAdjust,
            icon: const Icon(Symbols.edit_rounded, size: 18),
            label: Text(MoneyFormat.whole(value, hide: hide)),
          ),
        ],
      ),
    );
  }
}

class _AdjustSheet extends StatefulWidget {
  const new({required this.initial});

  final Money initial;

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  late Money _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdCurrencyInput(
          key: BudgetSuggestionsKeys.adjustValueKey,
          label: l10n.budgetLimit,
          initial: _value,
          onChanged: (value) => setState(() => _value = value),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: BudgetSuggestionsKeys.adjustSaveKey,
          expand: true,
          label: l10n.budgetSave,
          onPressed: () => Navigator.of(context).pop(_value),
        ),
      ],
    );
  }
}
