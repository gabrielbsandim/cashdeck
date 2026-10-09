import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android 15 draws the app under the system navigation bar; this keeps every
/// screen, sheet and dialog above it, with the surface color behind the bar.
class CdBottomInset extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Without this the system paints its light contrast scrim over the bar,
    // whatever theme the app chose.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: palette.surface,
        systemNavigationBarDividerColor: palette.surface,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(
        color: palette.surface,
        child: SafeArea(top: false, left: false, right: false, child: child),
      ),
    );
  }
}
