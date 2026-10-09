import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// How a step reads. [ready] is the current step 3: the guaranteed path,
/// drawn in the accent card, never as a failure.
enum CdLadderState { done, active, failed, upcoming, expired, skipped, ready }

final class CdLadderLine {
  const new(this.text, {this.time});

  final String text;
  final String? time;
}

final class CdLadderStep {
  const new({
    required this.number,
    required this.title,
    required this.icon,
    required this.state,
    required this.tone,
    this.badge,
    this.trailingLabel,
    this.lines = const [],
    this.stepDown,
    this.body,
    this.actions = const [],
    this.summary,
    this.key,
  });

  final int number;
  final String title;
  final IconData icon;
  final CdLadderState state;

  /// The step's own color while it runs: scheduled, awaitingApproval or
  /// assisted.
  final MoneyTone tone;
  final CdStatusBadge? badge;
  final String? trailingLabel;
  final List<CdLadderLine> lines;

  /// The visible step-down after a failure, with time and destination.
  final String? stepDown;
  final String? body;
  final List<Widget> actions;

  /// The one line a past step collapses to once a later step is current.
  final String? summary;
  final Key? key;
}

/// The heart of the app: every step a bill can be paid by, what was tried on
/// each, why it stepped down and what happens next.
class CdPaymentLadder extends StatelessWidget {
  const new({
    required this.title,
    required this.subtitle,
    required this.steps,
    this.nextAction,
    this.footnote,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<CdLadderStep> steps;
  final String? nextAction;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final nextAction = this.nextAction;
    final footnote = this.footnote;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                title,
                style: AppTextStyles.titleMd.copyWith(color: palette.onSurface),
              ),
              Text(
                subtitle,
                style: AppTextStyles.bodyMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Progress(steps: steps),
          const SizedBox(height: AppSpacing.md),
          for (final (index, step) in steps.indexed)
            _StepView(
              key: step.key,
              step: step,
              last: index == steps.length - 1,
            ),
          if (nextAction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: palette.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.notifications_active_rounded,
                    color: palette.primary,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      nextAction,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              footnote,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const new({required this.steps});

  final List<CdLadderStep> steps;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final money = context.money;
    return Row(
      children: [
        for (final (index, step) in steps.indexed) ...[
          if (index > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SizedBox(
              height: 4,
              child: step.state == CdLadderState.skipped
                  ? CustomPaint(painter: _Dotted(palette.outline))
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: switch (step.state) {
                          CdLadderState.failed => money.failed,
                          CdLadderState.done => money.paid,
                          CdLadderState.active || CdLadderState.ready =>
                            money.tone(step.tone).foreground,
                          CdLadderState.expired => palette.outline,
                          CdLadderState.upcoming ||
                          CdLadderState.skipped => palette.outlineVariant,
                        },
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Dotted extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, 3, size.height),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Dotted oldDelegate) => oldDelegate.color != color;
}

class _StepView extends StatefulWidget {
  const new({required this.step, required this.last, super.key});

  final CdLadderStep step;
  final bool last;

  @override
  State<_StepView> createState() => _StepViewState();
}

class _StepViewState extends State<_StepView> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    if (step.state == CdLadderState.ready) return _ReadyStep(step: step);
    final summary = step.summary;
    if (summary != null && !_expanded) {
      return _CollapsedStep(
        step: step,
        summary: summary,
        onExpand: () => setState(() => _expanded = true),
      );
    }
    return _OpenStep(step: step, last: widget.last);
  }
}

class _StepIcon extends StatelessWidget {
  const new({required this.step});

  final CdLadderStep step;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final money = context.money;
    final tone = money.tone(step.tone);
    final (background, foreground, border, icon) = switch (step.state) {
      CdLadderState.failed => (
        money.failedContainer,
        money.failed,
        null,
        step.icon,
      ),
      CdLadderState.done => (
        money.paidContainer,
        money.paid,
        null,
        Symbols.check_rounded,
      ),
      CdLadderState.active || CdLadderState.ready => (
        tone.foreground,
        palette.surface,
        null,
        step.icon,
      ),
      CdLadderState.skipped => (
        Colors.transparent,
        palette.onSurfaceVariant,
        palette.outline,
        Symbols.block_rounded,
      ),
      CdLadderState.upcoming || CdLadderState.expired => (
        palette.surfaceContainerHigh,
        palette.onSurfaceVariant,
        null,
        step.icon,
      ),
    };
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border, width: 1.5),
      ),
      child: Icon(icon, size: 18, color: foreground, fill: 1),
    );
  }
}

class _OpenStep extends StatelessWidget {
  const new({required this.step, required this.last});

  final CdLadderStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final muted = step.state == CdLadderState.skipped;
    final titleColor = muted ? palette.onSurfaceVariant : palette.onSurface;
    final badge = step.badge;
    final trailing = step.trailingLabel;
    final stepDown = step.stepDown;
    final body = step.body;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              _StepIcon(step: step),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    color: palette.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 32),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${step.number} · ${step.title}',
                            style: AppTextStyles.titleSm.copyWith(
                              color: titleColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (trailing != null)
                          Text(
                            trailing,
                            style: AppTextStyles.bodyMd.copyWith(
                              fontSize: 13,
                              color: palette.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: badge,
                      ),
                    ),
                  for (final line in step.lines) _LineView(line: line),
                  if (stepDown != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Row(
                        children: [
                          Icon(
                            Symbols.south_rounded,
                            size: 16,
                            color: palette.onSurface,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              stepDown,
                              style: AppTextStyles.bodyMd.copyWith(
                                color: palette.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (body != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        body,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (step.actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: step.actions,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineView extends StatelessWidget {
  const new({required this.line});

  final CdLadderLine line;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final time = line.time;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (time != null) ...[
            Text(
              time,
              style: AppTextStyles.code.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.onSurface,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              line.text,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedStep extends StatelessWidget {
  const new({
    required this.step,
    required this.summary,
    required this.onExpand,
  });

  final CdLadderStep step;
  final String summary;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onExpand,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          children: [
            _StepIcon(step: step),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${step.number} · ${step.title}',
                    style: AppTextStyles.titleSm.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  Text(
                    summary,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Symbols.expand_more_rounded, color: palette.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const new({required this.step});

  final CdLadderStep step;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final body = step.body;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StepIcon(step: step),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${step.number} · ${step.title}',
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onPrimaryContainer,
                      ),
                    ),
                    if (body != null)
                      Text(
                        body,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: palette.onPrimaryContainer,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          for (final action in step.actions) ...[
            const SizedBox(height: AppSpacing.md),
            action,
          ],
        ],
      ),
    );
  }
}
