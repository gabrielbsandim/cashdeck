import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/share/file_sharer.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_refresh.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/assets/assets_providers.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/assets/presentation/asset_editor.dart';
import 'package:cashdeck/features/assets/presentation/assets_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

IconData assetIcon(AssetKind kind) => switch (kind) {
  AssetKind.property => Symbols.home_work_rounded,
  AssetKind.vehicle => Symbols.directions_car_rounded,
  AssetKind.other => Symbols.category_rounded,
};

/// What the tenant reads: the rent, each line passed on and the total.
String rentMessage(
  AppLocalizations l10n,
  AssetRental rental,
  RentCharge charge,
) {
  final due = charge.dueDate;
  final lines = [
    l10n.rentMessageLine(l10n.assetRent, MoneyFormat.format(rental.rent)),
    for (final line in charge.passedOn)
      l10n.rentMessageLine(line.description, MoneyFormat.format(line.amount)),
  ];
  return l10n.rentMessage(
    _monthOf(l10n, due),
    lines.join('\n'),
    MoneyFormat.format(charge.total),
  );
}

String _monthOf(AppLocalizations l10n, CalendarDate day) =>
    DateFormat('MMMM', l10n.localeName).format(DateTime(day.year, day.month));

/// Properties, vehicles and other goods: what each is worth, what its loan
/// still owes and how much of it is already the family's.
class AssetsScreen extends ConsumerWidget {
  const new({super.key});

  static const addKey = Key('assets-add');
  static const totalKey = Key('assets-total');

  static Key cardKey(String id) => Key('asset-$id');

  static Key menuKey(String id) => Key('asset-menu-$id');

  static const editKey = Key('asset-edit');
  static const revalueKey = Key('asset-revalue');
  static const soldKey = Key('asset-sold');
  static const deleteKey = Key('asset-delete');
  static const confirmKey = Key('asset-confirm');
  static const revalueAmountKey = Key('asset-revalue-amount');
  static const revalueSaveKey = Key('asset-revalue-save');
  static const rentTotalKey = Key('asset-rent-total');
  static const rentReceivedKey = Key('asset-rent-received');
  static const rentSendKey = Key('asset-rent-send');
  static const rentResultKey = Key('asset-rent-result');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    void add() => showAssetEditor(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.assetsTitle),
        actions: [
          IconButton(
            key: addKey,
            tooltip: l10n.assetAdd,
            icon: const Icon(Symbols.add_rounded),
            onPressed: add,
          ),
        ],
      ),
      body: switch (ref.watch(assetsControllerProvider)) {
        AsyncValue(:final value?, hasError: false) when value.isEmpty =>
          CdEmptyState(
            icon: Symbols.home_work_rounded,
            title: l10n.assetsEmptyTitle,
            message: l10n.assetsEmptyMessage,
            actionLabel: l10n.assetAdd,
            actionIcon: Symbols.add_rounded,
            onAction: add,
          ),
        AsyncValue(:final value?, hasError: false) => CdRefresh(
          providers: [assetsControllerProvider],
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.xxl,
            ),
            children: [
              _Totals(summary: value),
              for (final asset in value.items) ...[
                const SizedBox(height: AppSpacing.md),
                _AssetCard(key: cardKey(asset.id), asset: asset),
              ],
            ],
          ),
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(assetsControllerProvider),
        ),
        _ => const CdSkeleton(parts: [CdSkeletonCards(height: 160)]),
      },
    );
  }
}

class _Totals extends StatelessWidget {
  const new({required this.summary});

  final AssetsSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.assetsValue,
            style: AppTextStyles.bodyMd.copyWith(
              color: context.palette.onSurfaceVariant,
            ),
          ),
          CdAmount(
            summary.value,
            key: AssetsScreen.totalKey,
            size: CdAmountSize.lg,
            textAlign: TextAlign.start,
          ),
          if (summary.loanDebt.cents > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            CdKeyValueRow(
              label: l10n.assetsLoanDebt,
              value: CdAmount(summary.loanDebt, kind: CdAmountKind.expense),
            ),
            CdKeyValueRow(
              label: l10n.assetsEquity,
              strong: true,
              value: CdAmount(summary.equity),
            ),
          ],
        ],
      ),
    );
  }
}

