import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

String pixKeyTypeLabel(AppLocalizations l10n, PixKeyType type) =>
    switch (type) {
      PixKeyType.cpf => l10n.pixKeyTypeCpf,
      PixKeyType.cnpj => l10n.pixKeyTypeCnpj,
      PixKeyType.email => l10n.pixKeyTypeEmail,
      PixKeyType.phone => l10n.pixKeyTypePhone,
      PixKeyType.evp => l10n.pixKeyTypeEvp,
    };

String pixKeyKindLabel(AppLocalizations l10n, PixKeyKind kind) =>
    switch (kind) {
      PixKeyKind.taxId => l10n.pixKeyKindTaxId,
      PixKeyKind.phone => l10n.pixKeyKindPhone,
      PixKeyKind.email => l10n.pixKeyKindEmail,
      PixKeyKind.evp => l10n.pixKeyKindEvp,
    };

IconData pixKeyKindIcon(PixKeyKind kind) => switch (kind) {
  PixKeyKind.taxId => Symbols.badge_rounded,
  PixKeyKind.phone => Symbols.smartphone_rounded,
  PixKeyKind.email => Symbols.alternate_email_rounded,
  PixKeyKind.evp => Symbols.key_rounded,
};

/// "CPF ***.456.789-**", what a row shows of the key.
String pixKeyLine(AppLocalizations l10n, PixKeyType type, String key) =>
    '${pixKeyTypeLabel(l10n, type)} ${maskPixKey(type, key)}';

/// How often and how recently the contact got a Pix.
String paidLine(AppLocalizations l10n, PixContact contact) {
  final times = l10n.pixContactPaidTimes(contact.timesPaid);
  final last = contact.lastPaidAt;
  if (last == null) return times;
  return l10n.pixContactLastPaid(times, CalendarDate.brazilToday(last).display);
}
