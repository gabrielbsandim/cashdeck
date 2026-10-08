import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Placeholder rows shaped like the list that is loading.
class CdSkeleton extends StatelessWidget {
  const new({this.rows = 4, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
    );
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
        itemBuilder: (_, _) => Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(140, 12),
                  const SizedBox(height: AppSpacing.sm),
                  bar(90, 10),
                ],
              ),
            ),
            bar(64, 12),
          ],
        ),
      ),
    );
  }
}

class CdLoading extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
