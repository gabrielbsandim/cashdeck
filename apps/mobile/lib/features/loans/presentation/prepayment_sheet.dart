import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';
import 'package:cashdeck/features/loans/loans_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// The yearly rate as the person reads it, two decimals in their locale.
String loanRateText(AppLocalizations l10n, double rate) =>
    NumberFormat.decimalPatternDigits(
      locale: l10n.localeName,
      decimalDigits: 2,
    ).format(rate);

Future<void> showPrepaymentSheet(BuildContext context, Loan loan) =>
    showCdBottomSheet<void>(
      context,
      title: AppLocalizations.of(context).loanPrepayTitle,
      builder: (_) => PrepaymentSheet(loan: loan),
    );

/// What an extra payment today saves, cutting the term.
class PrepaymentSheet extends ConsumerStatefulWidget {
  const new({required this.loan, super.key});

  static const amountKey = Key('loan-prepay-amount');
  static const runKey = Key('loan-prepay-run');
  static const resultKey = Key('loan-prepay-result');
  static const errorKey = Key('loan-prepay-error');

  final Loan loan;

  @override
  ConsumerState<PrepaymentSheet> createState() => _PrepaymentSheetState();
}

class _PrepaymentSheetState extends ConsumerState<PrepaymentSheet> {
  var _amount = const Money(0);
  var _busy = false;
  Prepayment? _result;
  String? _error;

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(simulatePrepaymentProvider)
        .call(widget.loan.id, _amount);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok(:final value):
          _result = value;
        case Err(:final failure):
          _result = null;
          _error = failure.userMessage(l10n);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loan = widget.loan;
    final result = _result;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.loanPrepayYield(
            loanRateText(l10n, loan.effectiveRate),
            loan.indexer,
          ),
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CdCurrencyInput(
          key: PrepaymentSheet.amountKey,
          label: l10n.loanPrepayAmount,
          helperText: l10n.loanPrepayHelp,
          onChanged: (value) => setState(() => _amount = value),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: PrepaymentSheet.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        if (result != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _Result(key: PrepaymentSheet.resultKey, result: result),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: PrepaymentSheet.runKey,
          expand: true,
          label: l10n.loanPrepayRun,
          loading: _busy,
          onPressed: _amount.cents > 0 ? _run : null,
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const new({required this.result, super.key});

  final Prepayment result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdKeyValueRow(
          label: l10n.loanPrepaySaved,
          strong: true,
          value: CdAmount(
            result.saved,
            size: CdAmountSize.row,
            kind: CdAmountKind.income,
          ),
        ),
        CdKeyValueRow(
          label: l10n.loanPrepayInterest,
          value: CdPrivateText(
            (hide) => MoneyFormat.format(result.interestSaved, hide: hide),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.loanPrepayMonths(result.monthsCut),
          style: AppTextStyles.bodyLg.copyWith(
            color: context.palette.onSurface,
          ),
        ),
        if (result.lastDueOn case final lastDueOn?)
          Text(
            l10n.loanPrepayLastDue(lastDueOn.display),
            style: AppTextStyles.bodyMd.copyWith(
              color: context.palette.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
