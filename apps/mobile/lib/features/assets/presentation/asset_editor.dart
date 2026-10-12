import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
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
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/features/assets/assets_providers.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/assets/presentation/assets_controller.dart';
import 'package:cashdeck/features/assets/presentation/vehicle_picker.dart';
import 'package:cashdeck/features/loans/presentation/loans_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Adds a property, vehicle or other good, or edits [asset].
Future<void> showAssetEditor(BuildContext context, {Asset? asset}) async {
  final l10n = AppLocalizations.of(context);
  final saved = await showCdBottomSheet<bool>(
    context,
    title: asset == null ? l10n.assetAdd : l10n.assetEditTitle,
    builder: (_) => AssetEditor(asset: asset),
  );
  if (saved != true || !context.mounted) return;
  await showCdToast(
    context,
    icon: Symbols.task_alt_rounded,
    message: asset == null ? l10n.assetAdded : l10n.assetEdited,
  );
}

String assetProblemMessage(AppLocalizations l10n, AssetProblem problem) =>
    switch (problem) {
      AssetProblem.name => l10n.assetNameMissing,
      AssetProblem.value => l10n.assetValueMissing,
      AssetProblem.vehicle => l10n.assetVehicleMissing,
      AssetProblem.futureDate => l10n.assetFutureDate,
    };

class AssetEditor extends ConsumerStatefulWidget {
  const new({this.asset, super.key});

  final Asset? asset;

  static const kindKey = Key('asset-kind');
  static const nameKey = Key('asset-name');
  static const valueKey = Key('asset-value');
  static const acquiredKey = Key('asset-acquired');
  static const fipeKey = Key('asset-fipe');
  static const brandKey = Key('asset-brand');
  static const modelYearKey = Key('asset-model-year');
  static const modelKey = Key('asset-model');
  static const previewKey = Key('asset-fipe-preview');
  static const currentKey = Key('asset-fipe-current');
  static const loanKey = Key('asset-loan');
  static const errorKey = Key('asset-error');
  static const saveKey = Key('asset-save');

  @override
  ConsumerState<AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends ConsumerState<AssetEditor> {
  final _name = TextEditingController();
  AssetKind _kind = AssetKind.property;
  var _value = const Money(0);
  var _byFipe = true;
  VehicleType _vehicleType = VehicleType.car;
  VehicleOption? _brand;
  VehicleOption? _modelYear;
  VehicleOption? _model;
  CatalogVehicle? _vehicle;
  FipeVehicle? _fipe;
  // The model name the table gave, which a new model replaces.
  String? _modelName;
  var _pricing = false;
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
    byFipe: _byFipe,
    fipe: _priced ? _fipe : null,
    loanId: _loanId,
  );

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    if (asset == null) return;
    _kind = asset.kind;
    _name.text = asset.name;
    _value = asset.value;
    _byFipe = asset.kind != AssetKind.vehicle || asset.fipe != null;
    _vehicleType = asset.fipe?.type ?? VehicleType.car;
    _acquiredOn = asset.acquiredOn;
    _loanId = asset.loan?.id;
    _fipe = asset.fipe;
    _modelName = asset.fipe == null ? null : asset.name;
  }

  @override
  void dispose() {
    _name.dispose();
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

  void _pickType(VehicleType type) => setState(() {
    _vehicleType = type;
    _brand = null;
    _fipe = null;
    _modelYear = null;
    _model = null;
    _vehicle = null;
  });

  Future<void> _pickBrand() async {
    final browse = ref.read(browseVehiclesProvider);
    final brand = await showVehicleOptions(
      context,
      title: AppLocalizations.of(context).vehicleBrand,
      load: () => browse.brands(_vehicleType),
    );
    if (brand == null || !mounted) return;
    setState(() {
      _brand = brand;
      _modelYear = null;
      _fipe = null;
      _model = null;
      _vehicle = null;
    });
  }

  Future<void> _pickModelYear(VehicleOption brand) async {
    final browse = ref.read(browseVehiclesProvider);
    final year = await showVehicleOptions(
      context,
      title: AppLocalizations.of(context).assetModelYear,
      load: () => browse.years(_vehicleType, brand.code),
    );
    if (year == null || !mounted) return;
    setState(() {
      _modelYear = year;
      _model = null;
      _fipe = null;
      _vehicle = null;
    });
  }

  Future<void> _pickModel(VehicleOption brand, VehicleOption year) async {
    final l10n = AppLocalizations.of(context);
    final browse = ref.read(browseVehiclesProvider);
    final model = await showVehicleOptions(
      context,
      title: l10n.vehicleModel,
      load: () => browse.models(_vehicleType, brand.code, int.parse(year.code)),
    );
    if (model == null || !mounted) return;
    setState(() {
      _model = model;
      _vehicle = null;
      _fipe = null;
      _pricing = true;
      _error = null;
    });
    final priced = await browse.price(_vehicleType, brand.code, model);
    if (!mounted) return;
    setState(() {
      _pricing = false;
      switch (priced) {
        case Ok(:final value):
          _vehicle = value;
          _fipe = value.fipe;
          if (_modelName case final previous? when _name.text == previous) {
            _name.text = value.model;
          }
          _modelName = value.model;
        case Err(:final failure):
          _error = failure.userMessage(l10n);
      }
    });
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
    final controller = ref.read(assetsControllerProvider.notifier);
    final asset = widget.asset;
    final failure = asset == null
        ? await controller.create(_draft)
        : await controller.edit(asset, _draft);
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
    final brand = _brand;
    final modelYear = _modelYear;
    final vehicle = _vehicle;
    final loans = ref.watch(loansControllerProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.asset == null)
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
            onChanged: _pickType,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Step(
            key: AssetEditor.brandKey,
            label: l10n.vehicleBrand,
            value: brand?.name,
            onTap: _pickBrand,
          ),
          _Step(
            key: AssetEditor.modelYearKey,
            label: l10n.assetModelYear,
            value: modelYear?.name,
            onTap: brand == null ? null : () => _pickModelYear(brand),
          ),
          _Step(
            key: AssetEditor.modelKey,
            label: l10n.vehicleModel,
            value: _model?.name,
            onTap: brand == null || modelYear == null
                ? null
                : () => _pickModel(brand, modelYear),
          ),
          if (_pricing) const LinearProgressIndicator(),
          if (_fipe case final fipe? when vehicle == null)
            Text(
              l10n.assetFipeCurrent(fipe.code),
              key: AssetEditor.currentKey,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          if (vehicle != null)
            Text(
              l10n.assetFipePreview(
                vehicle.fipe.code,
                MoneyFormat.format(vehicle.price),
              ),
              key: AssetEditor.previewKey,
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
            initial: _value,
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
            // A loan removed since stays unlinked rather than break the list.
            initialValue: loans.any((loan) => loan.id == _loanId)
                ? _loanId
                : null,
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
          onPressed: _pricing ? null : _save,
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const new({required this.label, required this.onTap, this.value, super.key});

  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: CdListRow(
        title: label,
        subtitle: value ?? l10n.vehiclePick,
        titleMaxLines: 1,
        padding: EdgeInsets.zero,
        chevron: true,
        onTap: onTap,
      ),
    );
  }
}
