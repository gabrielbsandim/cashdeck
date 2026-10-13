import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/assets/presentation/assets_controller.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/presentation/goals_controller.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/presentation/plan_controller.dart';
import 'package:cashdeck/features/plan/presentation/plan_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Adds a goal to the plan, or edits [goal].
Future<void> showPlanGoalEditor(BuildContext context, {PlanGoal? goal}) async {
  final l10n = AppLocalizations.of(context);
  final message = await showCdBottomSheet<String>(
    context,
    title: goal == null ? l10n.planNew : l10n.planEdit,
    builder: (_) => PlanGoalEditor(goal: goal),
  );
  if (message == null || !context.mounted) return;
  await showCdToast(context, icon: Symbols.task_alt_rounded, message: message);
}

class PlanGoalEditor extends ConsumerStatefulWidget {
  const new({this.goal, super.key});

  final PlanGoal? goal;

  static const kindKey = Key('plan-kind');
  static const nameKey = Key('plan-name');
  static const priceKey = Key('plan-price');
  static const paymentKey = Key('plan-payment');
  static const installmentsKey = Key('plan-installments');
  static const caixinhaKey = Key('plan-caixinha');
  static const assetKey = Key('plan-asset');
  static const tradeInKey = Key('plan-trade-in');
  static const financedKey = Key('plan-financed');
  static const monthlyCostKey = Key('plan-monthly-cost');
  static const keepsValueKey = Key('plan-keeps-value');
  static const notBeforeKey = Key('plan-not-before');
  static const byKey = Key('plan-by');
  static const yearlyKey = Key('plan-yearly');
  static const metricKey = Key('plan-metric');
  static const targetKey = Key('plan-target');
  static const errorKey = Key('plan-error');
  static const saveKey = Key('plan-save');
  static const deleteKey = Key('plan-delete');

  static Key clearKey(String field) => Key('plan-clear-$field');

  @override
  ConsumerState<PlanGoalEditor> createState() => _PlanGoalEditorState();
}

class _PlanGoalEditorState extends ConsumerState<PlanGoalEditor> {
  final _name = TextEditingController();
  late PlanGoalDraft _draft = const PlanGoalDraft(
    kind: PlanGoalKind.purchase,
    name: '',
  );
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    if (goal == null) return;
    _draft = PlanGoalDraft.of(goal);
    _name.text = goal.name;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  PlanGoalDraft get _current => PlanGoalDraft(
    kind: _draft.kind,
    name: _name.text,
    icon: _draft.icon,
    price: _draft.price,
    tradeIn: _draft.tradeIn,
    tradeInAssetId: _draft.tradeInAssetId,
    financed: _draft.financed,
    monthlyCost: _draft.monthlyCost,
    keepsValue: _draft.keepsValue,
    payment: _draft.payment,
    installments: _draft.installments,
    goalId: _draft.goalId,
    notBefore: _draft.notBefore,
    by: _draft.by,
    yearly: _draft.yearly,
    metric: _draft.metric,
    target: _draft.target,
  );

  void _edit(PlanGoalDraft Function(PlanGoalDraft draft) change) =>
      setState(() => _draft = change(_current));

  Future<YearMonth?> _pickMonth(YearMonth? initial) async {
    final today = CalendarDate.brazilToday(ref.read(clockProvider).now());
    final first = DateTime(today.year, today.month);
    final start = initial ?? YearMonth.of(today);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(start.year, start.month),
      firstDate: first,
      lastDate: DateTime(today.year + 40, 12),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return null;
    return YearMonth(picked.year, picked.month);
  }

  Future<void> _pickNotBefore() async {
    final month = await _pickMonth(_draft.notBefore);
    if (month == null || !mounted) return;
    _edit((draft) => _with(draft, notBefore: () => month));
  }

