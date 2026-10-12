import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/features/automation/presentation/automation_controller.dart';
import 'package:cashdeck/features/settings/presentation/settings_section.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// How bills get paid: the kill switch for automatic payments and the rails
/// that pay each step.
class PaymentsSettingsScreen extends ConsumerWidget {
  const new({super.key});

  static const pauseKey = Key('settings-pause');

  /// Resuming lets the ladder pay bills on its own again, so it takes the
  /// same device check as paying one; pausing never does.
  Future<bool> _allowed(
    BuildContext context,
    WidgetRef ref, {
    required bool paused,
  }) async {
    if (paused) return true;
    final l10n = AppLocalizations.of(context);
    final passed = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(l10n.resumeAutomationReason);
    if (passed || !context.mounted) return passed;
    showCdToast(context, message: l10n.confirmDenied).ignore();
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final paused = ref.watch(automationControllerProvider).value?.paused;
    return SettingsPage(
      title: SettingsSection.payments.title(l10n),
      intro: l10n.settingsPaymentsIntro,
      children: [
        CdListRow(
          key: pauseKey,
          icon: Symbols.pause_circle_rounded,
          title: l10n.pauseAutomationSetting,
          subtitle: l10n.pauseAutomationHint,
          trailing: Switch(
            value: paused ?? false,
            onChanged: paused == null
                ? null
                : (value) async {
                    if (!await _allowed(context, ref, paused: value)) return;
                    final failure = await ref
                        .read(automationControllerProvider.notifier)
                        .setPaused(paused: value);
                    if (failure == null || !context.mounted) return;
                    await showCdToast(
                      context,
                      message: failure.userMessage(l10n),
                    );
                  },
          ),
        ),
        SettingsLink(
          icon: Symbols.route_rounded,
          title: l10n.railsTitle,
          subtitle: l10n.moreRailsHint,
          route: AppRoutes.rails,
        ),
        SettingsLink(
          icon: Symbols.contacts_rounded,
          title: l10n.pixContactsTitle,
          subtitle: l10n.pixContactsHint,
          route: AppRoutes.pixContacts,
        ),
      ],
    );
  }
}
