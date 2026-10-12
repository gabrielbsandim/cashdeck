import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:cashdeck/features/outlook/outlook_providers.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Picks the payers whose credits count as income.
Future<void> showIncomeSourcesSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final message = await showCdBottomSheet<String>(
    context,
    title: l10n.incomeSourcesTitle,
    builder: (_) => const IncomeSourcesSheet(),
  );
  if (message == null || !context.mounted) return;
  await showCdToast(context, icon: Symbols.task_alt_rounded, message: message);
}

class IncomeSourcesSheet extends ConsumerWidget {
  const new({super.key});

  static const retryKey = Key('income-sources-retry');

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(incomeSourcesProvider)) {
        AsyncData(:final value) => _Picker(candidates: value),
        AsyncError() => PerformanceFailed(
          retryKey: retryKey,
          onRetry: () => ref.invalidate(incomeSourcesProvider),
        ),
        _ => const PerformancePending(height: 160),
      };
}

class _Picker extends ConsumerStatefulWidget {
  const new({required this.candidates});

  final List<IncomeSourceCandidate> candidates;

  @override
  ConsumerState<_Picker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_Picker> {
  late final Set<String> _chosen = {
    for (final candidate in widget.candidates)
      if (candidate.selected) candidate.source.taxId,
  };
  var _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final sources = [
      for (final candidate in widget.candidates)
        if (_chosen.contains(candidate.source.taxId)) candidate.source,
    ];
    final result = await ref.read(setIncomeSourcesProvider).call(sources);
    if (!mounted) return;
    switch (result) {
      case Ok():
        ref.invalidate(safeToSpendProvider);
        navigator.pop(l10n.incomeSourcesSaved);
      case Err(:final failure):
        setState(() {
          _busy = false;
          _error = failure.userMessage(l10n);
        });
    }
  }

  void _toggle(String taxId, bool on) => setState(() {
    if (on) {
      _chosen.add(taxId);
      return;
    }
    _chosen.remove(taxId);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = AppTextStyles.bodyMd.copyWith(
      color: context.palette.onSurfaceVariant,
    );
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.incomeSourcesHelp, style: muted),
        const SizedBox(height: AppSpacing.sm),
        if (widget.candidates.isEmpty)
          Text(l10n.incomeSourcesEmpty, style: muted),
        for (final candidate in widget.candidates)
          CheckboxListTile(
            key: incomeSourceKey(candidate.source.taxId),
            contentPadding: EdgeInsets.zero,
            value: _chosen.contains(candidate.source.taxId),
            onChanged: (on) => _toggle(candidate.source.taxId, on ?? false),
            title: Text(candidate.source.name),
            subtitle: CdPrivateText(
              (hide) => l10n.incomeSourcesSent(
                MoneyFormat.format(candidate.total, hide: hide),
                candidate.months,
              ),
              style: muted,
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: incomeSourcesErrorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: incomeSourcesSaveKey,
          expand: true,
          label: l10n.incomeSourcesSave,
          loading: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}

Key incomeSourceKey(String taxId) => Key('income-source-$taxId');

const incomeSourcesSaveKey = Key('income-sources-save');
const incomeSourcesErrorKey = Key('income-sources-error');
