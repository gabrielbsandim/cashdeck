import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:cashdeck/features/budgets/presentation/budget_labels.dart';
import 'package:cashdeck/features/budgets/presentation/budgets_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Sets the limit of [category] in [month], or edits [item] when it exists.
Future<void> showBudgetLimitSheet(
  BuildContext context, {
  required YearMonth month,
  required SpendCategory category,
  BudgetItem? item,
}) async {
  final l10n = AppLocalizations.of(context);
  final message = await showCdBottomSheet<String>(
    context,
    title: spendCategoryName(l10n, category),
    builder: (_) =>
        BudgetLimitSheet(month: month, category: category, item: item),
  );
  if (message == null || !context.mounted) return;
  await showCdToast(context, icon: Symbols.task_alt_rounded, message: message);
}

class BudgetLimitSheet extends ConsumerStatefulWidget {
  const new({
    required this.month,
    required this.category,
    this.item,
    super.key,
  });

  static const limitKey = Key('budget-limit');
  static const rolloverKey = Key('budget-rollover');
  static const saveKey = Key('budget-save');
  static const deleteKey = Key('budget-delete');
  static const errorKey = Key('budget-error');

  final YearMonth month;
  final SpendCategory category;
  final BudgetItem? item;

  @override
  ConsumerState<BudgetLimitSheet> createState() => _BudgetLimitSheetState();
}

class _BudgetLimitSheetState extends ConsumerState<BudgetLimitSheet> {
  late Money _limit = widget.item?.limit ?? const Money(0);
  late bool _rollover = widget.item?.rollover ?? false;
  var _busy = false;
  String? _error;

  BudgetMonthController get _controller =>
      ref.read(budgetMonthControllerProvider(widget.month).notifier);

  Future<void> _run(Future<AppFailure?> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final failure = await action();
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(done);
      return;
    }
    setState(() {
      _busy = false;
      _error = failure.userMessage(l10n);
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_limit.cents <= 0) {
      setState(() => _error = l10n.budgetLimitMissing);
      return;
    }
    await _run(
      () => _controller.setLimit(
        categoryId: widget.category.id,
        limit: _limit,
        rollover: _rollover,
        id: widget.item?.id,
      ),
      l10n.budgetSaved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final item = widget.item;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdCurrencyInput(
          key: BudgetLimitSheet.limitKey,
          label: l10n.budgetLimit,
          initial: _limit,
          helperText: item == null || item.carried.cents == 0
              ? null
              : l10n.budgetCarried(MoneyFormat.whole(item.carried)),
          onChanged: (value) => setState(() => _limit = value),
        ),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile(
          key: BudgetLimitSheet.rolloverKey,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.budgetRollover),
          subtitle: Text(
            l10n.budgetRolloverHelp,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          value: _rollover,
          onChanged: (value) => setState(() => _rollover = value),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: BudgetLimitSheet.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: BudgetLimitSheet.saveKey,
          expand: true,
          label: l10n.budgetSave,
          loading: _busy,
          onPressed: _save,
        ),
        if (item != null) ...[
          const SizedBox(height: AppSpacing.sm),
          CdButton.text(
            key: BudgetLimitSheet.deleteKey,
            expand: true,
            icon: Symbols.delete_rounded,
            label: l10n.budgetDelete,
            onPressed: _busy
                ? null
                : () => _run(
                    () => _controller.delete(item.id),
                    l10n.budgetDeleted,
                  ),
          ),
        ],
      ],
    );
  }
}
