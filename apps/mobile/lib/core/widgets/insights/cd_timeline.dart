import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

enum CdTimelineState { done, current, future }

final class CdTimelineEntry {
  const new({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.state,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final CdTimelineState state;
}

/// A vertical timeline: done steps checked, the current one ringed, future
/// ones hollow, joined by a line.
class CdTimeline extends StatelessWidget {
  const new({required this.entries, super.key});

  final List<CdTimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final money = context.money;
    return Column(
      children: [
        for (final (index, entry) in entries.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    children: [
                      _Marker(
                        state: entry.state,
                        palette: palette,
                        money: money,
                      ),
                      if (index < entries.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: entry.state == CdTimelineState.done
                                ? money.paid
                                : palette.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.title,
                                style: AppTextStyles.titleSm.copyWith(
                                  color: palette.onSurface,
                                ),
                              ),
                              Text(
                                entry.subtitle,
                                style: AppTextStyles.bodyMd.copyWith(
                                  color: palette.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        entry.trailing,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Marker extends StatelessWidget {
  const new({required this.state, required this.palette, required this.money});

  final CdTimelineState state;
  final AppPalette palette;
  final AppMoneyColors money;

  @override
  Widget build(BuildContext context) => switch (state) {
    CdTimelineState.done => Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: money.paidContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(Symbols.check_rounded, size: 18, color: money.paid),
    ),
    CdTimelineState.current => Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: palette.primary, shape: BoxShape.circle),
      child: Icon(Symbols.schedule_rounded, size: 18, color: palette.onPrimary),
    ),
    CdTimelineState.future => Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.outline, width: 2),
      ),
    ),
  };
}
