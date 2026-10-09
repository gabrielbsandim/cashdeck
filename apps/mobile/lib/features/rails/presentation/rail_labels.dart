import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

String railName(AppLocalizations l10n, RailKind kind) => switch (kind) {
  RailKind.pixApi => l10n.railPixApi,
  RailKind.boletoApi => l10n.railBoletoApi,
  RailKind.taxApi => l10n.railTaxApi,
  RailKind.reserveFunding => l10n.railReserveFunding,
  RailKind.bankApproval => l10n.railBankApproval,
  RailKind.assisted => l10n.railAssisted,
};

String railDetail(AppLocalizations l10n, PaymentRail rail) =>
    switch (rail.kind) {
      RailKind.pixApi || RailKind.boletoApi => l10n.railPayer(rail.institution),
      RailKind.taxApi => l10n.railViaApi(rail.institution),
      RailKind.reserveFunding => l10n.railFundingDetail(rail.institution),
      RailKind.bankApproval when rail.status == RailStatus.unavailable =>
        l10n.railApprovalUnavailable,
      RailKind.bankApproval => l10n.railApprovalDetail(rail.institution),
      RailKind.assisted => l10n.railAssistedDetail,
    };

(MoneyTone, String, IconData) railStatusOf(
  AppLocalizations l10n,
  RailStatus status,
) => switch (status) {
  RailStatus.active => (
    MoneyTone.paid,
    l10n.railActive,
    Symbols.check_circle_rounded,
  ),
  RailStatus.needsAuthorization => (
    MoneyTone.pending,
    l10n.railAuthorize,
    Symbols.key_rounded,
  ),
  RailStatus.unavailable => (
    MoneyTone.neutral,
    l10n.railUnavailable,
    Symbols.block_rounded,
  ),
  RailStatus.always => (
    MoneyTone.assisted,
    l10n.railAlways,
    Symbols.verified_user_rounded,
  ),
};

String railCheckLabel(AppLocalizations l10n, RailCheckKind kind) =>
    switch (kind) {
      RailCheckKind.certificate => l10n.railCheckCertificate,
      RailCheckKind.apiKey => l10n.railCheckApiKey,
      RailCheckKind.scope => l10n.railCheckScope,
      RailCheckKind.payerAccount => l10n.railCheckPayer,
    };
