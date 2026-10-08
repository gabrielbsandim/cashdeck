import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/share/file_sharer.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_checkbox_row.dart';
import 'package:cashdeck/core/widgets/inputs/cd_filter_chip.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/accountant_export/accountant_export_providers.dart';
import 'package:cashdeck/features/accountant_export/domain/accountant_export.dart';
import 'package:cashdeck/features/home/presentation/home_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:material_symbols_icons/symbols.dart';

final FutureProviderFamily<ExportPlan, ExportPeriod> exportPlanProvider =
    FutureProvider.autoDispose.family<ExportPlan, ExportPeriod>(
      (ref, period) async =>
          (await ref.watch(accountantExportRepositoryProvider).plan(period))
              .orThrow,
      retry: noRetry,
    );

final FutureProvider<List<ExportRecord>>
exportHistoryProvider = FutureProvider.autoDispose<List<ExportRecord>>(
  (ref) async =>
      (await ref.watch(accountantExportRepositoryProvider).history()).orThrow,
  retry: noRetry,
);

/// Everything the accountant needs for a period, in one ZIP.
class AccountantExportScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const generateKey = Key('export-generate');

  static Key periodKey(ExportPeriod period) => Key('export-${period.name}');
  static Key itemKey(ExportItemKind kind) => Key('export-item-${kind.name}');

  @override
  ConsumerState<AccountantExportScreen> createState() =>
      _AccountantExportScreenState();
}

class _AccountantExportScreenState
    extends ConsumerState<AccountantExportScreen> {
  ExportPeriod _period = ExportPeriod.lastMonth;
  Set<ExportItemKind>? _selected;
  var _sending = false;

  Future<void> _generate(Set<ExportItemKind> items) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    final result = await ref
        .read(accountantExportRepositoryProvider)
        .generate(_period, items);
    if (!mounted) return;
    setState(() => _sending = false);
    ref.invalidate(exportHistoryProvider);
    await showOutcomeToast(context, switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    }, success: l10n.exportSentToast);
  }

  Future<void> _share(ExportRecord record) async {
    final result = await ref
        .read(accountantExportRepositoryProvider)
        .archive(record);
    switch (result) {
      case Ok(:final value):
        await ref.read(fileSharerProvider).shareFile(value);
      case Err(:final failure):
        if (!mounted) return;
        await showOutcomeToast(context, failure, success: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(exportPlanProvider(_period));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.exportTitle)),
      body: switch (plan) {
        AsyncData(:final value) => _body(context, value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(exportPlanProvider(_period)),
        ),
        _ => const CdSkeleton(),
      },
    );
  }

  Widget _body(BuildContext context, ExportPlan plan) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final selected =
        _selected ??
        {
          for (final item in plan.items)
            if (item.selectedByDefault) item.kind,
        };
    final (files, bytes) = plan.sizeOf(selected);
    final megabytes = (bytes / 1_000_000).round();
    final history = ref.watch(exportHistoryProvider).value ?? const [];
    final month = capitalized(monthName(context, plan.from));
    final periods = [
      (ExportPeriod.lastMonth, l10n.exportMonth(month, '${plan.from.year}')),
      (ExportPeriod.lastQuarter, l10n.exportQuarter),
      (ExportPeriod.custom, l10n.exportCustom),
    ];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        CdSectionHeader(title: l10n.exportPeriod, small: true),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (period, label) in periods)
              CdFilterChip(
                key: AccountantExportScreen.periodKey(period),
                label: label,
                selected: period == _period,
                onTap: () => setState(() {
                  _period = period;
                  _selected = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        CdSectionHeader(title: l10n.exportContents, small: true),
        for (final item in plan.items)
          CdCheckboxRow(
            key: AccountantExportScreen.itemKey(item.kind),
            title: exportItemLabel(l10n, item.kind),
            value: selected.contains(item.kind),
            trailing: Text(
              item.count,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            onChanged: (on) => setState(() {
              _selected = on
                  ? {...selected, item.kind}
                  : ({...selected}..remove(item.kind));
            }),
          ),
        const SizedBox(height: AppSpacing.md),
        CdCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Symbols.folder_zip_rounded, color: palette.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.exportZip(files, megabytes),
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CdButton.filled(
          key: AccountantExportScreen.generateKey,
          expand: true,
          loading: _sending,
          icon: Symbols.share_rounded,
          label: l10n.exportGenerateButton,
          onPressed: selected.isEmpty ? null : () => _generate(selected),
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          CdSectionHeader(title: l10n.exportHistory, small: true),
          for (final record in history)
            CdListRow(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              icon: Symbols.outgoing_mail_rounded,
              title: l10n.exportMonth(
                capitalized(monthName(context, record.month)),
                '${record.month.year}',
              ),
              subtitle: switch (record.to) {
                null => record.sentOn.dayMonth,
                final to => l10n.exportSentLine(record.sentOn.dayMonth, to),
              },
              trailing: Icon(
                Symbols.share_rounded,
                color: context.palette.onSurfaceVariant,
              ),
              onTap: () => _share(record),
            ),
        ],
      ],
    );
  }
}

String exportItemLabel(AppLocalizations l10n, ExportItemKind kind) =>
    switch (kind) {
      ExportItemKind.statements => l10n.exportStatements,
      ExportItemKind.invoices => l10n.exportInvoices,
      ExportItemKind.taxGuides => l10n.exportTaxGuides,
      ExportItemKind.expenses => l10n.exportExpenses,
      ExportItemKind.payroll => l10n.exportPayroll,
      ExportItemKind.reconciliation => l10n.exportReconciliation,
    };
