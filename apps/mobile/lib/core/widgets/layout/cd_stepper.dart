import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A short flow shown in a line: done steps check, the current one fills.
class CdStepper extends StatelessWidget {
  const new({required this.steps, required this.current, super.key});

  final List<String> steps;

  /// Zero based.
  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final money = context.money;
    return Row(
      children: [
        for (final (index, step) in steps.indexed) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                color: palette.outlineVariant,
              ),
            ),
          _StepMark(
            number: index + 1,
            state: switch (index.compareTo(current)) {
              < 0 => _StepState.done,
              0 => _StepState.current,
              _ => _StepState.next,
            },
            doneColor: money.paid,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              step,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMd.copyWith(
                fontSize: 13,
                color: switch (index.compareTo(current)) {
                  < 0 => money.paid,
                  0 => palette.onSurface,
                  _ => palette.onSurfaceVariant,
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _StepState { done, current, next }

class _StepMark extends StatelessWidget {
  const new({
    required this.number,
    required this.state,
    required this.doneColor,
  });

  final int number;
  final _StepState state;
  final Color doneColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return switch (state) {
      _StepState.done => Icon(
        Symbols.check_circle_rounded,
        size: 18,
        color: doneColor,
      ),
      _StepState.current => CircleAvatar(
        radius: 9,
        backgroundColor: palette.primary,
        child: Text(
          '$number',
          style: AppTextStyles.labelMd.copyWith(
            color: palette.onPrimary,
            fontSize: 11,
          ),
        ),
      ),
      _StepState.next => Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: palette.outline, width: 1.5),
        ),
        child: Text(
          '$number',
          style: AppTextStyles.labelMd.copyWith(
            color: palette.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ),
    };
  }
}
