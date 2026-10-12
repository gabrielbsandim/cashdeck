import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:flutter/material.dart';

/// Where point `index` of a chart sits in a box of `size`.
typedef ChartPointOf = Offset Function(int index, Size size);

/// Touch and drag across [child] to read one point: a guide line, a dot and
/// a tooltip with [labelOf] the point nearest the finger. A drag shows it
/// while the finger moves; a tap keeps it until the next tap.
class CdChartScrub extends StatefulWidget {
  const new({
    required this.count,
    required this.labelOf,
    required this.pointOf,
    required this.child,
    this.dot = true,
    super.key,
  });

  static const tooltipKey = Key('cd-chart-tooltip');

  final int count;

  /// The date and the value of a point, already masked when amounts hide.
  final String Function(int index) labelOf;
  final ChartPointOf pointOf;
  final Widget child;

  /// False for bars, where the guide line alone marks the group.
  final bool dot;

  @override
  State<CdChartScrub> createState() => _CdChartScrubState();
}

class _CdChartScrubState extends State<CdChartScrub> {
  int? _index;
  bool _held = false;

  int _nearest(double dx, Size size) {
    var best = 0;
    var distance = double.infinity;
    for (var index = 0; index < widget.count; index++) {
      final gap = (widget.pointOf(index, size).dx - dx).abs();
      if (gap >= distance) continue;
      best = index;
      distance = gap;
    }
    return best;
  }

  void _show(Offset local, Size size) {
    final index = _nearest(local.dx, size);
    if (index == _index) return;
    CdHaptics.selection();
    setState(() => _index = index);
  }

  void _tap(Offset local, Size size) {
    final index = _nearest(local.dx, size);
    if (_held && index == _index) {
      setState(() {
        _held = false;
        _index = null;
      });
      return;
    }
    _show(local, size);
    _held = true;
  }

  void _release() {
    if (_held) return;
    setState(() => _index = null);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final index = _index;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _tap(details.localPosition, size),
          onHorizontalDragStart: (details) {
            _held = false;
            _show(details.localPosition, size);
          },
          onHorizontalDragUpdate: (details) =>
              _show(details.localPosition, size),
          onHorizontalDragEnd: (_) => _release(),
          onHorizontalDragCancel: _release,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: widget.child),
              if (index != null)
                ..._marker(context, widget.pointOf(index, size), size, index),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _marker(
    BuildContext context,
    Offset point,
    Size size,
    int index,
  ) {
    final palette = context.palette;
    const tooltipWidth = 168.0;
    final left = (point.dx - tooltipWidth / 2).clamp(
      0.0,
      (size.width - tooltipWidth).clamp(0.0, double.infinity),
    );
    return [
      Positioned(
        left: point.dx - 0.5,
        top: 0,
        bottom: 0,
        child: SizedBox(width: 1, child: ColoredBox(color: palette.outline)),
      ),
      if (widget.dot)
        Positioned(
          left: point.dx - 5,
          top: point.dy - 5,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: palette.surfaceContainerLowest,
              shape: BoxShape.circle,
              border: Border.all(color: palette.primary, width: 2),
            ),
          ),
        ),
      Positioned(
        left: left,
        bottom: size.height + AppSpacing.xs,
        width: tooltipWidth,
        child: IgnorePointer(
          child: Container(
            key: CdChartScrub.tooltipKey,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: palette.inverseSurface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              widget.labelOf(index),
              textAlign: TextAlign.center,
              maxLines: 3,
              style: AppTextStyles.labelMd.copyWith(
                color: palette.onInverseSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
