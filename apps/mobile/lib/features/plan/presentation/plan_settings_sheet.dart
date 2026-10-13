import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/presentation/plan_controller.dart';
import 'package:cashdeck/features/plan/presentation/plan_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The reserve, the yield and the savings the plan runs on.
Future<void> showPlanSettings(BuildContext context, LifePlan plan) async {
  final l10n = AppLocalizations.of(context);
  final saved = await showCdBottomSheet<bool>(
    context,
    title: l10n.planSettingsTitle,
    builder: (_) => PlanSettingsSheet(plan: plan),
  );
  if (saved != true || !context.mounted) return;
  await showCdToast(
    context,
    icon: Symbols.task_alt_rounded,
    message: l10n.planSaved,
  );
}

class PlanSettingsSheet extends ConsumerStatefulWidget {
  const new({required this.plan, super.key});

  final LifePlan plan;

  static const reserveKey = Key('plan-settings-reserve');
  static const yieldKey = Key('plan-settings-yield');
  static const keepKey = Key('plan-settings-keep');
  static const fromBudgetKey = Key('plan-settings-from-budget');
  static const savingsKey = Key('plan-settings-savings');
  static const errorKey = Key('plan-settings-error');
  static const saveKey = Key('plan-settings-save');

  @override
  ConsumerState<PlanSettingsSheet> createState() => _PlanSettingsSheetState();
}

class _PlanSettingsSheetState extends ConsumerState<PlanSettingsSheet> {
  late final _reserve = TextEditingController(
    text: '${widget.plan.reserveMonths}',
  );
  late final _yield = TextEditingController(
    text: planRate(widget.plan.yearlyYield),
  );
  late final _keep = TextEditingController(text: '${widget.plan.keepInvested}');
  late bool _fromBudget = widget.plan.savingsFromBudget;
  late Money _savings = widget.plan.monthlySavings;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _reserve.dispose();
    _yield.dispose();
    _keep.dispose();
    super.dispose();
  }

  PlanSettings get _settings => PlanSettings(
    reserveMonths: int.tryParse(_reserve.text.trim()) ?? -1,
    yearlyYield: double.tryParse(_yield.text.trim().replaceAll(',', '.')) ?? -1,
    keepInvested: int.tryParse(_keep.text.trim()) ?? -1,
    monthlySavings: _fromBudget ? null : _savings,
  );

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final settings = _settings;
    if (settings.problem != null) {
      setState(() => _error = l10n.planSettingsInvalid);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final navigator = Navigator.of(context);
    final failure = await ref
        .read(planControllerProvider.notifier)
        .saveSettings(settings);
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = failure.userMessage(l10n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdTextField(
          key: PlanSettingsSheet.reserveKey,
          controller: _reserve,
          label: l10n.planSettingsReserve,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        CdTextField(
          key: PlanSettingsSheet.yieldKey,
          controller: _yield,
          label: l10n.planSettingsYield,
          helperText: l10n.planSettingsYieldHelp,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: AppSpacing.md),
        CdTextField(
          key: PlanSettingsSheet.keepKey,
          controller: _keep,
          label: l10n.planSettingsKeep,
          helperText: l10n.planSettingsKeepHelp,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        SwitchListTile(
          key: PlanSettingsSheet.fromBudgetKey,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.planSettingsFromBudget),
          value: _fromBudget,
          onChanged: (value) => setState(() => _fromBudget = value),
        ),
        if (!_fromBudget)
          CdCurrencyInput(
            key: PlanSettingsSheet.savingsKey,
            label: l10n.planSettingsSavings,
            initial: _savings,
            large: false,
            onChanged: (value) => setState(() => _savings = value),
          ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: PlanSettingsSheet.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: PlanSettingsSheet.saveKey,
          expand: true,
          label: l10n.planSave,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
