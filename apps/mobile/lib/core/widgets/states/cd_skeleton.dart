import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/states/cd_shimmer.dart';
import 'package:flutter/material.dart';

/// Placeholders shaped like the screen that is loading, under one shimmer.
/// Each screen lists its own [parts]; without them it is a list of [rows].
class CdSkeleton extends StatelessWidget {
  const new({this.rows = 4, this.parts, super.key});

  final int rows;
  final List<Widget>? parts;

  @override
  Widget build(BuildContext context) {
    final parts = this.parts ?? [CdSkeletonRows(count: rows)];
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: CdShimmer(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final (index, part) in parts.indexed) ...[
              if (index > 0) const SizedBox(height: AppSpacing.lg),
              part,
            ],
          ],
        ),
      ),
    );
  }
}

/// One placeholder shape in the surface the shimmer sweeps over.
class CdBone extends StatelessWidget {
  const new({
    this.width,
    this.height = 12,
    this.radius = AppRadius.full,
    this.circle = false,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.surfaceContainerHigh;
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: circle
          ? BoxDecoration(color: color, shape: BoxShape.circle)
          : BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
            ),
    );
  }
}

/// A headline figure: its label, the big amount and the line under it.
class CdSkeletonHeadline extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CdBone(width: 120),
        SizedBox(height: AppSpacing.sm),
        CdBone(width: 200, height: 32, radius: AppRadius.sm),
        SizedBox(height: AppSpacing.sm),
        CdBone(width: 160, height: 10),
      ],
    );
  }
}

/// A card block, such as a chart or a summary.
class CdSkeletonCard extends StatelessWidget {
  const new({this.height = 120, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return CdBone(height: height, radius: AppRadius.xxl);
  }
}

/// [count] cards of [height] one under the other, such as bills or goals.
class CdSkeletonCards extends StatelessWidget {
  const new({this.count = 3, this.height = 76, super.key});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < count; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          CdBone(height: height, radius: AppRadius.lg),
        ],
      ],
    );
  }
}

/// Two tiles side by side, such as the stats of a header.
class CdSkeletonTiles extends StatelessWidget {
  const new({this.height = 72, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CdBone(height: height, radius: AppRadius.lg),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: CdBone(height: height, radius: AppRadius.lg),
        ),
      ],
    );
  }
}

/// A row of [count] chips, such as filters or months.
class CdSkeletonChips extends StatelessWidget {
  const new({this.count = 3, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < count; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.sm),
          const CdBone(width: 72, height: 32),
        ],
      ],
    );
  }
}

/// List rows with a round leading, two lines and an amount; [header] adds
/// a day label above them, as the transaction list has.
class CdSkeletonRows extends StatelessWidget {
  const new({this.count = 4, this.header = false, super.key});

  final int count;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header) ...[
          const CdBone(width: 96, height: 10),
          const SizedBox(height: AppSpacing.lg),
        ],
        for (var index = 0; index < count; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.lg),
          const Row(
            children: [
              CdBone(height: 40, circle: true),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CdBone(width: 140),
                    SizedBox(height: AppSpacing.sm),
                    CdBone(width: 90, height: 10),
                  ],
                ),
              ),
              CdBone(width: 64),
            ],
          ),
        ],
      ],
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
