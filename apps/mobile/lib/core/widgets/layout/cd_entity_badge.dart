import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The PF, PJ or stacked circle that marks who a record belongs to.
class CdEntityBadge extends StatelessWidget {
  const new({required this.entity, this.label, this.size = 32, super.key});

  final EntityTone entity;

  /// PF or PJ; the consolidated badge draws stacked layers instead.
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.entities.of(entity);
    final label = this.label;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.background,
        shape: BoxShape.circle,
      ),
      child: label == null
          ? Icon(
              Symbols.stacks_rounded,
              size: size * 0.56,
              color: colors.foreground,
            )
          : Text(
              label,
              style: AppTextStyles.labelMd.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
    );
  }
}
