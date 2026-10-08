import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/money/cd_bill_card.dart';
import 'package:cashdeck/features/automation/presentation/automation_controller.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/presentation/home_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The scroll every Início variant shares: gutters and section gaps.
class HomeScroll extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sectionGap),
          child,
        ],
      ],
    );
  }
}

CalendarDate homeToday(WidgetRef ref) =>
    CalendarDate.brazilToday(ref.watch(clockProvider).now());

/// The kill switch banner, shown on every entity while payments are paused.
class PausedBanner extends ConsumerWidget {
  const new({super.key});

  static const resumeKey = Key('home-resume');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final since = ref.watch(automationControllerProvider).value?.pausedSince;
    if (since == null) return const SizedBox.shrink();
    final waiting = ref.watch(billsNeedingYouCountProvider);
    return CdInlineBanner(
      tone: MoneyTone.pending,
      icon: Symbols.pause_circle_rounded,
      title: l10n.automationPausedTitle,
      message: l10n.automationPausedBody(
        CalendarDate.brazilToday(since).dayMonth,
        waiting,
      ),
      actionLabel: l10n.resumeButton,
      actionKey: resumeKey,
      onAction: () async {
        final failure = await ref
            .read(automationControllerProvider.notifier)
            .setPaused(paused: false);
        if (failure == null || !context.mounted) return;
        await showCdToast(context, message: failure.userMessage(l10n));
      },
    );
  }
}

/// The big balance, what feeds it and how fresh it is.
class BalanceHeader extends ConsumerWidget {
  const new({
    required this.label,
    required this.balance,
    required this.syncLine,
    super.key,
  });

  final String label;
  final Money balance;
  final String? syncLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final syncLine = this.syncLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMd.copyWith(color: palette.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        CdAmount(balance, size: CdAmountSize.xl, textAlign: TextAlign.start),
        if (syncLine != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(
                Symbols.cloud_done_rounded,
                size: 16,
                color: context.money.income,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  syncLine,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String syncAgo(WidgetRef ref, SyncInfo sync) =>
    '${ref.watch(clockProvider).now().difference(sync.syncedAt).inMinutes}';

/// Bills due in the next seven days, overdue ones included, in one card.
class DueSoonSection extends StatelessWidget {
  const new({
    required this.bills,
    required this.today,
    this.title,
    this.showEntity = false,
    this.actionLabel,
    super.key,
  });

  static const seeAllKey = Key('home-due-see-all');

  final List<Bill> bills;
  final CalendarDate today;
  final String? title;
  final bool showEntity;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final total = bills.fold(const Money(0), (sum, bill) => sum + bill.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdSectionHeader(
          title: title ?? l10n.dueIn7Days,
          subtitle: bills.isEmpty
              ? null
              : CdPrivateText(
                  (hide) => l10n.dueSummary(
                    MoneyFormat.format(total, hide: hide),
                    bills.length,
                  ),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
          actionLabel: actionLabel ?? l10n.seeAllButton,
          actionKey: seeAllKey,
          onAction: () => context.go(AppRoutes.bills),
        ),
        const SizedBox(height: AppSpacing.md),
        if (bills.isEmpty)
          Text(
            l10n.dueNothing,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        if (bills.isNotEmpty)
          CdCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (index, bill) in bills.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  _DueRow(bill: bill, today: today, showEntity: showEntity),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DueRow extends StatelessWidget {
  const new({
    required this.bill,
    required this.today,
    required this.showEntity,
  });

  final Bill bill;
  final CalendarDate today;
  final bool showEntity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, tone) = billHomeStatusOf(l10n, bill, today);
    final date = bill.isOverdue(today)
        ? l10n.billOverdueShort(bill.dueDate.dayMonth)
        : bill.dueDate.dayMonth;
    return CdBillRow(
      key: Key('home-bill-${bill.id}'),
      icon: billIconOf(bill),
      title: bill.payee,
      amount: bill.amount,
      dateLabel: showEntity ? null : date,
      leading: showEntity ? EntityKindBadge(kind: bill.owner) : null,
      status: Align(
        alignment: Alignment.centerLeft,
        child: CdStatusBadge(tone: tone, label: label),
      ),
      onTap: () => context.go(AppRoutes.bill(bill.id)),
    );
  }
}

/// One Início alert: a bill that moved to step 3, or a budget past its limit.
class HomeAlertRow extends ConsumerWidget {
  const new({required this.alert, super.key});

  final HomeAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final today = homeToday(ref);
    final when = relativeDay(l10n, CalendarDate.brazilToday(alert.at), today);
    final (icon, tone, title, subtitle, onTap) = switch (alert) {
      AssistedPaymentAlert(:final payee, :final reason, :final billId) => (
        Symbols.verified_user_rounded,
        MoneyTone.assisted,
        l10n.alertAssistedTitle(payee),
        (bool _) => reason,
        () => context.go(AppRoutes.bill(billId)),
      ),
      BudgetExceededAlert(:final budget) => (
        Symbols.error_rounded,
        MoneyTone.failed,
        l10n.alertBudgetTitle(budgetCategoryLabel(l10n, budget.category)),
        (bool hide) => l10n.alertBudgetBody(
          MoneyFormat.whole(budget.spent, hide: hide),
          MoneyFormat.whole(budget.limit, hide: hide),
          when,
        ),
        null,
      ),
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            CdIconTile(icon, tone: context.tone(tone)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.titleSm.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  CdPrivateText(
                    subtitle,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
