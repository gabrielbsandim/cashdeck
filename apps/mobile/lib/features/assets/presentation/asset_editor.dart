import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/assets/presentation/assets_controller.dart';
import 'package:cashdeck/features/loans/presentation/loans_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Adds a property, vehicle or other good.
Future<void> showAssetEditor(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final saved = await showCdBottomSheet<bool>(
    context,
    title: l10n.assetAdd,
    builder: (_) => const AssetEditor(),
  );
  if (saved != true || !context.mounted) return;
  await showCdToast(
    context,
    icon: Symbols.task_alt_rounded,
    message: l10n.assetAdded,
  );
}

String assetProblemMessage(AppLocalizations l10n, AssetProblem problem) =>
    switch (problem) {
      AssetProblem.name => l10n.assetNameMissing,
      AssetProblem.value => l10n.assetValueMissing,
      AssetProblem.fipeCode => l10n.assetFipeCodeInvalid,
      AssetProblem.modelYear => l10n.assetModelYearInvalid,
      AssetProblem.futureDate => l10n.assetFutureDate,
    };

class AssetEditor extends ConsumerStatefulWidget {
  const new({super.key});

  static const kindKey = Key('asset-kind');
  static const nameKey = Key('asset-name');
  static const valueKey = Key('asset-value');
  static const acquiredKey = Key('asset-acquired');
  static const fipeKey = Key('asset-fipe');
  static const fipeCodeKey = Key('asset-fipe-code');
  static const modelYearKey = Key('asset-model-year');
  static const loanKey = Key('asset-loan');
  static const errorKey = Key('asset-error');
  static const saveKey = Key('asset-save');

  @override
  ConsumerState<AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends ConsumerState<AssetEditor> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _year = TextEditingController();
  AssetKind _kind = AssetKind.property;
  var _value = const Money(0);
  var _byFipe = true;
  VehicleType _vehicleType = VehicleType.car;
  late CalendarDate _acquiredOn = _today;
  String? _loanId;
  var _saving = false;
  String? _error;

  CalendarDate get _today =>
      CalendarDate.brazilToday(ref.read(clockProvider).now());

  bool get _priced => _kind == AssetKind.vehicle && _byFipe;

  AssetDraft get _draft => AssetDraft(
    kind: _kind,
    name: _name.text,
    acquiredOn: _acquiredOn,
    value: _priced ? const Money(0) : _value,
    fipe: _priced
        ? FipeVehicle(
            type: _vehicleType,
            code: _code.text.trim(),
            modelYear: int.tryParse(_year.text.trim()) ?? 0,
          )
        : null,
    loanId: _loanId,
  );

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _pickAcquired() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
        _acquiredOn.year,
        _acquiredOn.month,
        _acquiredOn.day,
      ),
      firstDate: DateTime(1950),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (picked == null) return;
    setState(() => _acquiredOn = CalendarDate.fromDateTime(picked));
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final problem = _draft.problemOn(_today);
    setState(() {
      _error = problem == null ? null : assetProblemMessage(l10n, problem);
    });
    if (problem != null) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final failure = await ref
        .read(assetsControllerProvider.notifier)
        .create(_draft);
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
    final palette = context.palette;
    final error = _error;
    final loans = ref.watch(loansControllerProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdSegmented<AssetKind>(
          key: AssetEditor.kindKey,
          segments: [
            CdSegment(AssetKind.property, l10n.assetKindProperty),
            CdSegment(AssetKind.vehicle, l10n.assetKindVehicle),
            CdSegment(AssetKind.other, l10n.assetKindOther),
          ],
          selected: _kind,
          onChanged: (kind) => setState(() => _kind = kind),
        ),
        if (_kind == AssetKind.vehicle) ...[
          SwitchListTile(
            key: AssetEditor.fipeKey,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.assetByFipe),
            subtitle: Text(l10n.assetByFipeHelp),
            value: _byFipe,
            onChanged: (value) => setState(() => _byFipe = value),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (_priced) ...[
          CdSegmented<VehicleType>(
            segments: [
              CdSegment(VehicleType.car, l10n.vehicleCar),
              CdSegment(VehicleType.motorcycle, l10n.vehicleMotorcycle),
              CdSegment(VehicleType.truck, l10n.vehicleTruck),
            ],
            selected: _vehicleType,
            onChanged: (type) => setState(() => _vehicleType = type),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: CdTextField(
                  key: AssetEditor.fipeCodeKey,
                  controller: _code,
                  label: l10n.assetFipeCode,
                  hintText: '000000-0',
                  monospace: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
                    LengthLimitingTextInputFormatter(8),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: CdTextField(
                  key: AssetEditor.modelYearKey,
                  controller: _year,
                  label: l10n.assetModelYear,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.assetFipeHelp,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        CdTextField(
          key: AssetEditor.nameKey,
          controller: _name,
          label: _priced ? l10n.assetNameOptional : l10n.assetName,
          textInputAction: TextInputAction.next,
        ),
        if (!_priced) ...[
          const SizedBox(height: AppSpacing.md),
          CdCurrencyInput(
            key: AssetEditor.valueKey,
            label: l10n.assetValue,
            large: false,
            onChanged: (value) => setState(() => _value = value),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        CdButton.outlined(
          key: AssetEditor.acquiredKey,
          icon: Symbols.event_rounded,
          label: l10n.assetAcquiredOn(_acquiredOn.display),
          onPressed: _pickAcquired,
        ),
        if (loans.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String?>(
            key: AssetEditor.loanKey,
            isExpanded: true,
            initialValue: _loanId,
            decoration: InputDecoration(labelText: l10n.assetLoan),
            items: [
              DropdownMenuItem(child: Text(l10n.assetLoanNone)),
              for (final loan in loans)
                DropdownMenuItem(
                  value: loan.id,
                  child: Text(loan.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _loanId = value),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: AssetEditor.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: AssetEditor.saveKey,
          expand: true,
          label: l10n.assetSave,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
