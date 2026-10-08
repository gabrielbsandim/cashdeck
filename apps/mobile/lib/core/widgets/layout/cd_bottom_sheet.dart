import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// A modal sheet with the drag handle and AppRadius.sheet top corners.
Future<T?> showCdBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => CdSheetBody(title: title, child: builder(context)),
  );
}

class CdSheetBody extends StatelessWidget {
  const new({required this.child, this.title, super.key});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = this.title;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: palette.outline,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (title != null) ...[
            Text(
              title,
              style: AppTextStyles.titleLg.copyWith(color: palette.onSurface),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}
