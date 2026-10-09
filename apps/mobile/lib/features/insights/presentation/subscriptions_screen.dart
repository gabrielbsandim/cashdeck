import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
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
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/insights/application/insights_use_cases.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/insights/presentation/subscription_widgets.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class SubscriptionsScreen extends ConsumerWidget {
  const new({super.key});

  static const listKey = Key('subscriptions-view-list');
  static const calendarKey = Key('subscriptions-view-calendar');
  static Key confirmKey(String key) => Key('subscriptions-confirm-$key');
  static Key dismissKey(String key) => Key('subscriptions-dismiss-$key');
  static Key suggestionKey(String key) => Key('subscriptions-suggestion-$key');
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

  /// The decision each suggestion waits on, by key, so only its own buttons
  /// spin while the others stay usable.
  final Map<String, SubscriptionDecision> _pending = {};

  Future<void> _decide(
    Subscription suggestion,
    SubscriptionDecision decision,
  ) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _pending[suggestion.key] = decision);
    final failure = await ref
        .read(subscriptionsControllerProvider.notifier)
        .decide(suggestion, decision);
    if (!mounted) return;
    setState(() => _pending.remove(suggestion.key));
    await showOutcomeToast(
      context,
      failure,
      success: switch (decision) {
        SubscriptionDecision.confirm => l10n.subscriptionsConfirmed,
        SubscriptionDecision.dismiss => l10n.subscriptionsDismissed,
      },
    );
  }

  void _open(Subscription subscription) =>
      context.push(AppRoutes.subscription(subscription.key));

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
                      [
                        l10n.subscriptionsCount(subscriptions.items.length),
                        l10n.subscriptionsPerYear(
                          MoneyFormat.whole(subscriptions.yearly, hide: hide),
                        ),
                      ].join(' · '),
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
          _suggestion(l10n, suggestion, hide: hide),
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
                item.dayOfMonth: [
                  subscriptionStatusColor(context, item.thisMonth),
                ],
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

  Widget _suggestion(
    AppLocalizations l10n,
    Subscription suggestion, {
    required bool hide,
  }) {
    final pending = _pending[suggestion.key];
    final busy = pending != null;
    return CdInsightCard(
      key: SubscriptionsScreen.suggestionKey(suggestion.key),
      title: l10n.subscriptionsSuggestionTitle,
      onTap: () => _open(suggestion),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SubscriptionAvatar(subscription: suggestion),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.subscriptionsSuggestionBody(
                    suggestion.name,
                    MoneyFormat.format(suggestion.amount, hide: hide),
                    suggestion.dayOfMonth,
                  ),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: context.palette.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: CdButton.outlined(
                  key: SubscriptionsScreen.dismissKey(suggestion.key),
                  expand: true,
                  label: l10n.subscriptionsDismiss,
                  loading: pending == SubscriptionDecision.dismiss,
                  onPressed: busy
                      ? null
                      : () => _decide(suggestion, SubscriptionDecision.dismiss),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: CdButton.filled(
                  key: SubscriptionsScreen.confirmKey(suggestion.key),
                  expand: true,
                  label: l10n.subscriptionsConfirm,
                  loading: pending == SubscriptionDecision.confirm,
                  onPressed: busy
                      ? null
                      : () => _decide(suggestion, SubscriptionDecision.confirm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(AppLocalizations l10n, Subscription item, {required bool hide}) =>
      CdListRow(
        key: SubscriptionsScreen.rowKey(item.key),
        title: item.name,
        titleMaxLines: 1,
        subtitle: subscriptionSubtitle(l10n, item, hide: hide),
        leading: SubscriptionAvatar(subscription: item),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        trailing: CdAmount(item.amount, size: CdAmountSize.row),
        onTap: () => _open(item),
      );
}
