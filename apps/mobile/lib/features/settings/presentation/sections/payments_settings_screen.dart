import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/failure_message.dart';
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
      ],
    );
  }
}
