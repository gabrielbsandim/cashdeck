import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 48 high, pill shaped; clears with one tap and spins while a search runs.
class CdSearchField extends StatelessWidget {
  const new({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.loading = false,
    super.key,
  });

  static const clearKey = Key('cd-search-clear');

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.full),
      borderSide: BorderSide.none,
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyLg.copyWith(color: palette.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: palette.surfaceContainerHigh,
          border: pill,
          enabledBorder: pill,
          focusedBorder: pill.copyWith(
            borderSide: BorderSide(color: palette.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          prefixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Icon(Symbols.search_rounded, color: palette.onSurfaceVariant),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  key: clearKey,
                  tooltip: l10n.clearSearch,
                  icon: const Icon(Symbols.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
        ),
      ),
    );
  }
}
