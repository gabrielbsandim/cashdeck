import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The groups Ajustes opens into, each on a screen of its own. Away from a
/// safe zone only the groups marked [openWhileLimited] stay.
enum SettingsSection {
  connections(AppRoutes.settingsConnections, Symbols.hub_rounded),
  payments(AppRoutes.settingsPayments, Symbols.payments_rounded),
  company(AppRoutes.settingsCompany, Symbols.business_center_rounded),
  security(
    AppRoutes.settingsSecurity,
    Symbols.shield_rounded,
    openWhileLimited: true,
  );

  new(this.route, this.icon, {this.openWhileLimited = false});

  final String route;
  final IconData icon;
  final bool openWhileLimited;

  String title(AppLocalizations l10n) => switch (this) {
    connections => l10n.settingsSectionConnections,
    payments => l10n.settingsSectionPayments,
    company => l10n.settingsSectionCompany,
    security => l10n.settingsSectionSecurity,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    connections => l10n.settingsConnectionsHint,
    payments => l10n.settingsPaymentsHint,
    company => l10n.settingsCompanyHint,
    security => l10n.settingsSecurityHint,
  };
}

/// A row in Ajustes that opens [route]; its key is [keyOf] the route.
class SettingsLink extends StatelessWidget {
  new({
    required this.icon,
    required this.title,
    required this.route,
    this.subtitle,
  }) : super(key: keyOf(route));

  static Key keyOf(String route) => Key('settings-row-$route');

  final IconData icon;
  final String title;
  final String? subtitle;
  final String route;

  @override
  Widget build(BuildContext context) => CdListRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    chevron: true,
    onTap: () => context.push(route),
  );
}

/// The frame of a section screen: its title, a line on what it holds and its
/// rows.
class SettingsPage extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.intro,
    super.key,
  });

  final String title;
  final String? intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final intro = this.intro;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          if (intro != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.md,
                AppSpacing.screenGutter,
                AppSpacing.sm,
              ),
              child: Text(
                intro,
                style: AppTextStyles.bodyMd.copyWith(
                  color: context.palette.onSurfaceVariant,
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}
