import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/features/category_review/presentation/category_review_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Opens the review with the count of transactions waiting for a category;
/// nothing while the queue is empty, loading or failed.
class CategoryReviewBadge extends ConsumerWidget {
  const new({super.key});

  static const buttonKey = Key('category-review-badge');

  /// Above this the badge reads 99+.
  static const maxShown = 99;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref.watch(categoryReviewControllerProvider).value?.pending ?? 0;
    if (pending == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: buttonKey,
      tooltip: l10n.categoryReviewPending(pending),
      onPressed: () => context.push(AppRoutes.categoryReview),
      icon: Badge.count(
        count: pending,
        maxCount: maxShown,
        child: const Icon(Symbols.label_important_rounded),
      ),
    );
  }
}
