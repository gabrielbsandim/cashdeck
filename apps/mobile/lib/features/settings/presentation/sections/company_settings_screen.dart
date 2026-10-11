import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/features/settings/presentation/settings_section.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What only a company entity needs: invoices, payroll and the accountant.
class CompanySettingsScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsPage(
      title: SettingsSection.company.title(l10n),
      intro: l10n.settingsCompanyIntro,
      children: [
        SettingsLink(
          icon: Symbols.receipt_rounded,
          title: l10n.issuerTitle,
          subtitle: l10n.moreIssuerHint,
          route: AppRoutes.invoiceIssuer,
        ),
        SettingsLink(
          icon: Symbols.groups_rounded,
          title: l10n.payrollMenu,
          subtitle: l10n.morePayrollHint,
          route: AppRoutes.payroll,
        ),
        SettingsLink(
          icon: Symbols.folder_zip_rounded,
          title: l10n.exportTitle,
          subtitle: l10n.moreExportHint,
          route: AppRoutes.accountantExport,
        ),
      ],
    );
  }
}
