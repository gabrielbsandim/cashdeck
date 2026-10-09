import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// Android 15 draws the app under the system navigation bar; this keeps every
/// screen, sheet and dialog above it, with the surface color behind the bar.
class CdBottomInset extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.palette.surface,
    child: SafeArea(top: false, left: false, right: false, child: child),
  );
}
