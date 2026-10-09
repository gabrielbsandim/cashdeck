import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_options_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/chat/presentation/chat_action_card.dart';
import 'package:cashdeck/features/chat/presentation/chat_controller.dart';
import 'package:cashdeck/features/chat/presentation/chat_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

enum AttachKind { photo, pdf, file }

const Map<AttachKind, List<String>> attachExtensions = {
  AttachKind.photo: ['jpg', 'jpeg', 'png', 'heic'],
  AttachKind.pdf: ['pdf'],
  AttachKind.file: [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'heic',
    'm4a',
    'mp3',
    'aac',
    'wav',
    'ogg',
  ],
};

class ConversationScreen extends ConsumerWidget {
  const new({required this.threadId, super.key});

  static const inputKey = Key('chat-input');
  static const sendKey = Key('chat-send');
  static const attachKey = Key('chat-attach');
  static const thinkingKey = Key('chat-thinking');

  static Key attachOptionKey(AttachKind kind) =>
      Key('chat-attach-${kind.name}');

  static Key fileChipKey(int index) => Key('chat-file-$index');

  static Key messageKey(String id) => Key('chat-message-$id');

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = conversationControllerProvider(threadId);
    final conversation = ref.watch(provider);
    final thread = (ref.watch(chatThreadsControllerProvider).value ?? const [])
        .where((item) => item.id == threadId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(thread?.title ?? l10n.chatUntitledThread)),
      body: switch (conversation) {
        AsyncData(:final value) => Column(
          children: [
            Expanded(
              child: value.messages.isEmpty
                  ? CdEmptyState(
                      icon: Symbols.forum_rounded,
                      title: l10n.chatConversationEmptyTitle,
                      message: l10n.chatConversationEmptyMessage,
                    )
                  : _Messages(threadId: threadId, conversation: value),
            ),
            if (value.sending)
              Padding(
                key: thinkingKey,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  l10n.chatThinking,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: context.palette.onSurfaceVariant,
                  ),
                ),
              ),
            _Composer(threadId: threadId, sending: value.sending),
          ],
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(provider),
        ),
        _ => const CdSkeleton(rows: 3),
      },
    );
  }
}

class _Messages extends StatelessWidget {
  const new({required this.threadId, required this.conversation});

  final String threadId;
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final messages = conversation.messages.reversed.toList();
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      itemCount: messages.length,
      itemBuilder: (context, index) => _Bubble(
        threadId: threadId,
        message: messages[index],
        resolving: conversation.resolving,
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const new({
    required this.threadId,
    required this.message,
    required this.resolving,
  });

  final String threadId;
  final ChatMessage message;
  final Set<String> resolving;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final mine = message.role == ChatRole.user;
    final notice = message.notice;
    final text = message.text.trim();
    return Align(
      key: ConversationScreen.messageKey(message.id),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: mine
                        ? palette.primaryContainer
                        : palette.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    text,
                    style: AppTextStyles.bodyLg.copyWith(
                      color: mine
                          ? palette.onPrimaryContainer
                          : palette.onSurface,
                    ),
                  ),
                ),
              for (final attachment in message.attachments)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Chip(
                    avatar: const Icon(Symbols.attach_file_rounded, size: 18),
                    label: Text(attachment.fileName),
                  ),
                ),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    chatNoticeText(l10n, notice),
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final action in message.actions)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: ChatActionCard(
                    threadId: threadId,
                    action: action,
                    busy: resolving.contains(action.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const new({required this.threadId, required this.sending});

  final String threadId;
  final bool sending;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _text = TextEditingController();
  final List<LocalFile> _files = [];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final l10n = AppLocalizations.of(context);
    final kind = await showOptionsSheet<AttachKind>(
      context,
      title: l10n.chatAttachTitle,
      options: [
        PickerOption(
          value: AttachKind.photo,
          label: l10n.chatAttachPhoto,
          key: ConversationScreen.attachOptionKey(AttachKind.photo),
          icon: Symbols.photo_camera_rounded,
        ),
        PickerOption(
          value: AttachKind.pdf,
          label: l10n.chatAttachPdf,
          key: ConversationScreen.attachOptionKey(AttachKind.pdf),
          icon: Symbols.picture_as_pdf_rounded,
        ),
        PickerOption(
          value: AttachKind.file,
          label: l10n.chatAttachFile,
          key: ConversationScreen.attachOptionKey(AttachKind.file),
          icon: Symbols.attach_file_rounded,
        ),
      ],
    );
    if (kind == null) return;
    final file = await ref
        .read(fileChooserProvider)
        .choose(attachExtensions[kind.$1]!);
    if (file == null || !mounted) return;
    setState(() => _files.add(file));
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final draft = ChatDraft(text: _text.text, files: List.of(_files));
    final problem = draft.problem;
    if (problem != null) {
      await showCdToast(
        context,
        icon: Symbols.error_rounded,
        message: draftProblemText(l10n, problem),
      );
      return;
    }
    final failure = await ref
        .read(conversationControllerProvider(widget.threadId).notifier)
        .send(draft);
    if (!mounted) return;
    if (failure != null) {
      await showOutcomeToast(context, failure, success: '');
      return;
    }
    _text.clear();
    setState(_files.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceContainerLow,
          border: Border(top: BorderSide(color: palette.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_files.isNotEmpty)
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final (index, file) in _files.indexed)
                    InputChip(
                      key: ConversationScreen.fileChipKey(index),
                      label: Text(file.name),
                      onDeleted: () => setState(() => _files.removeAt(index)),
                    ),
                ],
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: ConversationScreen.attachKey,
                  tooltip: l10n.chatAttachTitle,
                  onPressed: widget.sending ? null : _attach,
                  icon: const Icon(Symbols.attach_file_rounded),
                ),
                Expanded(
                  child: TextField(
                    key: ConversationScreen.inputKey,
                    controller: _text,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppTextStyles.bodyLg.copyWith(
                      color: palette.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.chatInputHint,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  key: ConversationScreen.sendKey,
                  tooltip: l10n.chatSend,
                  onPressed: widget.sending ? null : _send,
                  icon: Icon(Symbols.send_rounded, color: palette.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
