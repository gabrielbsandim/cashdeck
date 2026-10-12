import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_filter_chip.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_options_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_controller.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_labels.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Regras de categoria: what the app labels on its own, each one editable.
class CategoryRulesScreen extends ConsumerWidget {
  const new({super.key});

  static Key rowKey(String id) => Key('category-rule-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rules = ref.watch(categoryRulesControllerProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.categoryRulesTitle)),
      body: switch (rules) {
        AsyncData(:final value) when value.isEmpty => CdEmptyState(
          icon: Symbols.rule_rounded,
          title: l10n.categoryRulesEmptyTitle,
          message: l10n.categoryRulesEmptyMessage,
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: AppSpacing.xxl,
          ),
          children: [
            for (final rule in value)
              CdListRow(
                key: rowKey(rule.id),
                icon: categoryIcon(categoryById(rule.categoryId, categories)),
                title: ruleMatchLabel(l10n, rule),
                subtitle: ruleScopeLine(l10n, rule, categories),
                chevron: true,
                onTap: () => showCategoryRuleEditor(context, rule),
              ),
          ],
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(categoryRulesControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

enum _EditorOutcome { saved, delete }

/// Edits [rule]; deleting asks once more in its own sheet.
Future<void> showCategoryRuleEditor(
  BuildContext context,
  CategoryRule rule,
) async {
  final l10n = AppLocalizations.of(context);
  final outcome = await showCdBottomSheet<_EditorOutcome>(
    context,
    title: l10n.categoryRuleEdit,
    builder: (_) => CategoryRuleEditor(rule: rule),
  );
  if (!context.mounted || outcome == null) return;
  switch (outcome) {
    case _EditorOutcome.saved:
      await showCdToast(
        context,
        icon: Symbols.task_alt_rounded,
        message: l10n.categoryRuleSaved,
      );
    case _EditorOutcome.delete:
      await _confirmDelete(context, rule);
  }
}

Future<void> _confirmDelete(BuildContext context, CategoryRule rule) async {
  final l10n = AppLocalizations.of(context);
  final deleted = await showCdBottomSheet<bool>(
    context,
    title: l10n.categoryRuleDeleteTitle,
    builder: (_) => _DeleteSheet(rule: rule),
  );
  if (deleted != true || !context.mounted) return;
  await showCdToast(
    context,
    icon: Symbols.task_alt_rounded,
    message: l10n.categoryRuleDeleted,
  );
}

class CategoryRuleEditor extends ConsumerStatefulWidget {
  const new({required this.rule, super.key});

  static const patternKey = Key('category-rule-pattern');
  static const categoryKey = Key('category-rule-category');
  static const saveKey = Key('category-rule-save');
  static const deleteKey = Key('category-rule-delete');
  static const errorKey = Key('category-rule-error');

  static Key optionKey(String id) => Key('category-rule-option-$id');

  final CategoryRule rule;

  @override
  ConsumerState<CategoryRuleEditor> createState() => _CategoryRuleEditorState();
}

class _CategoryRuleEditorState extends ConsumerState<CategoryRuleEditor> {
  late final CategoryRule _rule = widget.rule;
  late final _pattern = TextEditingController(text: _rule.pattern);
  late String _categoryId = _rule.categoryId;
  var _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  /// Only what changed travels; an untouched document rule keeps matching
  /// its document.
  CategoryRuleChange get _change {
    final pattern = _pattern.text.trim();
    return CategoryRuleChange(
      pattern: pattern == _rule.pattern ? null : pattern,
      categoryId: _categoryId == _rule.categoryId ? null : _categoryId,
    );
  }

  Future<void> _pick(List<Category> categories) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showOptionsSheet<Category>(
      context,
      title: l10n.categoryReviewPickCategory,
      options: [
        for (final category in categories)
          PickerOption(
            value: category,
            label: categoryName(l10n, category),
            key: CategoryRuleEditor.optionKey(category.id),
            icon: categoryIcon(category),
            selected: category.id == _categoryId,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _categoryId = picked.$1.id);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final change = _change;
    if (!change.isValid) {
      setState(() => _serverError = l10n.categoryRulePatternMissing);
      return;
    }
    setState(() {
      _saving = true;
      _serverError = null;
    });
    final navigator = Navigator.of(context);
    final failure = await ref
        .read(categoryRulesControllerProvider.notifier)
        .save(_rule, change);
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(_EditorOutcome.saved);
      return;
    }
    setState(() {
      _saving = false;
      _serverError = failure.userMessage(l10n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final category = categoryById(_categoryId, categories);
    final document = _rule.counterparty;
    final serverError = _serverError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdTextField(
          key: CategoryRuleEditor.patternKey,
          controller: _pattern,
          label: l10n.categoryRulePattern,
          helperText: _rule.pattern.isEmpty && document != null
              ? l10n.categoryRuleDocumentHint(document)
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: CdFilterChip(
            key: CategoryRuleEditor.categoryKey,
            label: categoryLabel(l10n, _categoryId, categories),
            icon: categoryIcon(category),
            selected: true,
            dropdown: true,
            onTap: _saving ? null : () => _pick(categories),
          ),
        ),
        if (serverError != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            serverError,
            key: CategoryRuleEditor.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: CategoryRuleEditor.saveKey,
          expand: true,
          label: l10n.categoryRuleSave,
          loading: _saving,
          onPressed: _save,
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          key: CategoryRuleEditor.deleteKey,
          expand: true,
          icon: Symbols.delete_rounded,
          label: l10n.categoryRuleDelete,
          onPressed: () => Navigator.of(context).pop(_EditorOutcome.delete),
        ),
      ],
    );
  }
}

class _DeleteSheet extends ConsumerStatefulWidget {
  const new({required this.rule});

  final CategoryRule rule;

  @override
  ConsumerState<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends ConsumerState<_DeleteSheet> {
  var _deleting = false;

  Future<void> _delete() async {
    setState(() => _deleting = true);
    final navigator = Navigator.of(context);
    final failure = await ref
        .read(categoryRulesControllerProvider.notifier)
        .delete(widget.rule);
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(true);
      return;
    }
    setState(() => _deleting = false);
    await showOutcomeToast(context, failure, success: '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.categoryRuleDeleteMessage,
          style: AppTextStyles.bodyLg.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.danger(
          key: CategoryRuleEditor.deleteKey,
          expand: true,
          label: l10n.categoryRuleDelete,
          loading: _deleting,
          onPressed: _delete,
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          expand: true,
          label: l10n.cancelButton,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
