import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The inverse surface toast, one icon, one line and at most one action.
/// Resolves with how it closed, so an undo can be honored.
Future<SnackBarClosedReason> showCdToast(
  BuildContext context, {
  required String message,
  IconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final palette = context.palette;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger
      .showSnackBar(
        SnackBar(
          // An undo toast must still time out, or the action never commits.
          persist: false,
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: palette.onInverseSurface, size: 20),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  onPressed: onAction ?? () {},
                ),
        ),
      )
      .closed;
}

/// [success] when [failure] is null, the failure's message otherwise.
Future<SnackBarClosedReason> showOutcomeToast(
  BuildContext context,
  AppFailure? failure, {
  required String success,
}) => showCdToast(
  context,
  icon: failure == null ? Symbols.task_alt_rounded : Symbols.error_rounded,
  message: failure?.userMessage(AppLocalizations.of(context)) ?? success,
);
