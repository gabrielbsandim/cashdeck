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
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/insights/cd_calendar_month.dart';
import 'package:cashdeck/core/widgets/insights/cd_comparison_pill.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_options_sheet.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/insights/application/insights_use_cases.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

class SubscriptionsScreen extends ConsumerWidget {
  const new({super.key});

  static const listKey = Key('subscriptions-view-list');
  static const calendarKey = Key('subscriptions-view-calendar');
  static const confirmKey = Key('subscriptions-confirm');
  static const dismissKey = Key('subscriptions-dismiss');
  static const removeKey = Key('subscriptions-remove');
  static Key rowKey(String key) => Key('subscriptions-row-$key');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.subscriptionsTitle)),
      body: switch (ref.watch(subscriptionsControllerProvider)) {
        AsyncData(:final value)
            when value.items.isEmpty && value.suggestions.isEmpty =>
          CdEmptyState(
            icon: Symbols.autorenew_rounded,
            title: l10n.subscriptionsEmpty,
            message: l10n.subscriptionsEmptyMessage,
          ),
        AsyncData(:final value) => _Subscriptions(subscriptions: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(subscriptionsControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _Subscriptions extends ConsumerStatefulWidget {
  const new({required this.subscriptions});

  final Subscriptions subscriptions;

  @override
  ConsumerState<_Subscriptions> createState() => _SubscriptionsState();
}

class _SubscriptionsState extends ConsumerState<_Subscriptions> {
  bool _calendar = false;
  CalendarDate? _day;
  bool _busy = false;

  Future<void> _decide(
    Subscription suggestion,
    SubscriptionDecision decision,
  ) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final failure = await ref
        .read(subscriptionsControllerProvider.notifier)
        .decide(suggestion, decision);
    if (!mounted) return;
    setState(() => _busy = false);
    await showOutcomeToast(
      context,
      failure,
      success: switch (decision) {
        SubscriptionDecision.confirm => l10n.subscriptionsConfirmed,
        SubscriptionDecision.dismiss => l10n.subscriptionsDismissed,
      },
    );
  }

  Future<void> _options(Subscription subscription) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showOptionsSheet<bool>(
      context,
      title: subscription.name,
      options: [
        PickerOption(
          value: true,
          label: l10n.subscriptionsRemove,
          icon: Symbols.delete_rounded,
          key: SubscriptionsScreen.removeKey,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    final failure = await ref
        .read(subscriptionsControllerProvider.notifier)
        .remove(subscription);
    if (!mounted) return;
    await showOutcomeToast(
      context,
      failure,
      success: l10n.subscriptionsRemoved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    final subscriptions = widget.subscriptions;
    final change = subscriptions.changePercent;
    final day = _day ?? today;
    final items = _calendar
        ? [
            for (final item in subscriptions.items)
              if (item.dayOfMonth == day.day) item,
          ]
        : subscriptions.items;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        CdInsightCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  CdAmount(
                    subscriptions.monthly,
                    size: CdAmountSize.xl,
                    textAlign: TextAlign.start,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    l10n.subscriptionsPerMonth,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.subscriptionsPerYear(
                        MoneyFormat.whole(subscriptions.yearly, hide: hide),
                      ),
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (change != null)
                    CdComparisonPill(
                      direction: change.sign,
                      value: l10n.insightsPercent(change.abs()),
                    ),
                ],
              ),
            ],
          ),
        ),
        for (final suggestion in subscriptions.suggestions) ...[
          const SizedBox(height: AppSpacing.md),
          CdInsightCard(
            title: l10n.subscriptionsSuggestionTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.subscriptionsSuggestionBody(
                    suggestion.name,
                    MoneyFormat.format(suggestion.amount, hide: hide),
                    suggestion.dayOfMonth,
                  ),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: CdButton.outlined(
                        key: SubscriptionsScreen.dismissKey,
                        label: l10n.subscriptionsDismiss,
                        onPressed: _busy
                            ? null
                            : () => _decide(
                                suggestion,
                                SubscriptionDecision.dismiss,
                              ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: CdButton.filled(
                        key: SubscriptionsScreen.confirmKey,
                        label: l10n.subscriptionsConfirm,
                        loading: _busy,
                        onPressed: _busy
                            ? null
                            : () => _decide(
                                suggestion,
                                SubscriptionDecision.confirm,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        CdSegmented<bool>(
          segments: [
            CdSegment(
              false,
              l10n.subscriptionsList,
              key: SubscriptionsScreen.listKey,
            ),
            CdSegment(
              true,
              l10n.subscriptionsCalendar,
              key: SubscriptionsScreen.calendarKey,
            ),
          ],
          selected: _calendar,
          onChanged: (calendar) => setState(() => _calendar = calendar),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_calendar) ...[
          CdCalendarMonth(
            month: YearMonth.of(today),
            weekdays: weekdayInitials(l10n),
            today: today,
            selected: day,
            dots: {
              for (final item in subscriptions.items)
                item.dayOfMonth: [_statusColor(context, item.thisMonth)],
            },
            onSelect: (date) => setState(() => _day = date),
          ),
          const SizedBox(height: AppSpacing.md),
          if (items.isEmpty)
            Text(
              l10n.subscriptionsNoneOnDay,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
        ],
        for (final item in items) _row(l10n, item, hide: hide),
      ],
    );
  }

  Widget _row(AppLocalizations l10n, Subscription item, {required bool hide}) {
    final previous = item.previousAmount;
    return CdListRow(
      key: SubscriptionsScreen.rowKey(item.key),
      title: item.name,
      subtitle: [
        l10n.subscriptionsDay(item.dayOfMonth),
        _statusLabel(l10n, item.thisMonth),
        if (item.priceChanged && previous != null)
          l10n.subscriptionsPriceUp(MoneyFormat.format(previous, hide: hide)),
      ].join(' · '),
      icon: Symbols.autorenew_rounded,
      padding: EdgeInsets.zero,
      trailing: CdAmount(item.amount, size: CdAmountSize.row),
      onTap: () => _options(item),
    );
  }
}

String _statusLabel(AppLocalizations l10n, SubscriptionMonthStatus status) =>
    switch (status) {
      SubscriptionMonthStatus.paid => l10n.subscriptionsPaid,
      SubscriptionMonthStatus.upcoming => l10n.subscriptionsUpcoming,
      SubscriptionMonthStatus.late => l10n.subscriptionsLate,
    };

Color _statusColor(BuildContext context, SubscriptionMonthStatus status) =>
    switch (status) {
      SubscriptionMonthStatus.paid => context.money.paid,
      SubscriptionMonthStatus.upcoming => context.money.scheduled,
      SubscriptionMonthStatus.late => context.money.overdue,
    };