  Future<void> _pickBy() async {
    final month = await _pickMonth(_draft.by);
    if (month == null || !mounted) return;
    _edit((draft) => _with(draft, by: () => month));
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final draft = _current;
    final problem = draft.problem;
    setState(() {
      _draft = draft;
      _error = problem == null ? null : planProblemMessage(l10n, problem);
    });
    if (problem != null) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final failure = await ref
        .read(planControllerProvider.notifier)
        .save(draft, id: widget.goal?.id);
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(l10n.planSaved);
      return;
    }
    setState(() {
      _saving = false;
      _error = failure.userMessage(l10n);
    });
  }

  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final failure = await ref.read(planControllerProvider.notifier).remove(id);
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(l10n.planDeleted);
      return;
    }
    setState(() {
      _saving = false;
      _error = failure.userMessage(l10n);
    });
  }

  Widget _money(Key key, String label, Money initial, ValueChanged<Money> on) =>
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: CdCurrencyInput(
          key: key,
          label: label,
          initial: initial,
          large: false,
          onChanged: on,
        ),
      );

  Widget _monthRow({
    required Key key,
    required String field,
    required String label,
    required YearMonth? month,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) => CdListRow(
    key: key,
    title: label,
    icon: Symbols.calendar_month_rounded,
    padding: EdgeInsets.zero,
    onTap: onTap,
    trailing: month == null
        ? null
        : IconButton(
            key: PlanGoalEditor.clearKey(field),
            tooltip: AppLocalizations.of(context).planMonthClear,
            icon: const Icon(Symbols.close_rounded),
            onPressed: onClear,
          ),
  );

  List<Widget> _purchaseFields(AppLocalizations l10n) {
    final assets = [
      for (final asset
          in ref.watch(assetsControllerProvider).value?.items ??
              const <Asset>[])
        if (asset.soldOn == null) asset,
    ];
    final assetId = _draft.tradeInAssetId;
    final notBefore = _draft.notBefore;
    final by = _draft.by;
    return [
      _money(
        PlanGoalEditor.priceKey,
        l10n.planPrice,
        _draft.price,
        (value) => _edit((draft) => _with(draft, price: value)),
      ),
      const SizedBox(height: AppSpacing.md),
      CdSegmented<PlanPayment>(
        key: PlanGoalEditor.paymentKey,
        segments: [
          CdSegment(PlanPayment.cash, l10n.planPaymentCash),
          CdSegment(PlanPayment.card, l10n.planPaymentCard),
        ],
        selected: _draft.payment,
        onChanged: (payment) =>
            _edit((draft) => _with(draft, payment: payment)),
      ),
      if (_draft.payment == PlanPayment.card) ...[
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<int>(
          key: PlanGoalEditor.installmentsKey,
          initialValue: _draft.installments,
          decoration: InputDecoration(labelText: l10n.planInstallments),
          items: [
            for (var count = 1; count <= maxPlanInstallments; count++)
              DropdownMenuItem(
                value: count,
                child: Text(l10n.planInstallmentsOption(count)),
              ),
          ],
          onChanged: (count) =>
              _edit((draft) => _with(draft, installments: count)),
        ),
      ],
      ..._caixinhaField(l10n),
      if (assets.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String?>(
          key: PlanGoalEditor.assetKey,
          isExpanded: true,
          initialValue: assets.any((asset) => asset.id == assetId)
              ? assetId
              : null,
          decoration: InputDecoration(
            labelText: l10n.planTradeInAsset,
            helperText: l10n.planTradeInAssetHelp,
            helperMaxLines: 2,
          ),
          items: [
            DropdownMenuItem(child: Text(l10n.planTradeInNone)),
            for (final asset in assets)
              DropdownMenuItem(
                value: asset.id,
                child: Text(asset.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) =>
              _edit((draft) => _with(draft, tradeInAssetId: () => value)),
        ),
      ],
      if (assetId == null)
        _money(
          PlanGoalEditor.tradeInKey,
          l10n.planTradeIn,
          _draft.tradeIn,
          (value) => _edit((draft) => _with(draft, tradeIn: value)),
        ),
      _money(
        PlanGoalEditor.financedKey,
        l10n.planFinanced,
        _draft.financed,
        (value) => _edit((draft) => _with(draft, financed: value)),
      ),
      _money(
        PlanGoalEditor.monthlyCostKey,
        l10n.planMonthlyCost,
        _draft.monthlyCost,
        (value) => _edit((draft) => _with(draft, monthlyCost: value)),
      ),
      SwitchListTile(
        key: PlanGoalEditor.keepsValueKey,
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.planKeepsValue),
        subtitle: Text(l10n.planKeepsValueHelp),
        value: _draft.keepsValue,
        onChanged: (value) => _edit((draft) => _with(draft, keepsValue: value)),
      ),
      _monthRow(
        key: PlanGoalEditor.notBeforeKey,
        field: 'not-before',
        label: notBefore == null
            ? l10n.planNotBeforeNone
            : l10n.planNotBefore(planMonth(l10n, notBefore)),
        month: notBefore,
        onTap: _pickNotBefore,
        onClear: () => _edit((draft) => _with(draft, notBefore: () => null)),
      ),
      _byRow(l10n, by),
    ];
  }

  List<Widget> _caixinhaField(AppLocalizations l10n) {
    final caixinhas =
        ref.watch(goalsControllerProvider).value ?? const <Goal>[];
    if (caixinhas.isEmpty) return const [];
    final goalId = _draft.goalId;
    return [
      const SizedBox(height: AppSpacing.md),
      DropdownButtonFormField<String?>(
        key: PlanGoalEditor.caixinhaKey,
        isExpanded: true,
        initialValue: caixinhas.any((goal) => goal.id == goalId)
            ? goalId
            : null,
        decoration: InputDecoration(
          labelText: l10n.planCaixinha,
          helperText: l10n.planCaixinhaHelp,
          helperMaxLines: 2,
        ),
        items: [
          DropdownMenuItem(child: Text(l10n.planCaixinhaNone)),
          for (final goal in caixinhas)
            DropdownMenuItem(
              value: goal.id,
              child: Text(goal.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) =>
            _edit((draft) => _with(draft, goalId: () => value)),
      ),
    ];
  }

  Widget _byRow(AppLocalizations l10n, YearMonth? by) => _monthRow(
    key: PlanGoalEditor.byKey,
    field: 'by',
    label: by == null ? l10n.planByNone : l10n.planBy(planMonth(l10n, by)),
    month: by,
    onTap: _pickBy,
    onClear: () => _edit((draft) => _with(draft, by: () => null)),
  );

  List<Widget> _milestoneFields(AppLocalizations l10n) => [
    const SizedBox(height: AppSpacing.md),
    CdSegmented<MilestoneMetric>(
      key: PlanGoalEditor.metricKey,
      segments: [
        CdSegment(MilestoneMetric.netWorth, l10n.planMetricNetWorth),
        CdSegment(MilestoneMetric.invested, l10n.planMetricInvested),
      ],
      selected: _draft.metric,
      onChanged: (metric) => _edit((draft) => _with(draft, metric: metric)),
    ),
    _money(
      PlanGoalEditor.targetKey,
      l10n.planTarget,
      _draft.target,
      (value) => _edit((draft) => _with(draft, target: value)),
    ),
    const SizedBox(height: AppSpacing.sm),
    _byRow(l10n, _draft.by),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = _error;
    final goal = widget.goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (goal == null) ...[
          CdSegmented<PlanGoalKind>(
            key: PlanGoalEditor.kindKey,
            segments: [
              for (final kind in PlanGoalKind.values)
                CdSegment(kind, planKindLabel(l10n, kind)),
            ],
            selected: _draft.kind,
            onChanged: (kind) => _edit((draft) => _with(draft, kind: kind)),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        CdTextField(
          key: PlanGoalEditor.nameKey,
          controller: _name,
          label: l10n.planName,
          textInputAction: TextInputAction.next,
        ),
        ...switch (_draft.kind) {
          PlanGoalKind.purchase => _purchaseFields(l10n),
          PlanGoalKind.yearly => [
            _money(
              PlanGoalEditor.yearlyKey,
              l10n.planYearly,
              _draft.yearly,
              (value) => _edit((draft) => _with(draft, yearly: value)),
            ),
          ],
          PlanGoalKind.milestone => _milestoneFields(l10n),
        },
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: PlanGoalEditor.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: PlanGoalEditor.saveKey,
          expand: true,
          label: l10n.planSave,
          loading: _saving,
          onPressed: _save,
        ),
        if (goal != null) ...[
          const SizedBox(height: AppSpacing.sm),
          CdButton.danger(
            key: PlanGoalEditor.deleteKey,
            expand: true,
            label: l10n.planDelete,
            onPressed: _saving ? null : () => _delete(goal.id),
          ),
        ],
      ],
    );
  }
}

/// A copy of [draft] with the given fields; nullable ones take a function so
/// null can clear them.
PlanGoalDraft _with(
  PlanGoalDraft draft, {
  PlanGoalKind? kind,
  Money? price,
  Money? tradeIn,
  String? Function()? tradeInAssetId,
  Money? financed,
  Money? monthlyCost,
  bool? keepsValue,
  PlanPayment? payment,
  int? installments,
  String? Function()? goalId,
  YearMonth? Function()? notBefore,
  YearMonth? Function()? by,
  Money? yearly,
  MilestoneMetric? metric,
  Money? target,
}) => PlanGoalDraft(
  kind: kind ?? draft.kind,
  name: draft.name,
  icon: draft.icon,
  price: price ?? draft.price,
  tradeIn: tradeIn ?? draft.tradeIn,
  tradeInAssetId: tradeInAssetId == null
      ? draft.tradeInAssetId
      : tradeInAssetId(),
  financed: financed ?? draft.financed,
  monthlyCost: monthlyCost ?? draft.monthlyCost,
  keepsValue: keepsValue ?? draft.keepsValue,
  payment: payment ?? draft.payment,
  installments: installments ?? draft.installments,
  goalId: goalId == null ? draft.goalId : goalId(),
  notBefore: notBefore == null ? draft.notBefore : notBefore(),
  by: by == null ? draft.by : by(),
  yearly: yearly ?? draft.yearly,
  metric: metric ?? draft.metric,
  target: target ?? draft.target,
);
