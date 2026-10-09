import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The floating "ask" pill docked above the tab bar; it opens the chat.
class CdAskBar extends StatelessWidget {
  const new({required this.hint, required this.onTap, super.key});

  static const barKey = Key('cd-ask-bar');

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Semantics(
        button: true,
        label: hint,
        excludeSemantics: true,
        child: Material(
          color: palette.surfaceContainer,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: barKey,
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.lg),
                  Icon(Symbols.auto_awesome_rounded, color: palette.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLg.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(Symbols.mic_rounded, color: palette.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
