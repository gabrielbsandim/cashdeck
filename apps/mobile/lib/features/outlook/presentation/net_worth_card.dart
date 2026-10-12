import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/insights/cd_comparison_pill.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/investments/presentation/investment_performance.dart';
import 'package:cashdeck/features/investments/presentation/investments_labels.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Net worth today, how it moved since last month and its curve; opens the
/// net worth screen. Hidden while there is nothing to add up.
class NetWorthCard extends ConsumerWidget {
  const new({super.key});

  static const cardKey = Key('home-net-worth');
  static const retryKey = Key('home-net-worth-retry');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final worth = ref.watch(netWorthProvider);
    if (worth case AsyncData(:final value) when value.isEmpty) {
      return const SizedBox.shrink();
    }
    return CdInsightCard(
      key: cardKey,
      title: l10n.netWorthTitle,
      onTap: () {
        CdHaptics.selection();
        context.push(AppRoutes.netWorth).ignore();
      },
      child: switch (worth) {
        AsyncData(:final value) => _Worth(worth: value),
        AsyncError() => PerformanceFailed(
          retryKey: retryKey,
          onRetry: () => ref.invalidate(netWorthProvider),
        ),
        _ => const PerformancePending(height: 140),
      },
    );
  }
}

class _Worth extends StatelessWidget {
  const new({required this.worth});

  final NetWorth worth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdAmount(
          worth.current.total,
          size: CdAmountSize.lg,
          textAlign: TextAlign.start,
          countUp: true,
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: NetWorthChangePill(
            change: worth.fromLastMonth,
            label: l10n.netWorthFromLastMonth,
          ),
        ),
        if (worth.series.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          NetWorthSparkline(
            values: [for (final point in worth.series) point.total.cents],
          ),
        ],
      ],
    );
  }
}

/// The change as a percent, or in reais when the earlier value was zero.
class NetWorthChangePill extends ConsumerWidget {
  const new({required this.change, required this.label, super.key});

  final NetWorthChange change;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    return CdComparisonPill(
      direction: change.direction,
      value: switch (change.percent) {
        final percent? => unsignedPercent(l10n, percent),
        null => MoneyFormat.format(change.amount.abs, hide: hide),
      },
      goodWhen: GoodWhen.up,
      label: label,
    );
  }
}

/// A bare line with a soft fill under it, the shape of the history only.
class NetWorthSparkline extends StatelessWidget {
  const new({required this.values, this.height = 48, super.key});

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: SparklinePainter(
            values: values,
            line: palette.primary,
            area: palette.primaryContainer.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  const new({required this.values, required this.line, required this.area});

  final List<int> values;
  final Color line;
  final Color area;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    // A flat history draws mid-height instead of dividing by zero.
    final span = high == low ? 1 : high - low;
    final step = size.width / (values.length - 1);
    final points = [
      for (final (index, value) in values.indexed)
        Offset(
          index * step,
          high == low
              ? size.height / 2
              : size.height - (value - low) / span * size.height,
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas
      ..drawPath(fill, Paint()..color = area)
      ..drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(points.last, 3, Paint()..color = line);
  }

  @override
  bool shouldRepaint(SparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.line != line ||
      oldDelegate.area != area;
}
