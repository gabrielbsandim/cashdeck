import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_filter_chip.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_options_sheet.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_labels.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef GroupDecision = Future<bool> Function(
  String categoryId, {
  required bool createRule,
});

/// One merchant waiting for a category: the guess comes preselected, the
/// rule toggle starts on. Swiping right confirms, left skips.
class ReviewGroupCard extends StatefulWidget {
  const new({
    required this.group,
    required this.categories,
    required this.onConfirm,
    required this.onSkip,
    super.key,
  });

  final ReviewGroup group;
  final List<Category> categories;

  /// True when the server took the choice.
  final GroupDecision onConfirm;
  final VoidCallback onSkip;

  static Key categoryKey(String id) => Key('review-category-$id');
  static Key ruleKey(String id) => Key('review-rule-$id');
  static Key confirmKey(String id) => Key('review-confirm-$id');
  static Key skipKey(String id) => Key('review-skip-$id');
  static Key optionKey(String id) => Key('review-option-$id');

  @override
  State<ReviewGroupCard> createState() => _ReviewGroupCardState();
}

class _ReviewGroupCardState extends State<ReviewGroupCard> {
  late String? _categoryId = widget.group.suggestedCategoryId;
  var _createRule = true;
  var _saving = false;

  ReviewGroup get _group => widget.group;

  Future<bool> _confirm() async {
    final categoryId = _categoryId;
    if (categoryId == null || _saving) return false;
    setState(() => _saving = true);
    final done = await widget.onConfirm(
      categoryId,
      createRule: _createRule && _group.canCreateRule,
    );
    if (mounted) setState(() => _saving = false);
    return done;
  }

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showOptionsSheet<Category>(
      context,
      title: l10n.categoryReviewPickCategory,
      options: [
        for (final category in widget.categories)
          PickerOption(
            value: category,
            label: categoryName(l10n, category),
            key: ReviewGroupCard.optionKey(category.id),
            icon: categoryIcon(category),
            selected: category.id == _categoryId,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _categoryId = picked.$1.id);
  }

  Future<bool> _swiped(DismissDirection direction) {
    if (direction == DismissDirection.startToEnd) return _confirm();
    widget.onSkip();
    return Future.value(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final selected = categoryById(_categoryId, widget.categories);
    return Dismissible(
      key: ValueKey('review-swipe-${_group.id}'),
      confirmDismiss: _swiped,
      background: _SwipeHint(
        icon: Symbols.check_rounded,
        label: l10n.categoryReviewConfirm,
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _SwipeHint(
        icon: Symbols.skip_next_rounded,
        label: l10n.categoryReviewSkip,
        alignment: Alignment.centerRight,
      ),
      child: CdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _group.merchant,
                        style: AppTextStyles.titleMd,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        l10n.categoryReviewLastOn(
                          l10n.categoryReviewTransactions(_group.count),
                          _group.lastBookedOn.dayMonth,
                        ),
                        style: AppTextStyles.bodyMd.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                CdAmount(
                  _group.total,
                  size: CdAmountSize.row,
                  kind: _group.direction == FlowDirection.incoming
                      ? CdAmountKind.income
                      : CdAmountKind.expense,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              reviewReasonsLine(l10n, _group),
              style: AppTextStyles.bodyMd.copyWith(
                fontSize: 12,
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: CdFilterChip(
                key: ReviewGroupCard.categoryKey(_group.id),
                label: selected == null
                    ? l10n.categoryReviewPickCategory
                    : categoryName(l10n, selected),
                icon: categoryIcon(selected),
                selected: selected != null,
                dropdown: true,
                onTap: _saving ? null : _pick,
              ),
            ),
            if (_group.canCreateRule) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.categoryReviewAlwaysRule,
                          style: AppTextStyles.bodyLg,
                        ),
                        Text(
                          l10n.categoryReviewAlwaysRuleHint(
                            _group.pattern.isEmpty
                                ? _group.merchant
                                : _group.pattern,
                          ),
                          style: AppTextStyles.bodyMd.copyWith(
                            fontSize: 12,
                            color: palette.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    key: ReviewGroupCard.ruleKey(_group.id),
                    value: _createRule,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _createRule = value),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                CdButton.text(
                  key: ReviewGroupCard.skipKey(_group.id),
                  label: l10n.categoryReviewSkip,
                  dense: true,
                  onPressed: _saving ? null : widget.onSkip,
                ),
                CdButton.filled(
                  key: ReviewGroupCard.confirmKey(_group.id),
                  label: l10n.categoryReviewConfirm,
                  icon: Symbols.check_rounded,
                  dense: true,
                  loading: _saving,
                  onPressed: selected == null ? null : _confirm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const new({required this.icon, required this.label, required this.alignment});

  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: palette.onPrimaryContainer),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTextStyles.labelLg.copyWith(
              color: palette.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
