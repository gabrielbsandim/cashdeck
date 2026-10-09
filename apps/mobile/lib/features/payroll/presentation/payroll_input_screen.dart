import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/home/presentation/home_labels.dart';
import 'package:cashdeck/features/payroll/domain/payroll.dart';
import 'package:cashdeck/features/payroll/payroll_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

final FutureProvider<PayrollSheet> payrollSheetProvider =
    FutureProvider.autoDispose<PayrollSheet>(
      (ref) async =>
          (await ref.watch(payrollRepositoryProvider).sheet()).orThrow,
      retry: noRetry,
    );

/// The month's payroll, which feeds Fator R and so the DAS estimate.
class PayrollInputScreen extends ConsumerWidget {
  const new({super.key});

  static const saveKey = Key('payroll-save');
  static const proLaboreKey = Key('payroll-pro-labore');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sheet = ref.watch(payrollSheetProvider);
    final month = sheet.value?.current.month;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          month == null
              ? l10n.payrollMenu
              : l10n.payrollTitle(monthName(context, month)),
        ),
      ),
      body: switch (sheet) {
        AsyncData(:final value) => _PayrollForm(sheet: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(payrollSheetProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _PayrollForm extends ConsumerStatefulWidget {
  const new({required this.sheet});

  final PayrollSheet sheet;

  @override
  ConsumerState<_PayrollForm> createState() => _PayrollFormState();
}

class _PayrollFormState extends ConsumerState<_PayrollForm> {
  late PayrollMonth _current = widget.sheet.current;
  var _saving = false;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final result = await ref.read(payrollRepositoryProvider).save(_current);
    if (!mounted) return;
    setState(() => _saving = false);
    await showOutcomeToast(context, switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    }, success: l10n.payrollSavedToast);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final fator = FatorR.of(
      current: _current,
      history: widget.sheet.history,
      revenue12: widget.sheet.revenue12,
    );
    final percent = (fator.ratio * 100).toStringAsFixed(1).replaceAll('.', ',');
    final annexIii = fator.annex == SimplesAnnex.iii;
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final fields = [
      (
        l10n.payrollProLabore,
        _current.proLabore,
        (Money value) => _current.copyWith(proLabore: value),
        PayrollInputScreen.proLaboreKey,
      ),
      (
        l10n.payrollSalaries,
        _current.salaries,
        (Money value) => _current.copyWith(salaries: value),
        const Key('payroll-salaries'),
      ),
      (
        l10n.payrollFgts,
        _current.fgts,
        (Money value) => _current.copyWith(fgts: value),
        const Key('payroll-fgts'),
      ),
    ];
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: secondary)),
          Text(
            value,
            style: AppTextStyles.labelLg.copyWith(color: palette.onSurface),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        Text(l10n.payrollIntro, style: secondary),
        const SizedBox(height: AppSpacing.lg),
        for (final (label, value, update, key) in fields) ...[
          CdCurrencyInput(
            key: key,
            label: label,
            initial: value,
            large: false,
            onChanged: (next) => setState(() => _current = update(next)),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.payrollMonthTotal,
                style: AppTextStyles.titleSm.copyWith(color: palette.onSurface),
              ),
            ),
            CdAmount(_current.total, size: CdAmountSize.sm),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line(
                l10n.payroll12Months,
                MoneyFormat.format(fator.payroll12, hide: hide),
              ),
              line(
                l10n.revenue12Months,
                MoneyFormat.format(fator.revenue12, hide: hide),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.fatorR(percent),
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  CdStatusBadge(
                    tone: annexIii ? MoneyTone.paid : MoneyTone.pending,
                    icon: annexIii
                        ? Symbols.check_circle_rounded
                        : Symbols.warning_rounded,
                    label: annexIii ? l10n.annexIii : l10n.annexV,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _FatorBar(ratio: fator.ratio),
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.fatorRMarker, style: secondary.copyWith(fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (widget.sheet.history.isNotEmpty)
          CdSectionHeader(title: l10n.payrollPreviousMonths, small: true),
        for (final month in widget.sheet.history.take(3))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    capitalized(monthName(context, month.month)),
                    style: AppTextStyles.bodyLg.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                ),
                CdAmount(month.total, size: CdAmountSize.row),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Symbols.check_circle_rounded,
                  size: 20,
                  color: context.money.paid,
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        CdButton.filled(
          key: PayrollInputScreen.saveKey,
          expand: true,
          loading: _saving,
          label: l10n.payrollSaveButton,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _FatorBar extends StatelessWidget {
  const new({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final marker = width * FatorR.threshold / 0.5;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: palette.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              Container(
                height: 6,
                width: width * (ratio / 0.5).clamp(0, 1),
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              Positioned(
                left: marker - 1,
                child: Container(
                  width: 2,
                  height: 12,
                  color: palette.onSurface,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
