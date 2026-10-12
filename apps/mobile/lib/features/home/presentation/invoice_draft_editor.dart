import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/home/domain/invoice_draft_edit.dart';
import 'package:cashdeck/features/home/presentation/home_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

String draftProblemMessage(
  AppLocalizations l10n,
  InvoiceDraftProblem problem,
) => switch (problem) {
  InvoiceDraftProblem.customerMissing => l10n.draftCustomerMissing,
  InvoiceDraftProblem.descriptionMissing => l10n.draftDescriptionMissing,
  InvoiceDraftProblem.amountMissing => l10n.draftAmountMissing,
};

/// Loads the draft [draftId] and opens its form; pops true once saved.
class InvoiceDraftEditor extends ConsumerWidget {
  const new({required this.draftId, super.key});

  static const customerKey = Key('draft-editor-customer');
  static const descriptionKey = Key('draft-editor-description');
  static const amountKey = Key('draft-editor-amount');
  static const issueOnKey = Key('draft-editor-issue-on');
  static const saveKey = Key('draft-editor-save');
  static const errorKey = Key('draft-editor-error');

  final String draftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(invoiceDraftProvider(draftId))) {
      AsyncData(:final value) => _DraftForm(draft: value),
      AsyncError(:final error) => CdErrorState(
        failure: failureOf(error),
        onRetry: () => ref.invalidate(invoiceDraftProvider(draftId)),
      ),
      _ => const SizedBox(height: 240, child: CdLoading()),
    };
  }
}

class _DraftForm extends ConsumerStatefulWidget {
  const new({required this.draft});

  final InvoiceDraftDetail draft;

  @override
  ConsumerState<_DraftForm> createState() => _DraftFormState();
}

class _DraftFormState extends ConsumerState<_DraftForm> {
  late final _customer = TextEditingController(text: widget.draft.customer);
  late final _description = TextEditingController(
    text: widget.draft.description,
  );
  late Money _amount = widget.draft.amount;
  late CalendarDate _issueOn = widget.draft.issueOn;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _customer.dispose();
    _description.dispose();
    super.dispose();
  }

  InvoiceDraftEdit get _edit => InvoiceDraftEdit.between(
    widget.draft,
    customer: _customer.text,
    description: _description.text,
    amount: _amount,
    issueOn: _issueOn,
  );

  Future<void> _pickIssueOn() async {
    final today = CalendarDate.brazilToday(ref.read(clockProvider).now());
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_issueOn.year, _issueOn.month, _issueOn.day),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _issueOn = CalendarDate.fromDateTime(picked));
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final edit = _edit;
    final problem = edit.problem;
    setState(
      () =>
          _error = problem == null ? null : draftProblemMessage(l10n, problem),
    );
    if (problem != null) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final failure = await ref
        .read(homeControllerProvider.notifier)
        .updateDraft(widget.draft.id, edit);
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
          key: InvoiceDraftEditor.customerKey,
          controller: _customer,
          label: l10n.draftCustomer,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        CdTextField(
          key: InvoiceDraftEditor.descriptionKey,
          controller: _description,
          label: l10n.draftDescription,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.md),
        CdCurrencyInput(
          key: InvoiceDraftEditor.amountKey,
          label: l10n.draftAmount,
          large: false,
          initial: widget.draft.amount,
          onChanged: (value) => setState(() => _amount = value),
        ),
        const SizedBox(height: AppSpacing.md),
        CdButton.outlined(
          key: InvoiceDraftEditor.issueOnKey,
          icon: Symbols.event_rounded,
          label: l10n.draftIssueOn(_issueOn.display),
          onPressed: _pickIssueOn,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: InvoiceDraftEditor.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: InvoiceDraftEditor.saveKey,
          expand: true,
          label: l10n.draftSave,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
