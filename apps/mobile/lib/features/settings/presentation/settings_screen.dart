import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/security/app_lock.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/automation/presentation/automation_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Ajustes, opened from the avatar on every tab, in four groups.
class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  static const themeSelectorKey = Key('settings-theme');
  static const hideAmountsKey = Key('settings-hide-amounts');
  static const signOutKey = Key('settings-sign-out');
  static const pauseKey = Key('settings-pause');

  static Key rowKey(String route) => Key('settings-row-$route');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(displayPreferencesProvider);
    final controller = ref.read(displayPreferencesProvider.notifier);
    final paused = ref.watch(automationControllerProvider).value?.paused;
    Widget link(IconData icon, String title, String subtitle, String route) =>
        CdListRow(
          key: rowKey(route),
          icon: icon,
          title: title,
          subtitle: subtitle,
          chevron: true,
          onTap: () => context.push(route),
        );
    Widget section(String title, {String? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xl,
        AppSpacing.screenGutter,
        AppSpacing.xs,
      ),
      child: CdSectionHeader(
        title: title,
        small: true,
        subtitle: trailing == null ? null : Text(trailing),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          const SizedBox(height: AppSpacing.sm),
          link(
            Symbols.badge_rounded,
            l10n.settingsProfileTitle,
            l10n.settingsProfileHint,
            AppRoutes.entityProfiles,
          ),
          section(l10n.settingsSectionConnections),
          link(
            Symbols.account_balance_rounded,
            l10n.itemIdTitle,
            l10n.moreItemIdHint,
            AppRoutes.connectItemId,
          ),
          link(
            Symbols.route_rounded,
            l10n.railsTitle,
            l10n.moreRailsHint,
            AppRoutes.rails,
          ),
          link(
            Symbols.inbox_rounded,
            l10n.captureTitle,
            l10n.moreCaptureHint,
            AppRoutes.captureSources,
          ),
          link(
            Symbols.credit_card_rounded,
            l10n.cardImportMenu,
            l10n.moreCardImportHint,
            AppRoutes.cardImport,
          ),
          section(l10n.settingsSectionPayments),
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
          section(
            l10n.settingsSectionCompany,
            trailing: l10n.settingsCompanyOnly,
          ),
          link(
            Symbols.receipt_rounded,
            l10n.issuerTitle,
            l10n.moreIssuerHint,
            AppRoutes.invoiceIssuer,
          ),
          link(
            Symbols.groups_rounded,
            l10n.payrollMenu,
            l10n.morePayrollHint,
            AppRoutes.payroll,
          ),
          link(
            Symbols.folder_zip_rounded,
            l10n.exportTitle,
            l10n.moreExportHint,
            AppRoutes.accountantExport,
          ),
          section(l10n.settingsSectionAppearance),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            child: CdSegmented<ThemeMode>(
              key: themeSelectorKey,
              segments: [
                CdSegment(ThemeMode.system, l10n.themeSystem),
                CdSegment(ThemeMode.light, l10n.themeLight),
                CdSegment(ThemeMode.dark, l10n.themeDark),
              ],
              selected: prefs.themeMode,
              onChanged: controller.setThemeMode,
            ),
          ),
          CdListRow(
            key: hideAmountsKey,
            icon: Symbols.visibility_off_rounded,
            title: l10n.settingsPrivacy,
            subtitle: l10n.hideAmountsSetting,
            trailing: Switch(
              value: prefs.hideAmounts,
              onChanged: (_) => controller.toggleHideAmounts(),
            ),
            onTap: controller.toggleHideAmounts,
          ),
          link(
            Symbols.notifications_rounded,
            l10n.alertsTitle,
            l10n.moreAlertsHint,
            AppRoutes.alerts,
          ),
          link(
            Symbols.tune_rounded,
            l10n.alertSettingsTitle,
            l10n.moreAlertSettingsHint,
            AppRoutes.alertSettings,
          ),
          CdListRow(
            key: rowKey(AppRoutes.unlock),
            icon: Symbols.lock_rounded,
            title: l10n.lockNowSetting,
            onTap: () => ref.read(appLockProvider.notifier).lock(),
          ),
          CdListRow(
            key: signOutKey,
            icon: Symbols.logout_rounded,
            title: l10n.signOutButton,
            onTap: () => ref.read(signOutProvider).call(),
          ),
        ],
      ),
    );
  }
}
