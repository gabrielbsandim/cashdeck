import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// A label and its value: side by side in a sheet, stacked in a receipt.
class CdKeyValueRow extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.stacked = false,
    this.monospace = false,
    this.strong = false,
    super.key,
  });

  final String label;
  final Widget value;
  final bool stacked;
  final bool monospace;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final labelText = Text(
      label,
      style: AppTextStyles.bodyMd.copyWith(color: palette.onSurfaceVariant),
    );
    final valueStyle = (monospace ? AppTextStyles.code : AppTextStyles.bodyMd)
        .copyWith(
          color: palette.onSurface,
          fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final styled = DefaultTextStyle.merge(style: valueStyle, child: value);
    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [labelText, styled],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: labelText),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            flex: 2,
            child: Align(alignment: Alignment.centerRight, child: styled),
          ),
        ],
      ),
    );
  }
}
