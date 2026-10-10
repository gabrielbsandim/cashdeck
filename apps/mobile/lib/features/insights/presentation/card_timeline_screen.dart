import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/inputs/cd_filter_chip.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/money/cd_transaction_row.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/home/presentation/account_rename_sheet.dart';
import 'package:cashdeck/features/insights/domain/card_timeline.dart';
import 'package:cashdeck/features/insights/presentation/cards_screen.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// One card's bills side by side, oldest to the left: it opens on the open
/// bill, swipes back to the closed ones and ahead to the forecast ones.
class CardTimelineScreen extends ConsumerWidget {
  const new({required this.accountId, super.key});

  final String accountId;

  static const pagesKey = Key('card-timeline-pages');
  static const previousKey = Key('card-timeline-previous');
  static const nextKey = Key('card-timeline-next');
  static const renameKey = Key('card-timeline-rename');
  static Key monthKey(int index) => Key('card-timeline-month-$index');
  static Key billKey(int index) => Key('card-timeline-bill-$index');
  static Key installmentKey(String key) =>
      Key('card-timeline-installment-$key');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final timeline = ref.watch(cardTimelineProvider(accountId));
    final account = ref
        .watch(transactionAccountsProvider)
        .value
        ?.where((item) => item.id == accountId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(l10n, timeline.value, account)),
        actions: [
          if (account != null)
            IconButton(
              key: renameKey,
              tooltip: l10n.cardTimelineRename,
              onPressed: () => renameAccount(context, ref, account).ignore(),
              icon: const Icon(Symbols.edit_rounded),
            ),
        ],
      ),
      body: switch (timeline) {
        AsyncData(:final value) when value.bills.isEmpty => CdEmptyState(
          icon: Symbols.receipt_long_rounded,
          title: l10n.cardsBills,
          message: l10n.cardsNoBills,
        ),
        AsyncData(:final value) => _Timeline(timeline: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(cardTimelineProvider(accountId)),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

String _title(
  AppLocalizations l10n,
  CardTimeline? timeline,
  TransactionAccount? account,
) {
  final name = account?.name ?? timeline?.name;
  if (name == null) return l10n.cardsTitle;
  final suffix = timeline?.suffix ?? account?.numberSuffix;
  if (suffix == null || name.contains(suffix)) return name;
  return '$name •• $suffix';
}

String _stateLabel(AppLocalizations l10n, TimelineBillState state) =>
    switch (state) {
      TimelineBillState.past => l10n.cardsStatePast,
      TimelineBillState.closed => l10n.cardsStateClosed,
      TimelineBillState.open => l10n.cardsStateOpen,
      TimelineBillState.forecast => l10n.cardsStateForecast,
    };

/// `out`, or `jan 27` once the bills leave this year.
String _monthChip(AppLocalizations l10n, YearMonth month, int year) {
  final short = shortMonth(l10n, month);
  return month.year == year ? short : '$short ${month.year % 100}';
}

String _billTitle(AppLocalizations l10n, YearMonth month, int year) {
  final name = monthName(l10n, month);
  return l10n.cardsBillOf(month.year == year ? name : '$name ${month.year}');
}

class _Timeline extends ConsumerStatefulWidget {
  const new({required this.timeline});

  final CardTimeline timeline;

  @override
  ConsumerState<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends ConsumerState<_Timeline> {
  static const _chipWidth = 72.0;

  late final PageController _pages = PageController(
    initialPage: widget.timeline.start,
  );
  late final ScrollController _months = ScrollController(
    initialScrollOffset: widget.timeline.start * _chipWidth,
  );
  late int _page = widget.timeline.start;

  @override
  void dispose() {
    _pages.dispose();
    _months.dispose();
    super.dispose();
  }

  void _go(int page) => _pages
      .animateToPage(page, duration: AppMotion.slow, curve: AppMotion.standard)
      .ignore();

  void _onPage(int page) {
    setState(() => _page = page);
    if (!_months.hasClients) return;
    final position = _months.position;
    final centered =
        page * _chipWidth - (position.viewportDimension - _chipWidth) / 2;
    _months
        .animateTo(
          centered.clamp(0, position.maxScrollExtent),
          duration: AppMotion.medium,
          curve: AppMotion.standard,
        )
        .ignore();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final bills = widget.timeline.bills;
    final year = CalendarDate.brazilToday(ref.watch(clockProvider).now()).year;
    final bill = bills[_page];
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView.builder(
            controller: _months,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            itemCount: bills.length,
            itemExtent: _chipWidth,
            itemBuilder: (_, index) => Center(
              child: CdFilterChip(
                key: CardTimelineScreen.monthKey(index),
                label: _monthChip(l10n, YearMonth.of(bills[index].dueOn), year),
                selected: index == _page,
                onTap: () => _go(index),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              IconButton(
                key: CardTimelineScreen.previousKey,
                tooltip: l10n.cardTimelinePrevious,
                onPressed: _page > 0 ? () => _go(_page - 1) : null,
                icon: const Icon(Symbols.chevron_left_rounded),
              ),
              Expanded(
                child: Semantics(
                  label: l10n.cardTimelinePage(_page + 1, bills.length),
                  child: Text(
                    '${_billTitle(l10n, YearMonth.of(bill.dueOn), year)} · '
                    '${_stateLabel(l10n, bill.state)}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleSm.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: CardTimelineScreen.nextKey,
                tooltip: l10n.cardTimelineNext,
                onPressed: _page < bills.length - 1
                    ? () => _go(_page + 1)
                    : null,
                icon: const Icon(Symbols.chevron_right_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            key: CardTimelineScreen.pagesKey,
            controller: _pages,
            onPageChanged: _onPage,
            itemCount: bills.length,
            itemBuilder: (_, index) => _BillPage(
              key: CardTimelineScreen.billKey(index),
              accountId: widget.timeline.accountId,
              bill: bills[index],
            ),
          ),
        ),
      ],
    );
  }
}

class _BillPage extends StatelessWidget {
  const new({required this.accountId, required this.bill, super.key});

  final String accountId;
  final TimelineBill bill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        _BillSummary(bill: bill),
        if (bill.installments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          CdSectionHeader(title: l10n.cardTimelineInstallments, small: true),
          const SizedBox(height: AppSpacing.xs),
          _Installments(installments: bill.installments),
        ],
        const SizedBox(height: AppSpacing.lg),
        CdSectionHeader(title: l10n.cardsCharges, small: true),
        const SizedBox(height: AppSpacing.xs),
        CardBillCharges(charges: (accountId: accountId, range: bill.range)),
      ],
    );
  }
}

class _BillSummary extends ConsumerWidget {
  const new({required this.bill});

  final TimelineBill bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    final muted = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final closes = bill.closesOn?.dayMonth;
    final due = bill.dueOn.dayMonth;
    final dates = switch (bill.state) {
      TimelineBillState.past => l10n.cardsPastDue(due),
      TimelineBillState.closed when closes != null => l10n.cardsClosedDates(
        closes,
        due,
      ),
      _ when closes != null => l10n.cardsBillDates(closes, due),
      _ => l10n.cardsBillDue(due),
    };
    final minimum = bill.minimum;
    return CdInsightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CdAmount(
            bill.total,
            size: CdAmountSize.lg,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(dates, style: muted),
          if (bill.state == TimelineBillState.closed)
            Text(
              l10n.cardsDueIn(today.daysUntil(bill.dueOn)),
              style: AppTextStyles.labelLg.copyWith(
                color: context.money.pending,
              ),
            ),
          if (minimum != null)
            Text(
              l10n.cardTimelineMinimum(MoneyFormat.format(minimum, hide: hide)),
              style: muted,
            ),
          if (bill.payment case final payment?) ...[
            const SizedBox(height: AppSpacing.sm),
            _PaymentTag(payment: payment),
          ],
          if (bill.isForecast) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.query_stats_rounded,
                  size: 16,
                  color: palette.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(l10n.cardTimelineForecastNote, style: muted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentTag extends StatelessWidget {
  const new({required this.payment});

  final BillPayment payment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, icon, color) = switch (payment) {
      BillPayment.paid => (
        l10n.cardTimelinePaid,
        Symbols.check_circle_rounded,
        context.money.paid,
      ),
      BillPayment.due => (
        l10n.cardTimelineDue,
        Symbols.schedule_rounded,
        context.money.pending,
      ),
      BillPayment.unconfirmed => (
        l10n.cardTimelineUnconfirmed,
        Symbols.help_rounded,
        context.palette.onSurfaceVariant,
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.labelLg.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _Installments extends ConsumerWidget {
  const new({required this.installments});

  final List<PlannedInstallment> installments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    return Column(
      children: [
        for (final item in installments)
          CdTransactionRow(
            key: CardTimelineScreen.installmentKey(item.key),
            icon: categoryIcon(
              categories
                  .where((category) => category.id == item.categoryId)
                  .firstOrNull,
            ),
            title: item.name,
            subtitle: '${item.label} · ${l10n.cardsStateForecast}',
            amount: -item.amount,
          ),
      ],
    );
  }
}
