import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_expand_hero.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/presentation/goal_celebration.dart';
import 'package:cashdeck/features/goals/presentation/goal_editor.dart';
import 'package:cashdeck/features/goals/presentation/goal_labels.dart';
import 'package:cashdeck/features/goals/presentation/goal_ring.dart';
import 'package:cashdeck/features/goals/presentation/goals_controller.dart';
import 'package:cashdeck/features/goals/presentation/goals_screen.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

enum _GoalAction { edit, archive, delete }

/// One goal: the ring, the projection, and for a manual goal the money put
/// in and taken out.
class GoalDetailScreen extends ConsumerWidget {
  const new({required this.goalId, super.key});

  static const menuKey = Key('goal-menu');
  static const addKey = Key('goal-add');
  static const withdrawKey = Key('goal-withdraw');

  static Key actionKey(String name) => Key('goal-action-$name');

  static Key contributionKey(String id) => Key('goal-contribution-$id');

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = goalDetailControllerProvider(goalId);
    final goal = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(
        title: Text(goal.value?.name ?? l10n.goalsTitle),
        actions: [
          if (goal.value case final Goal loaded)
            PopupMenuButton<_GoalAction>(
              key: menuKey,
              onSelected: (action) => _act(context, ref, loaded, action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: actionKey('edit'),
                  value: _GoalAction.edit,
                  child: Text(l10n.goalEdit),
                ),
                PopupMenuItem(
                  key: actionKey('archive'),
                  value: _GoalAction.archive,
                  child: Text(l10n.goalArchive),
                ),
                PopupMenuItem(
                  key: actionKey('delete'),
                  value: _GoalAction.delete,
                  child: Text(l10n.goalDelete),
                ),
              ],
            ),
        ],
      ),
      body: CdExpandHero(
        tag: goalHeroTag(goalId),
        child: switch (goal) {
          AsyncData(:final value) => _GoalBody(goal: value),
          AsyncError(:final error) => CdErrorState(
            failure: failureOf(error),
            onRetry: () => ref.invalidate(provider),
          ),
          _ => const CdSkeleton(),
        },
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Goal goal,
    _GoalAction action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(goalDetailControllerProvider(goalId).notifier);
    switch (action) {
      case _GoalAction.edit:
        await showGoalEditor(context, goal: goal, save: controller.save);
      case _GoalAction.archive:
        final outcome = await controller.archive();
        if (!context.mounted) return;
        await _leaveOr(context, outcome.failure, l10n.goalArchived);
      case _GoalAction.delete:
        final confirmed = await showCdBottomSheet<bool>(
          context,
          title: l10n.goalDeleteTitle(goal.name),
          builder: (_) => const _ConfirmDelete(),
        );
        if (confirmed != true || !context.mounted) return;
        CdHaptics.warning();
        final failure = await controller.delete();
        if (!context.mounted) return;
        await _leaveOr(context, failure, l10n.goalDeleted);
    }
  }

  /// Back to the list once the goal is gone from it, the failure otherwise.
  Future<void> _leaveOr(
    BuildContext context,
    AppFailure? failure,
    String success,
  ) async {
    if (failure == null) context.pop();
    await showOutcomeToast(context, failure, success: success);
  }
}

