import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
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
import 'package:cashdeck/features/goals/presentation/goal_appearance.dart';
import 'package:cashdeck/features/goals/presentation/goal_celebration.dart';
import 'package:cashdeck/features/goals/presentation/goal_labels.dart';
import 'package:cashdeck/features/goals/presentation/goals_controller.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/investments_providers.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef SaveGoalDraft = Future<GoalOutcome> Function(GoalDraft draft);

/// What the goal follows: an account or an investment, by id.
typedef GoalLink = (GoalSource source, String id);

/// The person's investments, whatever entity the home shows, since goals
/// belong to the person.
final FutureProvider<List<InvestmentPosition>> goalInvestmentsProvider =
    FutureProvider.autoDispose<List<InvestmentPosition>>(
      (ref) async =>
          (await ref.watch(loadInvestmentsProvider)(EntityScope.personal))
              .orThrow
              .positions,
      retry: noRetry,
    );

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
  static Key iconKey(String name) => Key('goal-icon-$name');
  static Key colorKey(String name) => Key('goal-color-$name');
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
  late GoalLink? _link = switch (widget.goal) {
    Goal(accountId: final id?) => (GoalSource.account, id),
    Goal(investmentId: final id?) => (GoalSource.investment, id),
    _ => null,
  };
  late String? _icon = widget.goal?.icon;
  late String? _color = widget.goal?.color;
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
    accountId: _linkedId(GoalSource.account),
    investmentId: _linkedId(GoalSource.investment),
    icon: _icon,
    color: _color,
    initial: _initial,
  );

  String? _linkedId(GoalSource source) => switch (_link) {
    (final linked, final id) when linked == source => id,
    _ => null,
  };

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
    final investments =
        ref.watch(goalInvestmentsProvider).value ??
        const <InvestmentPosition>[];
    final linkable = <GoalLink>{
      for (final account in accounts) (GoalSource.account, account.id),
      for (final position in investments) (GoalSource.investment, position.id),
    };
    final link = _link;
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
        _IconPicker(
          selected: _icon,
          tint: goalTint(context, _color)?.fill ?? palette.primary,
          onChanged: (name) => setState(() => _icon = name),
        ),
        const SizedBox(height: AppSpacing.md),
        _ColorPicker(
          selected: _color,
          onChanged: (name) => setState(() => _color = name),
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
        DropdownButtonFormField<GoalLink?>(
          key: GoalEditor.accountKey,
          isExpanded: true,
          initialValue: linkable.contains(link) ? link : null,
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
                value: (GoalSource.account, account.id),
                child: Text(account.name, overflow: TextOverflow.ellipsis),
              ),
            for (final position in investments)
              DropdownMenuItem(
                value: (GoalSource.investment, position.id),
                child: Text(
                  l10n.goalInvestmentOption(
                    position.name,
                    position.institution,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() => _link = value),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          switch (link?.$1) {
            GoalSource.account => l10n.goalAccountHelp,
            GoalSource.investment => l10n.goalInvestmentHelp,
            GoalSource.manual || null => l10n.goalAccountManualHelp,
          },
          style: AppTextStyles.bodyMd.copyWith(color: palette.onSurfaceVariant),
        ),
        if (widget.goal == null && link == null) ...[
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

/// The curated icons; tapping the chosen one again goes back to the default.
class _IconPicker extends StatelessWidget {
  const new({
    required this.selected,
    required this.tint,
    required this.onChanged,
  });

  final String? selected;
  final Color tint;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return _Picker(
      label: l10n.goalIconLabel,
      children: [
        for (final MapEntry(key: name, value: icon) in goalIcons.entries)
          _Choice(
            key: GoalEditor.iconKey(name),
            semanticsLabel: l10n.goalIconLabel,
            selected: name == selected,
            onTap: () => onChanged(name == selected ? null : name),
            child: Icon(
              icon,
              color: name == selected ? tint : palette.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// The app's series colours; tapping the chosen one again clears it.
class _ColorPicker extends StatelessWidget {
  const new({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Picker(
      label: l10n.goalColorLabel,
      children: [
        for (final name in goalColors)
          _Choice(
            key: GoalEditor.colorKey(name),
            semanticsLabel: l10n.goalColorLabel,
            selected: name == selected,
            onTap: () => onChanged(name == selected ? null : name),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: goalTint(context, name)?.fill,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 24),
            ),
          ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  const new({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: children,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const new({
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String semanticsLabel;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: AppSpacing.minTouchTarget,
          height: AppSpacing.minTouchTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? palette.surfaceContainerHigh : null,
            border: Border.all(
              color: selected ? palette.primary : palette.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
