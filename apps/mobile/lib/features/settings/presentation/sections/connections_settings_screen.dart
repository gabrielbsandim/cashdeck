import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/features/settings/presentation/settings_section.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Where money and bills come in from: Open Finance, the capture sources and
/// the cards the aggregator does not reach.
class ConnectionsSettingsScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsPage(
      title: SettingsSection.connections.title(l10n),
      intro: l10n.settingsConnectionsIntro,
      children: [
        SettingsLink(
          icon: Symbols.account_balance_rounded,
          title: l10n.itemIdTitle,
          subtitle: l10n.moreItemIdHint,
          route: AppRoutes.connectItemId,
        ),
        SettingsLink(
          icon: Symbols.inbox_rounded,
          title: l10n.captureTitle,
          subtitle: l10n.moreCaptureHint,
          route: AppRoutes.captureSources,
        ),
        SettingsLink(
          icon: Symbols.credit_card_rounded,
          title: l10n.cardImportMenu,
          subtitle: l10n.moreCardImportHint,
          route: AppRoutes.cardImport,
        ),
        SettingsLink(
          icon: Symbols.notifications_active_rounded,
          title: l10n.cardNotificationsMenu,
          subtitle: l10n.moreCardNotificationsHint,
          route: AppRoutes.cardNotifications,
        ),
      ],
    );
  }
}