class _GoalBody extends ConsumerWidget {
  const new({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final required = goalRequiredLine(l10n, goal, hide: hide);
    final linked = goal.linkedName;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.lg,
        AppSpacing.screenGutter,
        AppSpacing.xxl,
      ),
      children: [
        Center(child: GoalRing(goal: goal, size: 160)),
        const SizedBox(height: AppSpacing.lg),
        Text(
          goalProgressLine(l10n, goal, hide: hide),
          textAlign: TextAlign.center,
          style: AppTextStyles.titleMd.copyWith(color: palette.onSurface),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: CdStatusBadge(
            tone: goalStatusTone(goal.status),
            label: goalStatusLabel(l10n, goal.status),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Symbols.trending_up_rounded, color: palette.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    l10n.goalProjectionTitle,
                    style: AppTextStyles.titleSm.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                goalProjectionLine(l10n, goal, hide: hide),
                style: AppTextStyles.bodyLg.copyWith(color: palette.onSurface),
              ),
              if (required != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(required, style: secondary),
              ],
              if (!goal.isDone) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.goalRemaining(
                    MoneyFormat.whole(goal.remaining, hide: hide),
                  ),
                  style: secondary,
                ),
              ],
              if (linked != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.goalLinked(linked), style: secondary),
              ],
            ],
          ),
        ),
        if (goal.takesContributions) ...[
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: CdButton.filled(
                  key: GoalDetailScreen.addKey,
                  icon: Symbols.add_rounded,
                  label: l10n.goalContributionAdd,
                  onPressed: () => _contribute(context, ref),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: CdButton.outlined(
                  key: GoalDetailScreen.withdrawKey,
                  icon: Symbols.remove_rounded,
                  label: l10n.goalContributionWithdraw,
                  onPressed: () => _contribute(context, ref, withdraw: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          CdSectionHeader(title: l10n.goalContributionsTitle),
          if (goal.contributions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(l10n.goalContributionsEmpty, style: secondary),
            ),
          for (final contribution in goal.contributions)
            _ContributionRow(goal: goal, contribution: contribution),
        ],
      ],
    );
  }

  Future<void> _contribute(
    BuildContext context,
    WidgetRef ref, {
    bool withdraw = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final outcome = await showCdBottomSheet<GoalOutcome>(
      context,
      title: withdraw
          ? l10n.goalContributionWithdraw
          : l10n.goalContributionAdd,
      builder: (_) => ContributionSheet(goalId: goal.id, withdraw: withdraw),
    );
    if (outcome == null || !context.mounted) return;
    if (outcome.reached) {
      await celebrateGoal(context, goal.name);
      return;
    }
    await showOutcomeToast(context, null, success: l10n.goalContributionSaved);
  }
}

class _ContributionRow extends ConsumerWidget {
  const new({required this.goal, required this.contribution});

  final Goal goal;
  final GoalContribution contribution;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final money = context.money;
    final out = contribution.amount.isNegative;
    return CdListRow(
      key: GoalDetailScreen.contributionKey(contribution.id),
      icon: out ? Symbols.south_west_rounded : Symbols.north_east_rounded,
      title: MoneyFormat.format(
        contribution.amount,
        hide: hide,
        sign: MoneySign.plus,
      ),
      subtitle: [contribution.on.display, ?contribution.note].join(' · '),
      trailing: IconButton(
        tooltip: l10n.goalContributionRemove,
        icon: Icon(Symbols.delete_rounded, color: money.failed),
        onPressed: () async {
          final outcome = await ref
              .read(goalDetailControllerProvider(goal.id).notifier)
              .removeContribution(contribution.id);
          if (!context.mounted) return;
          await showOutcomeToast(
            context,
            outcome.failure,
            success: l10n.goalContributionRemoved,
          );
        },
      ),
    );
  }
}

/// The amount and an optional note for money put in or taken out.
class ContributionSheet extends ConsumerStatefulWidget {
  const new({required this.goalId, this.withdraw = false, super.key});

  static const amountKey = Key('goal-contribution-amount');
  static const noteKey = Key('goal-contribution-note');
  static const saveKey = Key('goal-contribution-save');
  static const errorKey = Key('goal-contribution-error');

  final String goalId;
  final bool withdraw;

  @override
  ConsumerState<ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends ConsumerState<ContributionSheet> {
  final _note = TextEditingController();
  var _amount = const Money(0);
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_amount.cents <= 0) {
      setState(() => _error = l10n.goalContributionMissing);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final outcome = await ref
        .read(goalDetailControllerProvider(widget.goalId).notifier)
        .contribute(widget.withdraw ? -_amount : _amount, note: _note.text);
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
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdCurrencyInput(
          key: ContributionSheet.amountKey,
          label: l10n.goalContributionAmount,
          onChanged: (value) => setState(() => _amount = value),
        ),
        const SizedBox(height: AppSpacing.md),
        CdTextField(
          key: ContributionSheet.noteKey,
          controller: _note,
          label: l10n.goalContributionNote,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            key: ContributionSheet.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: ContributionSheet.saveKey,
          expand: true,
          label: widget.withdraw
              ? l10n.goalContributionWithdraw
              : l10n.goalContributionAdd,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _ConfirmDelete extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.goalDeleteMessage,
          style: AppTextStyles.bodyLg.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.danger(
          key: GoalDetailScreen.actionKey('confirm-delete'),
          expand: true,
          label: l10n.goalDelete,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          expand: true,
          label: l10n.cancelButton,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
