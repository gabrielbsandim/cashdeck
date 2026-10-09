import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

String chatToolTitle(AppLocalizations l10n, ChatTool tool) => switch (tool) {
  ChatTool.createBillFromAttachment => l10n.chatToolCreateBill,
  ChatTool.payBill => l10n.chatToolPayBill,
  ChatTool.createCategoryRule => l10n.chatToolCreateRule,
  ChatTool.draftInvoice => l10n.chatToolDraftInvoice,
};

IconData chatToolIcon(ChatTool tool) => switch (tool) {
  ChatTool.createBillFromAttachment => Symbols.document_scanner_rounded,
  ChatTool.payBill => Symbols.payments_rounded,
  ChatTool.createCategoryRule => Symbols.rule_rounded,
  ChatTool.draftInvoice => Symbols.request_quote_rounded,
};

(String, MoneyTone) chatActionStatusOf(
  AppLocalizations l10n,
  ChatActionStatus status,
) => switch (status) {
  ChatActionStatus.pending => (l10n.chatActionPending, MoneyTone.pending),
  ChatActionStatus.confirmed => (l10n.chatActionConfirmed, MoneyTone.paid),
  ChatActionStatus.cancelled => (l10n.chatActionCancelled, MoneyTone.neutral),
  ChatActionStatus.failed => (l10n.chatActionFailed, MoneyTone.failed),
  ChatActionStatus.expired => (l10n.chatActionExpired, MoneyTone.neutral),
};

String chatNoticeText(AppLocalizations l10n, ChatNotice notice) =>
    switch (notice) {
      ChatNotice.roundLimit => l10n.chatNoticeRoundLimit,
      ChatNotice.timeBudget => l10n.chatNoticeTimeBudget,
      ChatNotice.empty => l10n.chatNoticeEmpty,
      ChatNotice.error => l10n.chatNoticeError,
    };

String draftProblemText(AppLocalizations l10n, DraftProblem problem) =>
    switch (problem) {
      DraftProblem.empty => l10n.chatDraftEmpty,
      DraftProblem.tooLong => l10n.chatDraftTooLong(ChatDraft.maxText),
      DraftProblem.tooManyFiles => l10n.chatDraftTooManyFiles(
        ChatDraft.maxFiles,
      ),
      DraftProblem.tooLarge => l10n.chatDraftTooLarge,
      DraftProblem.unsupportedFile => l10n.chatDraftUnsupported,
    };
