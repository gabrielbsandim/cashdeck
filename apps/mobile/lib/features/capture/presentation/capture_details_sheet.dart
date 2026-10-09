import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What the user adds when a code lacks it.
typedef CaptureDetails = ({Money? amount, CalendarDate dueDate});

/// Asks the due date, starting at [today], and the amount when [askAmount].
/// Null when the user closes the sheet.
Future<CaptureDetails?> showCaptureDetailsSheet(
  BuildContext context, {
  required bool askAmount,
  required CalendarDate today,
}) {
  final l10n = AppLocalizations.of(context);
  return showCdBottomSheet<CaptureDetails>(
    context,
    title: askAmount ? l10n.captureDetailsTitle : l10n.captureDetailsDueTitle,
    builder: (_) => CaptureDetailsSheet(askAmount: askAmount, today: today),
  );
}

class CaptureDetailsSheet extends StatefulWidget {
  const new({required this.askAmount, required this.today, super.key});

  static const amountKey = Key('capture-details-amount');
  static const submitKey = Key('capture-details-submit');

  final bool askAmount;
  final CalendarDate today;

  @override
  State<CaptureDetailsSheet> createState() => _CaptureDetailsSheetState();
}

class _CaptureDetailsSheetState extends State<CaptureDetailsSheet> {
  var _amount = const Money(0);
  late CalendarDate _dueDate = widget.today;

  bool get _ready => !widget.askAmount || _amount.cents > 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.askAmount
              ? l10n.captureDetailsBody
              : l10n.captureDetailsDueBody,
          style: AppTextStyles.bodyMd.copyWith(color: palette.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (widget.askAmount) ...[
          CdCurrencyInput(
            key: CaptureDetailsSheet.amountKey,
            label: l10n.captureAmountLabel,
            large: false,
            onChanged: (amount) => setState(() => _amount = amount),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        DueDateField(
          date: _dueDate,
          today: widget.today,
          onChanged: (date) => setState(() => _dueDate = date),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: CaptureDetailsSheet.submitKey,
          expand: true,
          label: l10n.captureDetailsSubmit,
          onPressed: _ready
              ? () => Navigator.of(context).pop<CaptureDetails>((
                  amount: widget.askAmount ? _amount : null,
                  dueDate: _dueDate,
                ))
              : null,
        ),
      ],
    );
  }
}

/// The due date row with the system date picker; [date] null reads as taken
/// from the code itself.
class DueDateField extends StatelessWidget {
  const new({
    required this.date,
    required this.today,
    required this.onChanged,
    super.key,
  });

  static const changeKey = Key('due-date-change');

  final CalendarDate? date;
  final CalendarDate today;
  final ValueChanged<CalendarDate> onChanged;

  Future<void> _pick(BuildContext context) async {
    final initial = date ?? today;
    DateTime local(CalendarDate day) => DateTime(day.year, day.month, day.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: local(initial),
      firstDate: local(today.addDays(-365)),
      lastDate: local(today.addDays(3650)),
    );
    if (picked == null) return;
    onChanged(CalendarDate.fromDateTime(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final shown = date;
    return Row(
      children: [
        Icon(Symbols.event_rounded, color: palette.onSurfaceVariant),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.captureDueDateLabel,
                style: AppTextStyles.labelMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              Text(
                shown == null ? l10n.captureDueDateFromCode : shown.display,
                style: AppTextStyles.titleSm.copyWith(color: palette.onSurface),
              ),
            ],
          ),
        ),
        CdButton.text(
          key: changeKey,
          dense: true,
          label: l10n.captureDueDateChange,
          onPressed: () => _pick(context),
        ),
      ],
    );
  }
}
