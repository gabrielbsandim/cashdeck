import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

final class CdSegment<T> {
  const new(this.value, this.label, {this.enabled = true, this.key});

  final T value;
  final String label;
  final bool enabled;
  final Key? key;
}

/// Below this width the selected segment drops its check so the label fits.
const double _checkFits = 72;

/// 40 high, 48 hit; the selected segment fills with the primary container.
class CdSegmented<T> extends StatelessWidget {
  const new({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<CdSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
      child: Center(
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: palette.outline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: Row(
              children: [
                for (final (index, segment) in segments.indexed)
                  Expanded(
                    child: _Segment(
                      segment: segment,
                      selected: segment.value == selected,
                      divider: index > 0,
                      onTap: () => onChanged(segment.value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const new({
    required this.segment,
    required this.selected,
    required this.divider,
    required this.onTap,
  });

  final CdSegment<T> segment;
  final bool selected;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ink = switch ((segment.enabled, selected)) {
      (false, _) => palette.onSurfaceVariant.withValues(alpha: 0.6),
      (true, true) => palette.onPrimaryContainer,
      (true, false) => palette.onSurface,
    };
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? palette.primaryContainer : Colors.transparent,
        child: InkWell(
          key: segment.key,
          onTap: segment.enabled ? onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: divider
                  ? Border(left: BorderSide(color: palette.outline))
                  : null,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected && constraints.maxWidth >= _checkFits) ...[
                        Icon(Symbols.check_rounded, size: 18, color: ink),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Flexible(
                        child: Text(
                          segment.label,
                          style: AppTextStyles.labelLg.copyWith(color: ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
