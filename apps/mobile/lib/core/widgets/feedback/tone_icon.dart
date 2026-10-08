import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Every tone carries an icon and a label, so no state is told by color alone.
extension ToneIcon on MoneyTone {
  IconData get icon => switch (this) {
    MoneyTone.income => Symbols.south_west_rounded,
    MoneyTone.expense => Symbols.north_east_rounded,
    MoneyTone.transfer => Symbols.sync_alt_rounded,
    MoneyTone.pending => Symbols.schedule_rounded,
    MoneyTone.scheduled => Symbols.event_rounded,
    MoneyTone.awaitingApproval => Symbols.approval_rounded,
    MoneyTone.paid => Symbols.check_circle_rounded,
    MoneyTone.failed => Symbols.error_rounded,
    MoneyTone.overdue => Symbols.event_busy_rounded,
    MoneyTone.assisted => Symbols.verified_user_rounded,
    MoneyTone.neutral => Symbols.info_rounded,
  };

  String label(AppLocalizations l10n) => switch (this) {
    MoneyTone.income => l10n.toneIncome,
    MoneyTone.expense => l10n.toneExpense,
    MoneyTone.transfer => l10n.toneTransfer,
    MoneyTone.pending => l10n.tonePending,
    MoneyTone.scheduled => l10n.toneScheduled,
    MoneyTone.awaitingApproval => l10n.toneAwaitingApproval,
    MoneyTone.paid => l10n.tonePaid,
    MoneyTone.failed => l10n.toneFailed,
    MoneyTone.overdue => l10n.toneOverdue,
    MoneyTone.assisted => l10n.toneAssisted,
    MoneyTone.neutral => l10n.toneNeutral,
  };
}
