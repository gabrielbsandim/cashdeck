import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:cashdeck/features/outlook/outlook_providers.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Changes the monthly savings target the plan starts from.
Future<void> showSavingsTargetSheet(
  BuildContext context,
  SpendingPlan plan,
) async {
  final l10n = AppLocalizations.of(context);
  final message = await showCdBottomSheet<String>(
    context,
    title: l10n.savingsTargetTitle,
    builder: (_) => SavingsTargetSheet(plan: plan),
  );
  if (message == null || !context.mounted) return;
  await showCdToast(context, icon: Symbols.task_alt_rounded, message: message);
}

class SavingsTargetSheet extends ConsumerStatefulWidget {
  const new({required this.plan, super.key});

  static const amountKey = Key('savings-target-amount');
  static const saveKey = Key('savings-target-save');
  static const typicalKey = Key('savings-target-typical');
  static const errorKey = Key('savings-target-error');

  final SpendingPlan plan;

  @override
  ConsumerState<SavingsTargetSheet> createState() => _SavingsTargetSheetState();
}

class _SavingsTargetSheetState extends ConsumerState<SavingsTargetSheet> {
  late Money _savings = widget.plan.savings;
  var _busy = false;
  String? _error;

  Future<void> _save(Money? savings) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final result = await ref.read(setSavingsTargetProvider).call(savings);
    if (!mounted) return;
    switch (result) {
      case Ok():
        ref.invalidate(safeToSpendProvider);
        navigator.pop(l10n.savingsTargetSaved);
      case Err(:final failure):
        setState(() {
          _busy = false;
          _error = failure.userMessage(l10n);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdCurrencyInput(
          key: SavingsTargetSheet.amountKey,
          label: l10n.savingsTargetLabel,
          initial: _savings,
          helperText: l10n.savingsTargetHelp,
          onChanged: (value) => setState(() => _savings = value),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: SavingsTargetSheet.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: SavingsTargetSheet.saveKey,
          expand: true,
          label: l10n.savingsTargetSave,
          loading: _busy,
          onPressed: () => _save(_savings),
        ),
        if (widget.plan.savingsSet) ...[
          const SizedBox(height: AppSpacing.sm),
          CdButton.text(
            key: SavingsTargetSheet.typicalKey,
            expand: true,
            label: l10n.savingsTargetTypical,
            onPressed: _busy ? null : () => _save(null),
          ),
        ],
      ],
    );
  }
}
