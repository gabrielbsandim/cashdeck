import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/chat/presentation/chat_controller.dart';
import 'package:cashdeck/features/chat/presentation/chat_labels.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contact_labels.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contacts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What the assistant proposes to do. Nothing runs until the user confirms
/// here; a consolidated thread also asks which entity it is for.
class ChatActionCard extends ConsumerStatefulWidget {
  const new({
    required this.conversation,
    required this.action,
    required this.busy,
    super.key,
  });

  static Key confirmKey(String id) => Key('chat-action-confirm-$id');

  static Key cancelKey(String id) => Key('chat-action-cancel-$id');

  static Key entityKey(EntityKind kind) =>
      Key('chat-action-entity-${kind.name}');

  static const newContactKey = Key('chat-action-new-contact');

  final ConversationKey conversation;
  final ChatAction action;
  final bool busy;

  @override
  ConsumerState<ChatActionCard> createState() => _ChatActionCardState();
}

class _ChatActionCardState extends ConsumerState<ChatActionCard> {
  EntityKind? _entity;

  ConversationController get _controller =>
      ref.read(conversationControllerProvider(widget.conversation).notifier);

  /// Money leaves only after the same device check as the confirm sheet.
  Future<bool> _deviceCheck(AppLocalizations l10n) async {
    final tool = widget.action.tool;
    if (!tool.movesMoney) return true;
    final passed = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(chatToolTitle(l10n, tool));
    if (passed || !mounted) return passed;
    CdHaptics.error();
    showCdToast(
      context,
      icon: Symbols.fingerprint_rounded,
      message: l10n.confirmDenied,
    ).ignore();
    return false;
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    if (!await _deviceCheck(l10n) || !mounted) return;
    CdHaptics.confirm();
    final failure = await _controller.confirm(widget.action, entity: _entity);
    if (!mounted) return;
    if (failure == null && widget.action.tool == ChatTool.sendPix) {
      ref.invalidate(pixContactsControllerProvider);
    }
    await showOutcomeToast(context, failure, success: l10n.chatActionDone);
  }

  Future<void> _cancel() async {
    final failure = await _controller.cancel(widget.action);
    if (failure == null || !mounted) return;
    await showOutcomeToast(context, failure, success: '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final action = widget.action;
    final (status, tone) = chatActionStatusOf(l10n, action.status);
    final error = action.error;
    final needsChoice = action.isPending && action.needsEntity;
    final ready = !needsChoice || _entity != null;
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CdIconTile(chatToolIcon(action.tool)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  chatToolTitle(l10n, action.tool),
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
              CdStatusBadge(tone: tone, label: status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._rows(l10n, action.details),
          if (action.isPending && action.details.newContact == true)
            _NewContactNote(handle: action.details.contactHandle),
          if (error != null)
            Text(
              error,
              style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
            ),
          if (needsChoice) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.chatActionWhichEntity,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            CdSegmented<EntityKind?>(
              segments: [
                for (final kind in EntityKind.values)
                  CdSegment(kind, switch (kind) {
                    EntityKind.personal => l10n.entityPersonal,
                    EntityKind.company => l10n.entityCompany,
                  }, key: ChatActionCard.entityKey(kind)),
              ],
              selected: _entity,
              onChanged: (kind) => setState(() => _entity = kind),
            ),
          ],
          if (action.isPending) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: CdButton.text(
                    key: ChatActionCard.cancelKey(action.id),
                    label: l10n.cancelButton,
                    onPressed: widget.busy ? null : _cancel,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: CdButton.filled(
                    key: ChatActionCard.confirmKey(action.id),
                    label: l10n.chatActionConfirm,
                    loading: widget.busy,
                    onPressed: ready ? _confirm : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _rows(AppLocalizations l10n, ChatActionDetails details) {
    Widget text(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : CdKeyValueRow(label: label, value: Text(value));
    final amount = details.amount;
    final keyType = details.pixKeyType;
    final pixKey = details.pixKey;
    final handle = details.contactHandle;
    return [
      text(l10n.chatDetailPayee, details.payee),
      text(l10n.chatDetailContact, handle == null ? null : '@$handle'),
      if (pixKey != null)
        text(
          l10n.chatDetailPixKey,
          keyType == null
              ? pixKey
              : '${pixKeyTypeLabel(l10n, keyType)} $pixKey',
        ),
      if (amount != null)
        CdKeyValueRow(
          label: l10n.chatDetailAmount,
          value: CdAmount(amount, size: CdAmountSize.sm),
        ),
      text(l10n.chatDetailDueDate, details.dueDate?.display),
      text(l10n.chatDetailFile, details.fileName),
      text(l10n.chatDetailPattern, details.pattern),
      text(l10n.chatDetailCategory, details.category),
      text(l10n.chatDetailPayer, details.payer),
    ];
  }
}

class _NewContactNote extends StatelessWidget {
  const new({required this.handle});

  final String? handle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Container(
      key: ChatActionCard.newContactKey,
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.person_add_rounded,
            size: 20,
            color: palette.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.chatNewContactNote(handle ?? ''),
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
