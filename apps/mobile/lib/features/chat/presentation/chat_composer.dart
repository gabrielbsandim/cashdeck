import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/features/chat/presentation/conversation_screen.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/features/pix_contacts/presentation/contact_avatar.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contact_labels.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contacts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The message being written: files, the edit banner, the text and send.
class ChatComposer extends StatelessWidget {
  const new({
    required this.controller,
    required this.focus,
    required this.files,
    required this.sending,
    required this.onAttach,
    required this.onSend,
    required this.onRemoveFile,
    required this.onCancelEdit,
    this.editing = false,
    this.editingEarlier = false,
    this.autofocus = false,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final List<LocalFile> files;
  final bool sending;
  final bool editing;

  /// The edited message is not the last one, so later ones will go.
  final bool editingEarlier;
  final bool autofocus;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final ValueChanged<int> onRemoveFile;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      borderSide: BorderSide.none,
    );
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceContainerLow,
          border: Border(top: BorderSide(color: palette.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (editing)
                _EditBanner(earlier: editingEarlier, onCancel: onCancelEdit),
              if (files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (final (index, file) in files.indexed)
                        InputChip(
                          key: ConversationScreen.fileChipKey(index),
                          label: Text(file.name),
                          onDeleted: () => onRemoveFile(index),
                        ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    key: ConversationScreen.attachKey,
                    tooltip: l10n.chatAttachTitle,
                    onPressed: sending || editing ? null : onAttach,
                    icon: const Icon(Symbols.add_circle_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      key: ConversationScreen.inputKey,
                      controller: controller,
                      focusNode: focus,
                      autofocus: autofocus,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppTextStyles.bodyLg.copyWith(
                        color: palette.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.chatInputHint,
                        filled: true,
                        fillColor: palette.surfaceContainerHigh,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        border: field,
                        enabledBorder: field,
                        focusedBorder: field,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.filled(
                    key: ConversationScreen.sendKey,
                    tooltip: l10n.chatSend,
                    onPressed: sending ? null : onSend,
                    icon: Icon(
                      editing ? Symbols.check_rounded : Symbols.send_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditBanner extends StatelessWidget {
  const new({required this.earlier, required this.onCancel});

  final bool earlier;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Container(
      key: ConversationScreen.editBannerKey,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.only(left: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border(left: BorderSide(color: palette.primary, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Symbols.edit_rounded, size: 18, color: palette.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.chatEditing,
                  style: AppTextStyles.labelLg.copyWith(color: palette.primary),
                ),
                if (earlier)
                  Text(
                    l10n.chatEditingNote,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: ConversationScreen.cancelEditKey,
            tooltip: l10n.chatCancelEdit,
            icon: const Icon(Symbols.close_rounded),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

const _maxMentions = 5;

/// Contacts whose name or handle matches what follows the @, above the
/// composer; picking one completes the mention.
class MentionPanel extends ConsumerWidget {
  const new({required this.query, required this.onPick, super.key});

  final String query;
  final ValueChanged<PixContact> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final contacts = ref.watch(pixContactsControllerProvider);
    final matches = (contacts.value ?? const <PixContact>[])
        .where((contact) => contact.matches(query))
        .take(_maxMentions)
        .toList();
    return Material(
      key: ConversationScreen.mentionPanelKey,
      color: palette.surfaceContainer,
      shape: Border(top: BorderSide(color: palette.outlineVariant)),
      child: switch (contacts) {
        AsyncData() when matches.isEmpty => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            l10n.chatMentionsEmpty,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        AsyncData() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final contact in matches)
              _MentionRow(contact: contact, onTap: () => onPick(contact)),
          ],
        ),
        AsyncError() => const SizedBox.shrink(),
        _ => const LinearProgressIndicator(minHeight: 2),
      },
    );
  }
}

class _MentionRow extends StatelessWidget {
  const new({required this.contact, required this.onTap});

  final PixContact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return InkWell(
      key: ConversationScreen.mentionKey(contact.handle),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            ContactAvatar(contact: contact, size: 36),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSm.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  Text(
                    '${contact.mention} · '
                    '${pixKeyTypeLabel(l10n, contact.pixKeyType)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Starting points for an empty conversation.
class ChatSuggestions extends StatelessWidget {
  const new({required this.onAsk, required this.onPix, super.key});

  static Key suggestionKey(int index) => Key('chat-suggestion-$index');

  static const pixKey = Key('chat-suggestion-pix');

  final ValueChanged<String> onAsk;
  final VoidCallback onPix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final questions = [
      l10n.chatSuggestionWeek,
      l10n.chatSuggestionBills,
      l10n.chatSuggestionMonth,
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.auto_awesome_rounded,
              size: 40,
              color: palette.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.chatConversationEmptyTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLg.copyWith(color: palette.onSurface),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.chatConversationEmptyMessage,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (index, question) in questions.indexed)
                  ActionChip(
                    key: suggestionKey(index),
                    label: Text(question),
                    onPressed: () => onAsk(question),
                  ),
                ActionChip(
                  key: pixKey,
                  avatar: Icon(
                    Symbols.send_money_rounded,
                    color: palette.primary,
                  ),
                  label: Text(l10n.chatSuggestionPix),
                  onPressed: onPix,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
