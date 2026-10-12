import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/security/app_lock.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/features/settings/presentation/safe_zone/safe_zone_screen.dart';
import 'package:cashdeck/features/settings/presentation/settings_section.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What protects the data on the phone: the safe zones, the amount mask and
/// the lock. It stays open away from a safe zone.
class SecuritySettingsScreen extends ConsumerWidget {
  const new({super.key});

  static const hideAmountsKey = Key('settings-hide-amounts');
  static const lockKey = Key('settings-lock-now');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(displayPreferencesProvider);
    final controller = ref.read(displayPreferencesProvider.notifier);
    final safeMode = ref.watch(safeModeProvider);
    final limited = safeMode.limited;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return SettingsPage(
      title: SettingsSection.security.title(l10n),
      intro: l10n.settingsSecurityIntro,
      children: [
        SettingsLink(
          icon: Symbols.home_pin_rounded,
          title: l10n.safeZoneTitle,
          subtitle: safeModeStatusLabel(l10n, safeMode, locale),
          route: AppRoutes.safeZone,
        ),
        CdListRow(
          key: hideAmountsKey,
          icon: Symbols.visibility_off_rounded,
          title: l10n.settingsPrivacy,
          subtitle: l10n.hideAmountsSetting,
          trailing: Switch(
            value: prefs.hideAmounts || limited,
            onChanged: limited ? null : (_) => controller.toggleHideAmounts(),
          ),
          onTap: limited ? null : controller.toggleHideAmounts,
        ),
        if (!limited)
          SettingsLink(
            icon: Symbols.devices_rounded,
            title: l10n.deviceSessionsTitle,
            subtitle: l10n.deviceSessionsHint,
            route: AppRoutes.deviceSessions,
          ),
        CdListRow(
          key: lockKey,
          icon: Symbols.lock_rounded,
          title: l10n.lockNowSetting,
          subtitle: l10n.lockNowHint,
          onTap: () => ref.read(appLockProvider.notifier).lock(),
        ),
      ],
    );
  }
}
