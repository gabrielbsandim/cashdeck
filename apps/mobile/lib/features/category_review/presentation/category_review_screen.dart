import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_controller.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_labels.dart';
import 'package:cashdeck/features/category_review/presentation/review_group_card.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Revisar categorias: rule suggestions first, then the merchants waiting
/// for a category, largest first.
class CategoryReviewScreen extends ConsumerWidget {
  const new({super.key});

  static const rulesKey = Key('category-review-rules');

  static Key groupKey(String id) => Key('review-group-$id');
  static Key acceptKey(String id) => Key('review-accept-$id');
  static Key dismissKey(String id) => Key('review-dismiss-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final queue = ref.watch(categoryReviewControllerProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.categoryReviewTitle),
        actions: [
          IconButton(
            key: rulesKey,
            tooltip: l10n.categoryRulesTitle,
            onPressed: () => context.push(AppRoutes.categoryRules),
            icon: const Icon(Symbols.rule_settings_rounded),
          ),
        ],
      ),
      body: switch (queue) {
        AsyncData(:final value) when value.isEmpty => CdEmptyState(
          icon: Symbols.celebration_rounded,
          title: l10n.categoryReviewDoneTitle,
          message: l10n.categoryReviewDoneMessage,
        ),
        AsyncData(:final value) => _QueueList(
          queue: value,
          categories: categories,
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(categoryReviewControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _QueueList extends ConsumerWidget {
  const new({required this.queue, required this.categories});

  final ReviewQueue queue;
  final List<Category> categories;

  Future<bool> _categorize(
    BuildContext context,
    WidgetRef ref,
    ReviewGroup group,
    String categoryId, {
    required bool createRule,
  }) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(categoryReviewControllerProvider.notifier)
        .categorize(group, categoryId, createRule: createRule);
    if (!context.mounted) return result is Ok;
    switch (result) {
      case Ok(:final value):
        final count = value.updated + value.similarUpdated;
        unawaited(
          showCdToast(
            context,
            icon: Symbols.task_alt_rounded,
            message: value.rule == null
                ? l10n.categoryReviewSaved(count)
                : l10n.categoryReviewSavedRule(count),
          ),
        );
        return true;
      case Err(:final failure):
        unawaited(
          showCdToast(
            context,
            icon: Symbols.error_rounded,
            message: failure.userMessage(l10n),
          ),
        );
        return false;
    }
  }

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    RuleSuggestion suggestion,
  ) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(categoryReviewControllerProvider.notifier)
        .accept(suggestion);
    if (!context.mounted) return;
    await showOutcomeToast(context, switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    }, success: l10n.categoryReviewRuleCreated);
  }

  Future<void> _dismiss(
    BuildContext context,
    WidgetRef ref,
    RuleSuggestion suggestion,
  ) async {
    final failure = await ref
        .read(categoryReviewControllerProvider.notifier)
        .dismiss(suggestion);
    if (failure == null || !context.mounted) return;
    await showOutcomeToast(context, failure, success: '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        if (queue.suggestions.isNotEmpty) ...[
          CdSectionHeader(title: l10n.categoryReviewSuggestionsHeader),
          for (final suggestion in queue.suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _SuggestionCard(
                suggestion: suggestion,
                categories: categories,
                onAccept: () => _accept(context, ref, suggestion),
                onDismiss: () => _dismiss(context, ref, suggestion),
              ),
            ),
        ],
        if (queue.groups.isNotEmpty)
          CdSectionHeader(
            title: l10n.categoryReviewGroupsHeader,
            subtitle: Text(l10n.categoryReviewTransactions(queue.pending)),
          ),
        for (final group in queue.groups)
          Padding(
            key: CategoryReviewScreen.groupKey(group.id),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ReviewGroupCard(
              group: group,
              categories: categories,
              onConfirm: (categoryId, {required createRule}) => _categorize(
                context,
                ref,
                group,
                categoryId,
                createRule: createRule,
              ),
              onSkip: () => ref
                  .read(categoryReviewControllerProvider.notifier)
                  .skip(group),
            ),
          ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const new({
    required this.suggestion,
    required this.categories,
    required this.onAccept,
    required this.onDismiss,
  });

  final RuleSuggestion suggestion;
  final List<Category> categories;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.categoryReviewSuggestionTitle(
              categoryLabel(l10n, suggestion.categoryId, categories),
              suggestion.merchant,
            ),
            style: AppTextStyles.titleMd,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.categoryReviewSuggestionBody(suggestion.count),
            style: AppTextStyles.bodyMd.copyWith(
              color: context.palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              CdButton.text(
                key: CategoryReviewScreen.dismissKey(suggestion.id),
                label: l10n.categoryReviewSuggestionDismiss,
                dense: true,
                onPressed: onDismiss,
              ),
              CdButton.tonal(
                key: CategoryReviewScreen.acceptKey(suggestion.id),
                label: l10n.categoryReviewSuggestionAccept,
                icon: Symbols.bolt_rounded,
                dense: true,
                onPressed: onAccept,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
