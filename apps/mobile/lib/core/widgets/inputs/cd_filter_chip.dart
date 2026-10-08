import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 32 visual, 48 hit. [onRemove] turns it into an applied filter with a close;
/// [dropdown] marks a chip that opens a picker.
class CdFilterChip extends StatelessWidget {
  const new({
    required this.label,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.dropdown = false,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool dropdown;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null || onRemove != null;
    final filled = selected || onRemove != null;
    final ink = switch ((enabled, filled)) {
      (false, _) => palette.onSurfaceVariant.withValues(alpha: 0.6),
      (true, true) => palette.onPrimaryContainer,
      (true, false) => palette.onSurface,
    };
    final leading = selected ? Symbols.check_rounded : icon;
    final remove = onRemove;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap ?? onRemove,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: filled ? palette.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: filled
                    ? null
                    : Border.all(
                        color: enabled
                            ? palette.outline
                            : palette.outlineVariant,
                      ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    Icon(leading, size: 18, color: ink),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Text(
                    label,
                    style: AppTextStyles.labelLg.copyWith(color: ink),
                  ),
                  if (dropdown)
                    Icon(Symbols.arrow_drop_down_rounded, color: ink),
                  if (remove != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Icon(Symbols.close_rounded, size: 18, color: ink),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
