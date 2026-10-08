import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_checkbox_row.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/open_finance/domain/item_lookup.dart';
import 'package:cashdeck/features/open_finance/open_finance_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Connects a bank by pasting the aggregator's item id, for plans where the
/// connection cannot happen inside the app.
class ConnectByItemIdScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const fieldKey = Key('item-id-field');
  static const helpKey = Key('item-id-help');
  static const importKey = Key('item-id-import');

  static Key accountKey(String id) => Key('item-account-$id');

  @override
  ConsumerState<ConnectByItemIdScreen> createState() =>
      _ConnectByItemIdScreenState();
}

class _ConnectByItemIdScreenState extends ConsumerState<ConnectByItemIdScreen> {
  var _itemId = '';
  var _checking = false;
  var _importing = false;
  ItemLookup? _lookup;
  Set<String> _selected = {};

  Future<void> _changed(String value) async {
    setState(() {
      _itemId = value;
      _lookup = null;
    });
    if (!isValidItemId(value)) return;
    setState(() => _checking = true);
    final result = await ref.read(openFinanceRepositoryProvider).lookup(value);
    if (!mounted || value != _itemId) return;
    setState(() {
      _checking = false;
      _lookup = switch (result) {
        Ok(:final value) => value,
        Err() => const ItemNotFound(),
      };
      _selected = switch (_lookup) {
        ItemFound(:final accounts) => {for (final a in accounts) a.id},
        _ => {},
      };
    });
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final owner = switch (ref.read(entityScopeProvider)) {
      EntityScope.company => EntityKind.company,
      EntityScope.personal || EntityScope.consolidated => EntityKind.personal,
    };
    setState(() => _importing = true);
    final result = await ref
        .read(openFinanceRepositoryProvider)
        .import(_itemId, _selected, owner);
    if (!mounted) return;
    setState(() => _importing = false);
    switch (result) {
      case Ok(:final value):
        await showCdToast(
          context,
          icon: Symbols.task_alt_rounded,
          message: l10n.itemImportedToast(value),
        );
      case Err(:final failure):
        await showOutcomeToast(context, failure, success: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final lookup = _lookup;
    final invalid = _itemId.length >= 36 && !isValidItemId(_itemId);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.onboardingStep(3, 6))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          Text(
            l10n.itemIdTitle,
            style: AppTextStyles.headlineMd.copyWith(color: palette.onSurface),
          ),
          const SizedBox(height: AppSpacing.lg),
          CdCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.info_rounded,
                  size: 20,
                  color: palette.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.itemIdIntro,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          CdTextField(
            key: ConnectByItemIdScreen.fieldKey,
            label: l10n.itemIdLabel,
            monospace: true,
            maxLines: 2,
            valid: lookup is ItemFound,
            errorText: invalid ? l10n.itemIdInvalid : null,
            onChanged: _changed,
          ),
          const SizedBox(height: AppSpacing.sm),
          _LookupLine(checking: _checking, lookup: lookup),
          if (lookup case ItemFound(:final accounts)) ...[
            const SizedBox(height: AppSpacing.lg),
            CdSectionHeader(title: l10n.itemAccountsFound, small: true),
            for (final account in accounts)
              CdCheckboxRow(
                key: ConnectByItemIdScreen.accountKey(account.id),
                title: account.name,
                value: _selected.contains(account.id),
                trailing: CdAmount(account.balance, size: CdAmountSize.row),
                onChanged: (on) => setState(() {
                  _selected = on
                      ? {..._selected, account.id}
                      : ({..._selected}..remove(account.id));
                }),
              ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: CdButton.outlined(
                  key: ConnectByItemIdScreen.helpKey,
                  expand: true,
                  icon: Symbols.help_rounded,
                  label: l10n.itemIdHowButton,
                  onPressed: () => showItemIdHelpSheet(context),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: CdButton.filled(
                  key: ConnectByItemIdScreen.importKey,
                  expand: true,
                  loading: _importing,
                  label: l10n.itemImportButton(_selected.length),
                  onPressed: lookup is ItemFound && _selected.isNotEmpty
                      ? _import
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LookupLine extends StatelessWidget {
  const new({required this.checking, required this.lookup});

  final bool checking;
  final ItemLookup? lookup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final money = context.money;
    if (checking) {
      return Row(
        children: [
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            l10n.itemChecking,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    final (icon, color, text) = switch (lookup) {
      null => (null, palette.onSurfaceVariant, ''),
      ItemFound(:final institution, :final consentUntil) => (
        Symbols.check_circle_rounded,
        money.paid,
        l10n.itemFoundLine(institution, consentUntil.display),
      ),
      ItemNotFound() => (
        Symbols.error_rounded,
        money.failed,
        l10n.itemNotFound,
      ),
      ItemAlreadyConnected(:final owner) => (
        Symbols.link_rounded,
        palette.onSurfaceVariant,
        l10n.itemAlreadyConnected(entityKindLabel(l10n, owner)),
      ),
    };
    if (icon == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(text, style: AppTextStyles.bodyMd.copyWith(color: color)),
        ),
      ],
    );
  }
}

Future<void> showItemIdHelpSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showCdBottomSheet<void>(
    context,
    title: l10n.itemIdHelpTitle,
    builder: (sheetContext) => const ItemIdHelpSheet(),
  );
}

class ItemIdHelpSheet extends StatelessWidget {
  const new({super.key});

  static const openPanelKey = Key('item-help-open');
  static const doneKey = Key('item-help-done');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final steps = [
      l10n.itemHelpStep1,
      l10n.itemHelpStep2,
      l10n.itemHelpStep3,
      l10n.itemHelpStep4,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, step) in steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: palette.primaryContainer,
                  child: Text(
                    '${index + 1}',
                    style: AppTextStyles.labelMd.copyWith(
                      color: palette.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    step,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Container(
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            l10n.itemHelpPlaceholder,
            style: AppTextStyles.code.copyWith(
              fontSize: 12,
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: CdButton.outlined(
                key: openPanelKey,
                expand: true,
                icon: Symbols.open_in_new_rounded,
                label: l10n.openPanelButton,
                onPressed: () => showCdToast(
                  context,
                  icon: Symbols.open_in_new_rounded,
                  message: l10n.openPanelToast,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: CdButton.filled(
                key: doneKey,
                expand: true,
                label: l10n.gotItButton,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
