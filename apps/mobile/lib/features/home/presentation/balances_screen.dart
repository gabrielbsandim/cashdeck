import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What the home balance is made of: each cash account and its share, then
/// the reserve, cards and investments, which the home total leaves out.
class BalancesScreen extends ConsumerWidget {
  const new({super.key});

  static const totalKey = Key('balances-total');

  static Key rowKey(String id) => Key('balances-account-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.balancesTitle)),
      body: switch (ref.watch(transactionAccountsProvider)) {
        AsyncData(:final value) when value.isEmpty => CdEmptyState(
          icon: Symbols.account_balance_rounded,
          title: l10n.balancesEmpty,
        ),
        AsyncData(:final value) => _Balances(accounts: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(transactionAccountsProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _Balances extends ConsumerWidget {
  const new({required this.accounts});

  final List<TransactionAccount> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final consolidated =
        ref.watch(entityScopeProvider) == EntityScope.consolidated;
    final byBalance = [...accounts]
      ..sort((a, b) => b.balance.cents.compareTo(a.balance.cents));
    final available = [
      for (final account in byBalance)
        if (account.isCash && !account.isReserve) account,
    ];
    final reserve = [
      for (final account in byBalance)
        if (account.isCash && account.isReserve) account,
    ];
    final others = [
      for (final account in byBalance)
        if (!account.isCash) account,
    ];
    final total = available.fold(
      const Money(0),
      (sum, account) => sum + account.balance,
    );
    Widget row(TransactionAccount account, {bool share = false}) {
      final percent = share && total.cents > 0
          ? (account.balance.cents * 100 / total.cents).round()
          : null;
      final type = accountTypeLabel(l10n, account.type);
      return CdListRow(
        key: BalancesScreen.rowKey(account.id),
        icon: consolidated ? null : accountTypeIcon(account.type),
        leading: consolidated
            ? EntityKindBadge(kind: account.owner, size: 40)
            : null,
        title: account.name,
        subtitle: [
          account.institution,
          ?type,
          if (percent != null) l10n.balancesShare(percent),
        ].join(' · '),
        trailing: CdAmount(account.balance, size: CdAmountSize.row),
      );
    }

    List<Widget> section(
      String title,
      List<TransactionAccount> group, {
      bool share = false,
    }) => [
      if (group.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.lg,
            AppSpacing.screenGutter,
            AppSpacing.xs,
          ),
          child: CdSectionHeader(title: title, small: true),
        ),
        for (final account in group) row(account, share: share),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.balancesInAccounts(available.length),
                style: AppTextStyles.bodyMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              CdAmount(
                total,
                key: BalancesScreen.totalKey,
                size: CdAmountSize.xl,
                textAlign: TextAlign.start,
              ),
            ],
          ),
        ),
        ...section(l10n.balancesAvailable, available, share: true),
        ...section(l10n.balancesReserve, reserve),
        ...section(l10n.balancesOther, others),
      ],
    );
  }
}
