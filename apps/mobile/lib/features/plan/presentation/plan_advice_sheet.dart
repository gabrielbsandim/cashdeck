import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/plan_providers.dart';
import 'package:cashdeck/features/plan/presentation/plan_controller.dart';
import 'package:cashdeck/features/plan/presentation/plan_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Asks the model how to arrange the plan, or where the goal [goalId] fits,
/// and applies the proposal once accepted.
Future<void> showPlanAdvice(BuildContext context, {String? goalId}) async {
  final l10n = AppLocalizations.of(context);
  final message = await showCdBottomSheet<String>(
    context,
    title: l10n.planAdviceTitle,
    builder: (_) => PlanAdviceSheet(goalId: goalId),
  );
  if (message == null || !context.mounted) return;
  await showCdToast(
    context,
    icon: Symbols.auto_awesome_rounded,
    message: message,
  );
}

class PlanAdviceSheet extends ConsumerStatefulWidget {
  const new({this.goalId, super.key});

  final String? goalId;

  static const loadingKey = Key('plan-advice-loading');
  static const failedKey = Key('plan-advice-failed');
  static const retryKey = Key('plan-advice-retry');
  static const applyKey = Key('plan-advice-apply');
  static const keepKey = Key('plan-advice-keep');

  static Key rowKey(String id) => Key('plan-advice-$id');

  @override
  ConsumerState<PlanAdviceSheet> createState() => _PlanAdviceSheetState();
}

class _PlanAdviceSheetState extends ConsumerState<PlanAdviceSheet> {
  late Future<Result<PlanAdvice>> _advice = _ask();
  var _applying = false;
  String? _error;

  Future<Result<PlanAdvice>> _ask() =>
      ref.read(advisePlanProvider).call(goalId: widget.goalId);

  void _retry() => setState(() {
    _advice = _ask();
  });

  Future<void> _apply(PlanAdvice advice) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() => _applying = true);
    final failure = await ref
        .read(planControllerProvider.notifier)
        .applyAdvice(advice);
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(l10n.planAdviceApplied);
      return;
    }
    setState(() {
      _applying = false;
      _error = failure.userMessage(l10n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Result<PlanAdvice>>(
      future: _advice,
      builder: (context, snapshot) => switch (snapshot.data) {
        null => Padding(
          key: PlanAdviceSheet.loadingKey,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.planAdviceLoading, style: AppTextStyles.bodyMd),
            ],
          ),
        ),
        Err(:final failure) => CdInlineBanner(
          key: PlanAdviceSheet.failedKey,
          icon: Symbols.error_rounded,
          tone: MoneyTone.failed,
          message: failure.userMessage(l10n),
          actionLabel: l10n.planAdviceRetry,
          actionKey: PlanAdviceSheet.retryKey,
          onAction: _retry,
        ),
        Ok(:final value) => _proposal(l10n, value),
      },
    );
  }

  Widget _proposal(AppLocalizations l10n, PlanAdvice advice) {
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdInlineBanner(
          icon: Symbols.auto_awesome_rounded,
          message: advice.summary,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final (index, goal) in advice.goals.indexed)
          _AdviceRow(
            key: PlanAdviceSheet.rowKey(goal.id),
            position: index + 1,
            goal: goal,
            highlighted: goal.id == advice.goalId,
          ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: PlanAdviceSheet.applyKey,
          expand: true,
          label: l10n.planAdviceApply,
          loading: _applying,
          onPressed: () => _apply(advice),
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          key: PlanAdviceSheet.keepKey,
          expand: true,
          label: l10n.planAdviceKeep,
          onPressed: _applying ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _AdviceRow extends StatelessWidget {
  const new({
    required this.position,
    required this.goal,
    required this.highlighted,
    super.key,
  });

  final int position;
  final PlanAdviceGoal goal;
  final bool highlighted;

  String _when(AppLocalizations l10n, YearMonth? month, PlanStatus status) =>
      month == null ? planStatusLabel(l10n, status) : planMonth(l10n, month);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final muted = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final now = _when(l10n, goal.month, goal.status);
    final then = _when(l10n, goal.proposedMonth, goal.proposedStatus);
    final notBefore = goal.notBefore;
    final reason = goal.reason;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: highlighted ? palette.primaryContainer : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: palette.surfaceContainerHigh,
            child: Text(
              '$position',
              style: AppTextStyles.labelMd.copyWith(color: palette.onSurface),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.name,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  goal.moves
                      ? l10n.planAdviceMoves(now, then)
                      : l10n.planAdviceStays(now),
                  style: goal.moves
                      ? AppTextStyles.bodyMd.copyWith(color: palette.primary)
                      : muted,
                ),
                if (notBefore != null)
                  Text(
                    l10n.planNotBefore(planMonth(l10n, notBefore)),
                    style: muted,
                  ),
                if (reason != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(reason, style: muted),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