enum _AssetAction { edit, revalue, sold, delete }

class _AssetCard extends ConsumerWidget {
  const new({required this.asset, super.key});

  final Asset asset;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _AssetAction action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(assetsControllerProvider.notifier);
    switch (action) {
      case _AssetAction.edit:
        await showAssetEditor(context, asset: asset);
      case _AssetAction.revalue:
        final value = await showCdBottomSheet<Money>(
          context,
          title: l10n.assetRevalueTitle(asset.name),
          builder: (_) => _Revalue(initial: asset.value),
        );
        if (value == null || !context.mounted) return;
        final failure = await controller.revalue(asset.id, value);
        if (!context.mounted) return;
        await showOutcomeToast(context, failure, success: l10n.assetRevalued);
      case _AssetAction.sold:
        if (!await _confirm(context, l10n.assetSoldMessage, l10n.assetSold)) {
          return;
        }
        final failure = await controller.markSold(asset.id);
        if (!context.mounted) return;
        await showOutcomeToast(context, failure, success: l10n.assetMarkedSold);
      case _AssetAction.delete:
        if (!await _confirm(
          context,
          l10n.assetDeleteMessage,
          l10n.assetDelete,
        )) {
          return;
        }
        CdHaptics.warning();
        final failure = await controller.delete(asset.id);
        if (!context.mounted) return;
        await showOutcomeToast(context, failure, success: l10n.assetDeleted);
    }
  }

  Future<bool> _confirm(
    BuildContext context,
    String message,
    String label,
  ) async {
    final confirmed = await showCdBottomSheet<bool>(
      context,
      title: asset.name,
      builder: (_) => _Confirm(message: message, label: label),
    );
    return confirmed == true && context.mounted;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final muted = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final loan = asset.loan;
    final percent = asset.changePercent;
    final change = MoneyFormat.format(
      asset.change,
      hide: hide,
      sign: MoneySign.plus,
    );
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(assetIcon(asset.kind), color: palette.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  asset.name,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
              PopupMenuButton<_AssetAction>(
                key: AssetsScreen.menuKey(asset.id),
                onSelected: (action) => _act(context, ref, action),
                itemBuilder: (_) => [
                  if (!asset.sold)
                    PopupMenuItem(
                      key: AssetsScreen.editKey,
                      value: _AssetAction.edit,
                      child: Text(l10n.assetEdit),
                    ),
                  if (!asset.sold)
                    PopupMenuItem(
                      key: AssetsScreen.revalueKey,
                      value: _AssetAction.revalue,
                      child: Text(l10n.assetRevalue),
                    ),
                  if (!asset.sold)
                    PopupMenuItem(
                      key: AssetsScreen.soldKey,
                      value: _AssetAction.sold,
                      child: Text(l10n.assetSold),
                    ),
                  PopupMenuItem(
                    key: AssetsScreen.deleteKey,
                    value: _AssetAction.delete,
                    child: Text(l10n.assetDelete),
                  ),
                ],
              ),
            ],
          ),
          CdAmount(
            asset.value,
            size: CdAmountSize.lg,
            textAlign: TextAlign.start,
          ),
          Text(switch (asset) {
            Asset(:final soldOn?) => l10n.assetSoldOn(soldOn.display),
            Asset(fipe: _?) => l10n.assetFipeOn(asset.valuedOn.display),
            _ => l10n.assetValuedOn(asset.valuedOn.display),
          }, style: muted),
          if (asset.change.cents != 0)
            Text(
              percent == null
                  ? l10n.assetChange(change)
                  : l10n.assetChangePercent(change, percent.toStringAsFixed(1)),
              style: AppTextStyles.bodyMd.copyWith(
                color: asset.change.isNegative
                    ? context.money.expense
                    : context.money.income,
              ),
            ),
          if (loan != null) ...[
            const SizedBox(height: AppSpacing.md),
            CdKeyValueRow(
              label: loan.name,
              value: CdAmount(loan.balance, kind: CdAmountKind.expense),
            ),
            CdKeyValueRow(
              label: l10n.assetEquity,
              strong: true,
              value: CdAmount(asset.equity),
            ),
          ],
          if (asset.rental case final rental?) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            _Rental(rental: rental),
          ],
        ],
      ),
    );
  }
}

