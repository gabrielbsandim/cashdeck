import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Spend against a limit, with ticks at 80% and 100%. Past 80% it turns
/// pending and says so; past 100% it turns overdue.
class CdBudgetBar extends ConsumerWidget {
  const new({
    required this.icon,
    required this.name,
    required this.spent,
    required this.limit,
    this.showAmounts = false,
    super.key,
  });

  static const attention = 0.8;

  final IconData icon;
  final String name;
  final Money spent;
  final Money limit;

  /// `R$ 152 / R$ 400` instead of the percentage.
  final bool showAmounts;

  double get ratio => limit.cents == 0 ? 0 : spent.cents / limit.cents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final money = context.money;
    final hide = ref.watch(hideAmountsProvider);
    final ratio = this.ratio;
    final (fill, badge) = switch (ratio) {
      > 1 => (
        money.overdue,
        CdStatusBadge(
          tone: MoneyTone.overdue,
          label: l10n.budgetExceeded,
          icon: Symbols.error_rounded,
        ),
      ),
      >= attention => (
        money.pending,
        CdStatusBadge(
          tone: MoneyTone.pending,
          label: l10n.budgetAttention,
          icon: Symbols.warning_rounded,
        ),
      ),
      _ => (palette.primary, null),
    };
    final figure = showAmounts
        ? '${MoneyFormat.whole(spent, hide: hide)} / ${MoneyFormat.whole(limit, hide: hide)}'
        : '${(ratio * 100).round()}%';
    return Semantics(
      label: l10n.budgetSemantics(name, '${(ratio * 100).round()}'),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: palette.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    name,
                    style: AppTextStyles.bodyLg.copyWith(
                      color: palette.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null) ...[
                  badge,
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(
                  figure,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 12,
              child: CustomPaint(
                painter: _BudgetPainter(
                  ratio: ratio,
                  fill: fill,
                  track: palette.surfaceContainerHigh,
                  tick: palette.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetPainter extends CustomPainter {
  const new({
    required this.ratio,
    required this.fill,
    required this.track,
    required this.tick,
  });

  final double ratio;
  final Color fill;
  final Color track;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 8.0;
    final top = (size.height - barHeight) / 2;
    const radius = Radius.circular(4);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, size.width, barHeight),
          radius,
        ),
        Paint()..color = track,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, size.width * ratio.clamp(0, 1), barHeight),
          radius,
        ),
        Paint()..color = fill,
      );
    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 1.5;
    for (final mark in [CdBudgetBar.attention, 1.0]) {
      final x = (size.width * mark).clamp(1.0, size.width - 1);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tickPaint);
    }
  }

  @override
  bool shouldRepaint(_BudgetPainter oldDelegate) =>
      oldDelegate.ratio != ratio ||
      oldDelegate.fill != fill ||
      oldDelegate.track != track;
}
