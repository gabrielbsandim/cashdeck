import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/config/app_version.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/settings/presentation/safe_zone/safe_mode_release_tap.dart';
import 'package:cashdeck/features/settings/presentation/settings_section.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Ajustes, opened from the avatar on every tab: one row per group, each
/// opening a screen of its own, then sign out and the version.
class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  static const versionKey = Key('settings-version');
  static const signOutKey = Key('settings-sign-out');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final version = ref.watch(appVersionProvider).value;
    final limited = ref.watch(safeModeLimitedProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          const SizedBox(height: AppSpacing.sm),
          if (!limited)
            SettingsLink(
              icon: Symbols.badge_rounded,
              title: l10n.settingsProfileTitle,
              subtitle: l10n.settingsProfileHint,
              route: AppRoutes.entityProfiles,
            ),
          for (final section in SettingsSection.values)
            if (section.openWhileLimited || !limited)
              SettingsLink(
                icon: section.icon,
                title: section.title(l10n),
                subtitle: section.hint(l10n),
                route: section.route,
              ),
          if (!limited)
            SettingsLink(
              icon: Symbols.rule_rounded,
              title: l10n.categoryRulesTitle,
              subtitle: l10n.categoryRulesHint,
              route: AppRoutes.categoryRules,
            ),
          SettingsLink(
            icon: Symbols.notifications_rounded,
            title: l10n.alertSettingsTitle,
            subtitle: l10n.moreAlertSettingsHint,
            route: AppRoutes.alertSettings,
          ),
          const SizedBox(height: AppSpacing.lg),
          CdListRow(
            key: signOutKey,
            icon: Symbols.logout_rounded,
            title: l10n.signOutButton,
            danger: true,
            onTap: () => ref.read(signOutProvider).call(),
          ),
          if (version != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: SafeModeReleaseTap(
                child: Text(
                  l10n.settingsVersion(version),
                  key: versionKey,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd.copyWith(
                    fontSize: 12,
                    color: context.palette.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
