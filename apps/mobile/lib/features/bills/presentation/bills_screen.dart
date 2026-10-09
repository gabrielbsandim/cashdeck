import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/app/shell/tab_app_bar.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/insights/cd_calendar_month.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/insights/cd_segment_bar.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_bill_card.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
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
      appBar: const TabAppBar(),
      floatingActionButton: FloatingActionButton.extended(
        key: BillsScreen.pasteKey,
        icon: const Icon(Symbols.content_paste_rounded),
        label: Text(l10n.pasteCodeButton),
        onPressed: () => context.push(AppRoutes.pasteCode).ignore(),
      ),
      body: Column(
        children: [
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

class _BillList extends ConsumerStatefulWidget {
  const new({required this.listing, required this.today});

  final BillsListing listing;
  final CalendarDate today;

  @override
  ConsumerState<_BillList> createState() => _BillListState();
}

class _BillListState extends ConsumerState<_BillList> {
  CalendarDate? _day;

  /// Starts the next page this far before the end, so scrolling rarely
  /// waits on it.
  static const _prefetch = 600.0;

  /// The extended FAB and its margin, so the last bill scrolls clear of it.
  static const double _fabClearance = 56.0 + AppSpacing.lg + AppSpacing.xl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = context.money;
    final controller = ref.read(billsControllerProvider.notifier);
    final listing = widget.listing;
    final today = widget.today;
    final day = _day;
    final all = listing.bills;
    final month = YearMonth.of(today);
    final allNeeding = billsNeedingYou(all, today);
    Color dotOf(Bill bill) => switch (bill) {
      _ when bill.isSettled => money.paid,
      _ when allNeeding.contains(bill) => money.overdue,
      _ when bill.awaitsBankDebit(today) => money.pending,
      _ => money.scheduled,
    };
    final dots = <int, List<Color>>{};
    for (final bill in all) {
      if (!month.contains(bill.dueDate)) continue;
      dots.putIfAbsent(bill.dueDate.day, () => []).add(dotOf(bill));
    }
    final bills = day == null
        ? all
        : [
            for (final bill in all)
              if (bill.dueDate == day) bill,
          ];
    final needing = billsNeedingYou(bills, today);
    final settled = bills.where((bill) => bill.isSettled).toList();
    final debiting = bills
        .where((bill) => bill.awaitsBankDebit(today))
        .toList();
    final upcoming = bills
        .where(
          (bill) =>
              !bill.isSettled &&
              !needing.contains(bill) &&
              !debiting.contains(bill),
        )
        .toList();
    final groups = [
      (l10n.billsGroupNeedsYou, needing),
      (l10n.billsGroupUpcoming, upcoming),
      (l10n.billsGroupAwaitingDebit, debiting),
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
          _fabClearance,
        ),
        children: [
          CdInsightCard(
            title: monthTitle(l10n, month),
            actionLabel: day == null ? null : l10n.billsCalendarClear,
            onAction: () => setState(() => _day = null),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CdCalendarMonth(
                  month: month,
                  weekdays: weekdayInitials(l10n),
                  today: today,
                  selected: day,
                  dots: dots,
                  onSelect: (date) =>
                      setState(() => _day = date == day ? null : date),
                ),
                const SizedBox(height: AppSpacing.sm),
                CdSegmentLegend(
                  entries: [
                    (money.overdue, l10n.billsLegendNeedsYou),
                    (money.scheduled, l10n.billsLegendUpcoming),
                    (money.pending, l10n.billsLegendDebit),
                    (money.paid, l10n.billsLegendPaid),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (day != null && bills.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Text(
                l10n.billsNoneOnDay,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(
                  color: context.palette.onSurfaceVariant,
                ),
              ),
            ),
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
        ? l10n.billTitleWithEntity(
            billPayeeOf(l10n, bill),
            entityShortLabel(l10n, bill),
          )
        : billPayeeOf(l10n, bill);
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
