import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

final class ToneColors extends Equatable {
  const new({required this.foreground, required this.background});

  final Color foreground;
  final Color background;

  @override
  List<Object?> get props => [foreground, background];
}

/// Money semantics: one hue per state, derived by one lightness rule per
/// theme, so every status reads the same way in light and dark.
@immutable
final class AppMoneyColors extends ThemeExtension<AppMoneyColors> {
  const new({
    required this.income,
    required this.incomeContainer,
    required this.expense,
    required this.expenseContainer,
    required this.transfer,
    required this.transferContainer,
    required this.pending,
    required this.pendingContainer,
    required this.scheduled,
    required this.scheduledContainer,
    required this.awaitingApproval,
    required this.awaitingApprovalContainer,
    required this.paid,
    required this.paidContainer,
    required this.failed,
    required this.failedContainer,
    required this.overdue,
    required this.overdueContainer,
    required this.assisted,
    required this.assistedContainer,
    required this.neutral,
    required this.neutralContainer,
  });

  static final light = AppMoneyColors(
    income: const Color(0xFF007840),
    incomeContainer: const Color(0xFFD6F6E0),
    expense: const Color(0xFF9D3A67),
    expenseContainer: const Color(0xFFFFE1EE),
    transfer: const Color(0xFF5C6472),
    transferContainer: const Color(0xFFE4EDFE),
    pending: const Color(0xFF8A5700),
    pendingContainer: const Color(0xFFFFE9CC),
    scheduled: const Color(0xFF006F92),
    scheduledContainer: const Color(0xFFCEF4FF),
    awaitingApproval: const Color(0xFF7B489E),
    awaitingApprovalContainer: const Color(0xFFF6E5FF),
    paid: const Color(0xFF21763C),
    paidContainer: const Color(0xFFD9F6DD),
    failed: const Color(0xFFB02B27),
    failedContainer: const Color(0xFFFFE2DD),
    overdue: const Color(0xFFA34100),
    overdueContainer: const Color(0xFFFFE5D3),
    assisted: AppPalette.light.primary,
    assistedContainer: AppPalette.light.primaryContainer,
    neutral: AppPalette.light.onSurfaceVariant,
    neutralContainer: AppPalette.light.surfaceContainerHigh,
  );

  static final dark = AppMoneyColors(
    income: const Color(0xFF85D2A0),
    incomeContainer: const Color(0xFF173523),
    expense: const Color(0xFFF79FC1),
    expenseContainer: const Color(0xFF41232F),
    transfer: const Color(0xFFB7BECB),
    transferContainer: const Color(0xFF272E3B),
    pending: const Color(0xFFE2B576),
    pendingContainer: const Color(0xFF3C2A0E),
    scheduled: const Color(0xFF7CCAE9),
    scheduledContainer: const Color(0xFF0A3341),
    awaitingApproval: const Color(0xFFD4A9F4),
    awaitingApprovalContainer: const Color(0xFF352641),
    paid: const Color(0xFF90D09D),
    paidContainer: const Color(0xFF1A3520),
    failed: const Color(0xFFFF9A8E),
    failedContainer: const Color(0xFF442320),
    overdue: const Color(0xFFFCA676),
    overdueContainer: const Color(0xFF422616),
    assisted: AppPalette.dark.primary,
    assistedContainer: AppPalette.dark.primaryContainer,
    neutral: AppPalette.dark.onSurfaceVariant,
    neutralContainer: AppPalette.dark.surfaceContainerHigh,
  );

  final Color income;
  final Color incomeContainer;
  final Color expense;
  final Color expenseContainer;
  final Color transfer;
  final Color transferContainer;
  final Color pending;
  final Color pendingContainer;
  final Color scheduled;
  final Color scheduledContainer;
  final Color awaitingApproval;
  final Color awaitingApprovalContainer;
  final Color paid;
  final Color paidContainer;
  final Color failed;
  final Color failedContainer;
  final Color overdue;
  final Color overdueContainer;
  final Color assisted;
  final Color assistedContainer;
  final Color neutral;
  final Color neutralContainer;

  ToneColors tone(MoneyTone tone) => switch (tone) {
    MoneyTone.income => ToneColors(
      foreground: income,
      background: incomeContainer,
    ),
    MoneyTone.expense => ToneColors(
      foreground: expense,
      background: expenseContainer,
    ),
    MoneyTone.transfer => ToneColors(
      foreground: transfer,
      background: transferContainer,
    ),
    MoneyTone.pending => ToneColors(
      foreground: pending,
      background: pendingContainer,
    ),
    MoneyTone.scheduled => ToneColors(
      foreground: scheduled,
      background: scheduledContainer,
    ),
    MoneyTone.awaitingApproval => ToneColors(
      foreground: awaitingApproval,
      background: awaitingApprovalContainer,
    ),
    MoneyTone.paid => ToneColors(foreground: paid, background: paidContainer),
    MoneyTone.failed => ToneColors(
      foreground: failed,
      background: failedContainer,
    ),
    MoneyTone.overdue => ToneColors(
      foreground: overdue,
      background: overdueContainer,
    ),
    MoneyTone.assisted => ToneColors(
      foreground: assisted,
      background: assistedContainer,
    ),
    MoneyTone.neutral => ToneColors(
      foreground: neutral,
      background: neutralContainer,
    ),
  };

  @override
  AppMoneyColors copyWith() => this;

  @override
  AppMoneyColors lerp(AppMoneyColors? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

/// Entity identity: the PF, PJ and consolidated badge tints.
@immutable
final class AppEntityColors extends ThemeExtension<AppEntityColors> {
  const new({
    required this.personal,
    required this.personalContainer,
    required this.company,
    required this.companyContainer,
    required this.consolidated,
    required this.consolidatedContainer,
  });

  static const light = AppEntityColors(
    personal: Color(0xFF2C5DBD),
    personalContainer: Color(0xFFDDEEFF),
    company: Color(0xFF00736A),
    companyContainer: Color(0xFFCCF7F1),
    consolidated: Color(0xFF5C6472),
    consolidatedContainer: Color(0xFFE4EDFE),
  );

  static const dark = AppEntityColors(
    personal: Color(0xFF90BDFF),
    personalContainer: Color(0xFF202E47),
    company: Color(0xFF87CDC4),
    companyContainer: Color(0xFF053631),
    consolidated: Color(0xFFB7BECB),
    consolidatedContainer: Color(0xFF272E3B),
  );

  final Color personal;
  final Color personalContainer;
  final Color company;
  final Color companyContainer;
  final Color consolidated;
  final Color consolidatedContainer;

  ToneColors of(EntityTone entity) => switch (entity) {
    EntityTone.personal => ToneColors(
      foreground: personal,
      background: personalContainer,
    ),
    EntityTone.company => ToneColors(
      foreground: company,
      background: companyContainer,
    ),
    EntityTone.consolidated => ToneColors(
      foreground: consolidated,
      background: consolidatedContainer,
    ),
  };

  @override
  AppEntityColors copyWith() => this;

  @override
  AppEntityColors lerp(AppEntityColors? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

extension MoneyColorsContext on BuildContext {
  AppMoneyColors get money => Theme.of(this).extension<AppMoneyColors>()!;

  AppEntityColors get entities => Theme.of(this).extension<AppEntityColors>()!;

  ToneColors tone(MoneyTone tone) => money.tone(tone);
}