class _Rental extends ConsumerStatefulWidget {
  const new({required this.rental});

  final AssetRental rental;

  @override
  ConsumerState<_Rental> createState() => _RentalState();
}

class _RentalState extends ConsumerState<_Rental> {
  var _sending = false;

  Future<void> _send(RentCharge charge) async {
    final l10n = AppLocalizations.of(context);
    final text = rentMessage(l10n, widget.rental, charge);
    final sharer = ref.read(fileSharerProvider);
    if (charge.attachmentId == null) {
      await sharer.shareText(text);
      return;
    }
    setState(() => _sending = true);
    final bill = await ref.read(loadRentBillProvider).call(charge);
    if (!mounted) return;
    setState(() => _sending = false);
    switch (bill) {
      case Ok(:final value):
        await sharer.shareFile(value, text: text);
      case Err(:final failure):
        await showOutcomeToast(context, failure, success: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rental = widget.rental;
    final muted = AppTextStyles.bodyMd.copyWith(
      color: context.palette.onSurfaceVariant,
    );
    final charge = rental.charge;
    if (charge == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CdKeyValueRow(label: l10n.assetRent, value: CdAmount(rental.rent)),
          Text(l10n.rentChargeNoBill, style: muted),
        ],
      );
    }
    final installment = charge.installment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.rentChargeTitle(_monthOf(l10n, charge.dueDate)),
          style: AppTextStyles.titleSm.copyWith(
            color: context.palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        CdKeyValueRow(label: l10n.assetRent, value: CdAmount(rental.rent)),
        for (final line in charge.passedOn)
          CdKeyValueRow(label: line.description, value: CdAmount(line.amount)),
        CdKeyValueRow(
          label: l10n.rentChargeTotal,
          strong: true,
          value: CdAmount(charge.total, key: AssetsScreen.rentTotalKey),
        ),
        switch (charge.received) {
          RentReceived(:final on, :final amount) => CdKeyValueRow(
            key: AssetsScreen.rentReceivedKey,
            label: l10n.rentReceivedOn(on.dayMonth),
            value: CdAmount(amount, kind: CdAmountKind.income),
          ),
          null => Text(
            l10n.rentNotReceived,
            key: AssetsScreen.rentReceivedKey,
            style: muted,
          ),
        },
        const SizedBox(height: AppSpacing.sm),
        CdButton.tonal(
          key: AssetsScreen.rentSendKey,
          expand: true,
          icon: Symbols.send_rounded,
          label: l10n.rentChargeSend,
          loading: _sending,
          onPressed: () => _send(charge),
        ),
        const SizedBox(height: AppSpacing.md),
        if (installment != null)
          CdKeyValueRow(
            label: l10n.rentInstallment,
            value: CdAmount(installment, kind: CdAmountKind.expense),
          ),
        CdKeyValueRow(
          label: l10n.rentOwnerCost,
          value: CdAmount(charge.ownerCost, kind: CdAmountKind.expense),
        ),
        CdKeyValueRow(
          label: l10n.rentResult,
          strong: true,
          value: CdAmount(charge.result, key: AssetsScreen.rentResultKey),
        ),
      ],
    );
  }
}

class _Revalue extends StatefulWidget {
  const new({required this.initial});

  final Money initial;

  @override
  State<_Revalue> createState() => _RevalueState();
}

class _RevalueState extends State<_Revalue> {
  late Money _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdCurrencyInput(
          key: AssetsScreen.revalueAmountKey,
          label: l10n.assetValue,
          initial: widget.initial,
          helperText: l10n.assetRevalueHelp,
          onChanged: (value) => setState(() => _value = value),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: AssetsScreen.revalueSaveKey,
          expand: true,
          label: l10n.assetRevalueSave,
          onPressed: _value.cents > 0
              ? () => Navigator.of(context).pop(_value)
              : null,
        ),
      ],
    );
  }
}

class _Confirm extends StatelessWidget {
  const new({required this.message, required this.label});

  final String message;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          style: AppTextStyles.bodyLg.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.danger(
          key: AssetsScreen.confirmKey,
          expand: true,
          label: label,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          expand: true,
          label: l10n.cancelButton,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
