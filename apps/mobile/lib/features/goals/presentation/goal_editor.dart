import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/presentation/goal_celebration.dart';
import 'package:cashdeck/features/goals/presentation/goal_labels.dart';
import 'package:cashdeck/features/goals/presentation/goals_controller.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef SaveGoalDraft = Future<GoalOutcome> Function(GoalDraft draft);

const Set<AccountType> _savingTypes = {
  AccountType.checking,
  AccountType.savings,
  AccountType.investment,
  AccountType.wallet,
};

/// Creates a goal, or edits [goal]; [save] decides where the draft goes.
Future<void> showGoalEditor(
  BuildContext context, {
  required SaveGoalDraft save,
  Goal? goal,
}) async {
  final l10n = AppLocalizations.of(context);
  final outcome = await showCdBottomSheet<GoalOutcome>(
    context,
    title: goal == null ? l10n.goalNew : l10n.goalEdit,
    builder: (_) => GoalEditor(goal: goal, save: save),
  );
  if (outcome == null || !context.mounted) return;
  if (outcome.reached) {
    await celebrateGoal(context, outcome.goal!.name);
  }
}

class GoalEditor extends ConsumerStatefulWidget {
  const new({required this.save, this.goal, super.key});

  static const nameKey = Key('goal-name');
  static const targetKey = Key('goal-target');
  static const initialKey = Key('goal-initial');
  static const deadlineKey = Key('goal-deadline');
  static const clearDeadlineKey = Key('goal-deadline-clear');
  static const accountKey = Key('goal-account');
  static const saveKey = Key('goal-save');
  static const errorKey = Key('goal-error');

  final Goal? goal;
  final SaveGoalDraft save;

  @override
  ConsumerState<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<GoalEditor> {
  late final _name = TextEditingController(text: widget.goal?.name);
  late Money _target = widget.goal?.target ?? const Money(0);
  var _initial = const Money(0);
  late CalendarDate? _deadline = widget.goal?.deadline;
  late String? _accountId = widget.goal?.accountId;
  var _submitted = false;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  CalendarDate get _today =>
      CalendarDate.brazilToday(ref.read(clockProvider).now());

  GoalDraft get _draft => GoalDraft(
    name: _name.text,
    target: _target,
    deadline: _deadline,
    accountId: _accountId,
    initial: _initial,
  );

  Future<void> _pickDeadline() async {
    final today = _today;
    final start = _deadline ?? today.addDays(365);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(start.year, start.month, start.day),
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 50),
    );
    if (picked == null) return;
    setState(() => _deadline = CalendarDate.fromDateTime(picked));
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final problem = _draft.problemOn(_today);
    setState(() {
      _submitted = true;
      _error = problem == null ? null : goalProblemMessage(l10n, problem);
    });
    if (problem != null) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final outcome = await widget.save(_draft);
    if (!mounted) return;
    final failure = outcome.failure;
    if (failure == null) {
      navigator.pop(outcome);
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
    final deadline = _deadline;
    final accounts =
        ref
            .watch(transactionAccountsProvider)
            .value
            ?.where(
              (account) =>
                  account.owner == EntityKind.personal &&
                  _savingTypes.contains(account.type),
            )
            .toList() ??
        const <TransactionAccount>[];
    final linkable = {for (final account in accounts) account.id};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdTextField(
          key: GoalEditor.nameKey,
          controller: _name,
          label: l10n.goalName,
          textInputAction: TextInputAction.next,
          errorText: _submitted && _name.text.trim().isEmpty
              ? l10n.goalNameMissing
              : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        CdCurrencyInput(
          key: GoalEditor.targetKey,
          label: l10n.goalTarget,
          large: false,
          initial: _target,
          onChanged: (value) => setState(() => _target = value),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: CdButton.outlined(
                key: GoalEditor.deadlineKey,
                icon: Symbols.event_rounded,
                label: deadline == null
                    ? l10n.goalDeadlineNone
                    : l10n.goalDeadlineOn(deadline.display),
                onPressed: _pickDeadline,
              ),
            ),
            if (deadline != null)
              IconButton(
                key: GoalEditor.clearDeadlineKey,
                tooltip: l10n.goalDeadlineClear,
                icon: const Icon(Symbols.close_rounded),
                onPressed: () => setState(() => _deadline = null),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String?>(
          key: GoalEditor.accountKey,
          isExpanded: true,
          initialValue: linkable.contains(_accountId) ? _accountId : null,
          decoration: InputDecoration(labelText: l10n.goalAccount),
          items: [
            DropdownMenuItem(
              child: Text(
                l10n.goalAccountNone,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final account in accounts)
              DropdownMenuItem(
                value: account.id,
                child: Text(account.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) => setState(() => _accountId = id),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _accountId == null
              ? l10n.goalAccountManualHelp
              : l10n.goalAccountHelp,
          style: AppTextStyles.bodyMd.copyWith(color: palette.onSurfaceVariant),
        ),
        if (widget.goal == null && _accountId == null) ...[
          const SizedBox(height: AppSpacing.md),
          CdCurrencyInput(
            key: GoalEditor.initialKey,
            label: l10n.goalInitial,
            large: false,
            onChanged: (value) => setState(() => _initial = value),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: GoalEditor.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: GoalEditor.saveKey,
          expand: true,
          label: l10n.goalSave,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
