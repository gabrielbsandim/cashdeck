import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/insights/cd_institution_logo.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String subscriptionStatusLabel(
  AppLocalizations l10n,
  SubscriptionMonthStatus status,
) => switch (status) {
  SubscriptionMonthStatus.paid => l10n.subscriptionsPaid,
  SubscriptionMonthStatus.upcoming => l10n.subscriptionsUpcoming,
  SubscriptionMonthStatus.late => l10n.subscriptionsLate,
};

MoneyTone subscriptionStatusTone(SubscriptionMonthStatus status) =>
    switch (status) {
      SubscriptionMonthStatus.paid => MoneyTone.paid,
      SubscriptionMonthStatus.upcoming => MoneyTone.scheduled,
      SubscriptionMonthStatus.late => MoneyTone.overdue,
    };

Color subscriptionStatusColor(
  BuildContext context,
  SubscriptionMonthStatus status,
) => switch (status) {
  SubscriptionMonthStatus.paid => context.money.paid,
  SubscriptionMonthStatus.upcoming => context.money.scheduled,
  SubscriptionMonthStatus.late => context.money.overdue,
};

/// `Todo dia 12 · Pago · Subiu de R$ 19,90`, as a row reads.
String subscriptionSubtitle(
  AppLocalizations l10n,
  Subscription subscription, {
  required bool hide,
}) {
  final previous = subscription.previousAmount;
  return [
    l10n.subscriptionsEveryDay(subscription.dayOfMonth),
    subscriptionStatusLabel(l10n, subscription.thisMonth),
    if (subscription.priceChanged && previous != null)
      l10n.subscriptionsPriceUp(MoneyFormat.format(previous, hide: hide)),
  ].join(' · ');
}

/// The merchant's monogram on a tint picked by its key, with the bank the
/// charge lands on as a small badge once the accounts load.
class SubscriptionAvatar extends ConsumerWidget {
  const new({required this.subscription, this.size = 40, super.key});

  final Subscription subscription;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charts = context.charts;
    final accounts = ref.watch(transactionAccountsProvider).value ?? const [];
    final account = accounts
        .where((item) => item.id == subscription.accountId)
        .firstOrNull;
    final merchant = CdInstitutionLogo(
      name: subscription.name,
      size: size,
      colors: charts.at(subscription.key.codeUnits.fold(0, (a, b) => a + b)),
    );
    if (account == null) return merchant;
    final badge = size * 0.45;
    return SizedBox.square(
      dimension: size + badge * 0.2,
      child: Stack(
        children: [
          merchant,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: context.palette.surface,
                shape: BoxShape.circle,
              ),
              child: CdInstitutionLogo(
                name: account.institution,
                imageUrl: account.logo?.imageUrl,
                size: badge,
                colors: charts.at(account.institution.length),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
