import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A generated sentence with its tinted icon; the whole row opens what it
/// talks about.
class CdInsightRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.tone,
    required this.sentence,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final ToneColors tone;
  final String sentence;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tone.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: tone.foreground),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  sentence,
                  style: AppTextStyles.bodyLg.copyWith(
                    fontWeight: FontWeight.w500,
                    color: palette.onSurface,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Symbols.chevron_right_rounded,
                  color: palette.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
