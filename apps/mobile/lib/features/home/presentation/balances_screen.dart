import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/insights/cd_institution_logo.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/home/presentation/home_controller.dart';
import 'package:cashdeck/features/home/presentation/home_insights.dart';
import 'package:cashdeck/features/open_finance/open_finance_providers.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What the home balance is made of: each cash account and its share, then
/// the reserve, cards and investments, which the home total leaves out.
class BalancesScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const totalKey = Key('balances-total');
  static const syncKey = Key('balances-sync');
  static const connectKey = Key('balances-connect');

  static Key rowKey(String id) => Key('balances-account-$id');

  /// How far back a manual sync reaches.
  static const syncDays = 90;

  @override
  ConsumerState<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends ConsumerState<BalancesScreen> {
  bool _syncing = false;

  Future<void> _sync(List<TransactionAccount> accounts) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(openFinanceRepositoryProvider);
    final connections = {for (final account in accounts) ?account.connectionId};
    setState(() => _syncing = true);
    var imported = 0;
    AppFailure? failure;
    for (final connection in connections) {
      switch (await repository.sync(
        connection,
        days: BalancesScreen.syncDays,
      )) {
        case Ok(:final value):
          imported += value;
        case Err(failure: final error):
          failure = error;
      }
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    ref
      ..invalidate(transactionAccountsProvider)
      ..invalidate(homeControllerProvider);
    await showOutcomeToast(
      context,
      failure,
      success: l10n.balancesSynced(imported),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(transactionAccountsProvider);
    final connected = [
      for (final account in accounts.value ?? const <TransactionAccount>[])
        if (account.connectionId != null) account,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.balancesTitle),
        actions: [
          if (connected.isNotEmpty)
            IconButton(
              key: BalancesScreen.syncKey,
              tooltip: l10n.balancesSyncHistory,
              onPressed: _syncing ? null : () => _sync(connected),
              icon: _syncing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.sync_rounded),
            ),
        ],
      ),
      body: switch (accounts) {
        AsyncData(:final value) when value.isEmpty => CdEmptyState(
          icon: Symbols.account_balance_rounded,
          title: l10n.balancesEmpty,
          actionLabel: l10n.balancesConnect,
          onAction: () => context.push(AppRoutes.connectItemId).ignore(),
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

String _syncLabel(AppLocalizations l10n, SyncState state) => switch (state) {
  SyncState.updated => l10n.syncStateUpdated,
  SyncState.updating => l10n.syncStateUpdating,
  SyncState.needsAction => l10n.syncStateNeedsAction,
  SyncState.outdated => l10n.syncStateOutdated,
};

Color _syncColor(BuildContext context, SyncState state) => switch (state) {
  SyncState.updated => context.money.paid,
  SyncState.updating => context.money.scheduled,
  SyncState.needsAction => context.money.overdue,
  SyncState.outdated => context.money.pending,
};

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
    final institutions = {for (final account in byBalance) account.institution}
        .toList();
    Widget row(TransactionAccount account, {bool share = false}) {
      final percent = share && total.cents > 0
          ? (account.balance.cents * 100 / total.cents).round()
          : null;
      final type = accountTypeLabel(l10n, account.type);
      final sync = account.sync;
      return CdListRow(
        key: BalancesScreen.rowKey(account.id),
        leading: consolidated
            ? EntityKindBadge(kind: account.owner, size: 40)
            : CdInstitutionLogo(
                name: account.institution,
                imageUrl: account.logo?.imageUrl,
                colors: context.charts.at(
                  institutions.indexOf(account.institution),
                ),
              ),
        title: account.name,
        subtitle: [
          account.institution,
          ?type,
          if (percent != null) l10n.balancesShare(percent),
          if (!account.isCash) l10n.balancesOutsideTotal,
        ].join(' · '),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CdAmount(account.balance, size: CdAmountSize.row),
            if (sync != null)
              Text(
                _syncLabel(l10n, sync.state),
                style: AppTextStyles.labelMd.copyWith(
                  color: _syncColor(context, sync.state),
                ),
              ),
          ],
        ),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            0,
          ),
          child: InstitutionBar(),
        ),
        ...section(l10n.balancesAvailable, available, share: true),
        ...section(l10n.balancesReserve, reserve),
        ...section(l10n.balancesOther, others),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.lg,
            AppSpacing.screenGutter,
            0,
          ),
          child: CdButton.outlined(
            key: BalancesScreen.connectKey,
            label: l10n.balancesConnect,
            icon: Symbols.add_link_rounded,
            onPressed: () => context.push(AppRoutes.connectItemId).ignore(),
          ),
        ),
      ],
    );
  }
}
