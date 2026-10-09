import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_options_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/insights/application/insights_use_cases.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/insights/presentation/subscription_widgets.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// One subscription, confirmed or suggested: what it costs, when it comes
/// next, how its charges went and where it lands.
class SubscriptionDetailScreen extends ConsumerWidget {
  const new({required this.subscriptionKey, super.key});

  final String subscriptionKey;

  static const confirmKey = Key('subscription-detail-confirm');
  static const dismissKey = Key('subscription-detail-dismiss');
  static const removeKey = Key('subscription-detail-remove');
  static const removeConfirmKey = Key('subscription-detail-remove-confirm');
  static const priceKey = Key('subscription-detail-price');
  static Key chargeKey(String transactionId) =>
      Key('subscription-detail-charge-$transactionId');
  static Key monthKey(YearMonth month) =>
      Key('subscription-detail-month-${month.iso}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(subscriptionsControllerProvider);
    return Scaffold(
      appBar: AppBar(),
      body: switch (state) {
        AsyncValue(:final value?) => switch (_find(value)) {
          final subscription? => _Detail(subscription: subscription),
          null => CdEmptyState(
            icon: Symbols.autorenew_rounded,
            title: l10n.subscriptionsTitle,
            message: l10n.subscriptionDetailNotFound,
          ),
        },
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(subscriptionsControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }

  Subscription? _find(Subscriptions subscriptions) => [
    ...subscriptions.items,
    ...subscriptions.suggestions,
  ].where((item) => item.key == subscriptionKey).firstOrNull;
}

class _Detail extends ConsumerStatefulWidget {
  const new({required this.subscription});

  final Subscription subscription;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

enum _Action { confirm, dismiss, remove }

class _DetailState extends ConsumerState<_Detail> {
  _Action? _pending;

  Future<void> _run(_Action action) async {
    final l10n = AppLocalizations.of(context);
    final subscription = widget.subscription;
    final controller = ref.read(subscriptionsControllerProvider.notifier);
    setState(() => _pending = action);
    final failure = switch (action) {
      _Action.confirm => await controller.decide(
        subscription,
        SubscriptionDecision.confirm,
      ),
      _Action.dismiss => await controller.decide(
        subscription,
        SubscriptionDecision.dismiss,
      ),
      _Action.remove => await controller.remove(subscription),
    };
    if (!mounted) return;
    setState(() => _pending = null);
    final success = switch (action) {
      _Action.confirm => l10n.subscriptionsConfirmed,
      _Action.dismiss => l10n.subscriptionsDismissed,
      _Action.remove => l10n.subscriptionsRemoved,
    };
    unawaited(showOutcomeToast(context, failure, success: success));
    if (failure != null || action == _Action.confirm) return;
    context.pop();
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final choice = await showOptionsSheet<bool>(
      context,
      title: widget.subscription.name,
      options: [
        PickerOption(
          value: true,
          label: l10n.subscriptionsRemove,
          subtitle: l10n.subscriptionDetailRemoveHint,
          icon: Symbols.delete_rounded,
          key: SubscriptionDetailScreen.removeConfirmKey,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    await _run(_Action.remove);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    final subscription = widget.subscription;
    final next = subscription.nextChargeOn;
    final previous = subscription.previousAmount;
    final rose = previous != null && previous.cents < subscription.amount.cents;
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        0,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        Center(child: SubscriptionAvatar(subscription: subscription, size: 64)),
        const SizedBox(height: AppSpacing.md),
        Text(
          subscription.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.titleMd.copyWith(color: palette.onSurface),
        ),
        const SizedBox(height: AppSpacing.xs),
        CdAmount(
          subscription.amount,
          size: CdAmountSize.xl,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            Text(
              l10n.subscriptionsEveryDay(subscription.dayOfMonth),
              style: secondary,
            ),
            CdStatusBadge(
              tone: subscriptionStatusTone(subscription.thisMonth),
              label: subscriptionStatusLabel(l10n, subscription.thisMonth),
            ),
          ],
        ),
        if (subscription.isSuggestion) ...[
          const SizedBox(height: AppSpacing.lg),
          CdInlineBanner(
            icon: Symbols.auto_awesome_rounded,
            title: l10n.subscriptionsSuggestionTitle,
            message: l10n.subscriptionDetailSuggestionHint,
          ),
        ],
        if (subscription.priceChanged && previous != null) ...[
          const SizedBox(height: AppSpacing.lg),
          CdInlineBanner(
            key: SubscriptionDetailScreen.priceKey,
            icon: rose
                ? Symbols.trending_up_rounded
                : Symbols.trending_down_rounded,
            tone: rose ? MoneyTone.overdue : MoneyTone.paid,
            title: rose
                ? l10n.subscriptionDetailPriceUp
                : l10n.subscriptionDetailPriceDown,
            message: l10n.subscriptionDetailPriceChange(
              MoneyFormat.format(previous, hide: hide),
              MoneyFormat.format(subscription.amount, hide: hide),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        CdCard(
          child: Column(
            children: [
              if (next != null)
                CdKeyValueRow(
                  label: l10n.subscriptionDetailNext,
                  strong: true,
                  value: Text(next.display),
                ),
              CdKeyValueRow(
                label: l10n.subscriptionDetailMonthly,
                value: CdAmount(subscription.amount, size: CdAmountSize.row),
              ),
              CdKeyValueRow(
                label: l10n.subscriptionDetailYearly,
                value: CdAmount(subscription.yearly, size: CdAmountSize.row),
              ),
              if (subscription.charges.isNotEmpty)
                CdKeyValueRow(
                  label: l10n.subscriptionDetailSpent(
                    subscription.charges.length,
                  ),
                  value: CdAmount(subscription.spent, size: CdAmountSize.row),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        CdSectionHeader(title: l10n.subscriptionDetailMonths, small: true),
        const SizedBox(height: AppSpacing.sm),
        _MonthTrack(
          subscription: subscription,
          last: YearMonth.of(next ?? today),
        ),
        const SizedBox(height: AppSpacing.lg),
        CdSectionHeader(title: l10n.subscriptionDetailCharges, small: true),
        if (subscription.charges.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(l10n.subscriptionDetailNoCharges, style: secondary),
          ),
        for (final (index, charge) in subscription.charges.indexed)
          _ChargeRow(
            charge: charge,
            older: subscription.charges.elementAtOrNull(index + 1),
            hide: hide,
          ),
        const SizedBox(height: AppSpacing.lg),
        _Where(subscription: subscription),
        const SizedBox(height: AppSpacing.xl),
        ..._actions(l10n),
      ],
    );
  }

  List<Widget> _actions(AppLocalizations l10n) {
    final busy = _pending != null;
    if (widget.subscription.isSuggestion) {
      return [
        Row(
          children: [
            Expanded(
              child: CdButton.outlined(
                key: SubscriptionDetailScreen.dismissKey,
                expand: true,
                label: l10n.subscriptionDetailNotSubscription,
                loading: _pending == _Action.dismiss,
                onPressed: busy ? null : () => _run(_Action.dismiss),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: CdButton.filled(
                key: SubscriptionDetailScreen.confirmKey,
                expand: true,
                label: l10n.subscriptionsConfirm,
                loading: _pending == _Action.confirm,
                onPressed: busy ? null : () => _run(_Action.confirm),
              ),
            ),
          ],
        ),
      ];
    }
    return [
      CdButton.danger(
        key: SubscriptionDetailScreen.removeKey,
        icon: Symbols.delete_rounded,
        expand: true,
        label: l10n.subscriptionsRemove,
        loading: _pending == _Action.remove,
        onPressed: busy ? null : _remove,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        l10n.subscriptionDetailRemoveHint,
        textAlign: TextAlign.center,
        style: AppTextStyles.labelMd.copyWith(
          color: context.palette.onSurfaceVariant,
        ),
      ),
    ];
  }
}

enum _MonthState { charged, missed, next }

/// Six months up to the next charge: a check where a charge landed, a dot
/// where none did, a ring for the one to come.
class _MonthTrack extends StatelessWidget {
  const new({required this.subscription, required this.last});

  final Subscription subscription;
  final YearMonth last;

  static const _months = 6;

  _MonthState _stateOf(YearMonth month) {
    if (subscription.charges.any((c) => month.contains(c.bookedOn))) {
      return _MonthState.charged;
    }
    return month == last ? _MonthState.next : _MonthState.missed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final months = [
      for (var back = _months - 1; back >= 0; back--) last.add(-back),
    ];
    return Row(
      children: [
        for (final month in months)
          Expanded(
            child: _MonthSlot(
              key: SubscriptionDetailScreen.monthKey(month),
              month: month,
              state: _stateOf(month),
              label: shortMonth(l10n, month),
            ),
          ),
      ],
    );
  }
}

class _MonthSlot extends StatelessWidget {
  const new({
    required this.month,
    required this.state,
    required this.label,
    super.key,
  });

  final YearMonth month;
  final _MonthState state;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final money = context.money;
    final title = monthTitle(l10n, month);
    final (semantics, marker) = switch (state) {
      _MonthState.charged => (
        l10n.subscriptionMonthCharged(title),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: money.paidContainer,
            shape: BoxShape.circle,
            border: Border.all(color: money.paid, width: 2),
          ),
          child: Icon(Symbols.check_rounded, size: 16, color: money.paid),
        ),
      ),
      _MonthState.missed => (
        l10n.subscriptionMonthMissed(title),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: palette.outlineVariant,
            shape: BoxShape.circle,
          ),
        ),
      ),
      _MonthState.next => (
        l10n.subscriptionMonthNext(title),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.outline, width: 2),
          ),
        ),
      ),
    };
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(height: 28, child: Center(child: marker)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: AppTextStyles.labelMd.copyWith(
              color: state == _MonthState.next
                  ? palette.onSurface
                  : palette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  const new({required this.charge, required this.older, required this.hide});

  final SubscriptionCharge charge;
  final SubscriptionCharge? older;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = context.money;
    final palette = context.palette;
    final older = this.older;
    final delta = older == null ? 0 : charge.amount.cents - older.amount.cents;
    final change = MoneyFormat.format(
      Money(delta.abs(), currency: charge.amount.currency),
      hide: hide,
    );
    final (icon, color, subtitle) = switch (delta.sign) {
      1 => (
        Symbols.trending_up_rounded,
        money.overdue,
        l10n.subscriptionDetailChargeUp(change),
      ),
      -1 => (
        Symbols.trending_down_rounded,
        money.paid,
        l10n.subscriptionDetailChargeDown(change),
      ),
      _ => (Symbols.check_circle_rounded, palette.onSurfaceVariant, null),
    };
    return CdListRow(
      key: SubscriptionDetailScreen.chargeKey(charge.transactionId),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      leading: Icon(icon, size: 22, color: color),
      title: charge.bookedOn.display,
      subtitle: subtitle,
      trailing: CdAmount(charge.amount, size: CdAmountSize.row),
      onTap: () => context.push(AppRoutes.transaction(charge.transactionId)),
    );
  }
}

/// The account the charge lands on and its category.
class _Where extends ConsumerWidget {
  const new({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(transactionAccountsProvider).value ?? const [];
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final account = accounts
        .where((item) => item.id == subscription.accountId)
        .firstOrNull;
    final category = categories
        .where((item) => item.id == subscription.categoryId)
        .firstOrNull;
    if (account == null && category == null) return const SizedBox.shrink();
    return CdCard(
      child: Column(
        children: [
          if (account != null)
            CdKeyValueRow(
              label: l10n.transactionAccountLabel,
              value: Text(account.name, overflow: TextOverflow.ellipsis),
            ),
          if (category != null)
            CdKeyValueRow(
              label: l10n.categoryLabel,
              value: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(categoryIcon(category), size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      categoryName(l10n, category),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
