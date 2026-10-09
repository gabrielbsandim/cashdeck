import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_bill_card.dart';
import 'package:cashdeck/core/widgets/money/privacy_toggle.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class BillsScreen extends ConsumerWidget {
  const new({super.key});

  static Key tileKey(String billId) => Key('bill-$billId');
  static const pasteKey = Key('bills-paste');
  static const loadMoreKey = Key('bills-load-more');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bills = ref.watch(billsControllerProvider);
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.billsTitle),
        actions: const [PrivacyToggle()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: BillsScreen.pasteKey,
        icon: const Icon(Symbols.content_paste_rounded),
        label: Text(l10n.pasteCodeButton),
        onPressed: () => context.push(AppRoutes.pasteCode).ignore(),
      ),
      body: Column(
        children: [
          const EntitySwitcher(),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: switch (bills) {
              AsyncData(:final value) when value.bills.isEmpty => CdEmptyState(
                icon: Symbols.receipt_long_rounded,
                title: l10n.billsEmptyTitle,
                message: l10n.billsEmptyMessage,
              ),
              AsyncData(:final value) => _BillList(
                listing: value,
                today: today,
              ),
              AsyncError(:final error) => CdErrorState(
                failure: failureOf(error),
                onRetry: () => ref.invalidate(billsControllerProvider),
              ),
              _ => const CdSkeleton(),
            },
          ),
        ],
      ),
    );
  }
}

class _BillList extends ConsumerWidget {
  const new({required this.listing, required this.today});

  final BillsListing listing;
  final CalendarDate today;

  /// Starts the next page this far before the end, so scrolling rarely
  /// waits on it.
  static const _prefetch = 600.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(billsControllerProvider.notifier);
    final bills = listing.bills;
    final needing = billsNeedingYou(bills, today);
    final settled = bills.where((bill) => bill.isSettled).toList();
    final upcoming = bills
        .where((bill) => !bill.isSettled && !needing.contains(bill))
        .toList();
    final groups = [
      (l10n.billsGroupNeedsYou, needing),
      (l10n.billsGroupUpcoming, upcoming),
      (l10n.billsGroupSettled, settled),
    ];
    final failure = listing.moreFailure;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < _prefetch) {
          controller.loadMore().ignore();
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sm,
          AppSpacing.screenGutter,
          AppSpacing.xxl * 2,
        ),
        children: [
          for (final (title, group) in groups)
            if (group.isNotEmpty) ...[
              CdSectionHeader(title: title, small: true),
              const SizedBox(height: AppSpacing.sm),
              for (final bill in group) ...[
                BillTile(bill: bill, today: today),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          if (failure != null)
            Text(
              failure.userMessage(l10n),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: context.palette.onSurfaceVariant,
              ),
            ),
          if (listing.hasMore)
            Center(
              child: listing.loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: CircularProgressIndicator(),
                    )
                  : CdButton.text(
                      key: BillsScreen.loadMoreKey,
                      label: l10n.billsLoadMore,
                      onPressed: () => controller.loadMore().ignore(),
                    ),
            ),
        ],
      ),
    );
  }
}

class BillTile extends ConsumerWidget {
  const new({required this.bill, required this.today, super.key});

  final Bill bill;
  final CalendarDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final (label, tone) = billStatusOf(l10n, bill, today);
    final consolidated =
        ref.watch(entityScopeProvider) == EntityScope.consolidated;
    final title = consolidated
        ? l10n.billTitleWithEntity(bill.payee, entityShortLabel(l10n, bill))
        : bill.payee;
    return CdBillCard(
      key: BillsScreen.tileKey(bill.id),
      icon: billIconOf(bill),
      title: title,
      dueLabel: billDueLabel(l10n, bill, today),
      amount: bill.amount,
      status: CdStatusBadge(tone: tone, label: label),
      ladderHint: billLadderHint(l10n, bill),
      onTap: () => context.go(AppRoutes.bill(bill.id)),
    );
  }
}

String entityShortLabel(AppLocalizations l10n, Bill bill) =>
    switch (bill.owner) {
      EntityKind.personal => l10n.entityPersonalShort,
      EntityKind.company => l10n.entityCompanyShort,
    };
