import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// A row the whole width toggles: checkbox, title, optional detail and a
/// trailing value such as an amount or a count.
class CdCheckboxRow extends StatelessWidget {
  const new({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final onChanged = this.onChanged;
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    return Semantics(
      checked: value,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.listRowMinHeight,
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Checkbox(
                  value: value,
                  onChanged: onChanged == null
                      ? null
                      : (checked) => onChanged(checked ?? false),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    ?subtitle,
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                DefaultTextStyle.merge(
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                  child: trailing,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
