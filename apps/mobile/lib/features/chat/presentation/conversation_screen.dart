import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_options_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/chat/domain/mentions.dart';
import 'package:cashdeck/features/chat/presentation/chat_bubbles.dart';
import 'package:cashdeck/features/chat/presentation/chat_composer.dart';
import 'package:cashdeck/features/chat/presentation/chat_controller.dart';
import 'package:cashdeck/features/chat/presentation/chat_labels.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contacts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

enum MessageOption { copy, edit, regenerate }

/// One conversation with the assistant. Without [threadId] it is a new one:
/// the keyboard comes up at once and the thread starts with the first
/// message, over the entity the chip shows.
class ConversationScreen extends ConsumerStatefulWidget {
  const new({this.threadId, super.key});

  static const inputKey = Key('chat-input');
  static const sendKey = Key('chat-send');
  static const attachKey = Key('chat-attach');
  static const thinkingKey = Key('chat-thinking');
  static const historyKey = Key('chat-history');
  static const outgoingKey = Key('chat-outgoing');
  static const retrySendKey = Key('chat-outgoing-retry');
  static const editFailedKey = Key('chat-outgoing-edit');
  static const discardKey = Key('chat-outgoing-discard');
  static const editBannerKey = Key('chat-edit-banner');
  static const cancelEditKey = Key('chat-edit-cancel');
  static const mentionPanelKey = Key('chat-mentions');

  static Key attachOptionKey(AttachKind kind) =>
      Key('chat-attach-${kind.name}');

  static Key fileChipKey(int index) => Key('chat-file-$index');

  static Key messageKey(String id) => Key('chat-message-$id');

  static Key retryAnswerKey(String id) => Key('chat-retry-$id');

  static Key optionKey(MessageOption option) =>
      Key('chat-option-${option.name}');

  static Key mentionKey(String handle) => Key('chat-mention-$handle');

  final String? threadId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  late final ConversationKey _key = switch (widget.threadId) {
    final String id => ConversationKey.thread(id),
    null => ConversationKey.draft(newClientId()),
  };
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<LocalFile> _files = [];
  ChatMessage? _editing;
  MentionQuery? _mention;
  var _contactsWanted = false;

  ConversationController get _controller =>
      ref.read(conversationControllerProvider(_key).notifier);

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  @override
  void dispose() {
    _text
      ..removeListener(_onText)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onText() {
    final mention = mentionAt(_text.text, _text.selection.baseOffset);
    if (mention == _mention) return;
    setState(() {
      _mention = mention;
      _contactsWanted = _contactsWanted || mention != null;
    });
  }

  void _setText(String text) {
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  void _pickMention(PixContact contact) {
    final mention = _mention;
    if (mention == null) return;
    final (text, cursor) = insertMention(
      _text.text,
      mention,
      _text.selection.baseOffset,
      contact.handle,
    );
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _focus.requestFocus();
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
    final editing = _editing;
    _text.clear();
    setState(() {
      _files.clear();
      _editing = null;
    });
    if (editing != null) {
      await _sendEdit(editing, draft.text);
      return;
    }
    await _controller.send(draft);
  }

  Future<void> _sendEdit(ChatMessage message, String text) async {
    final failure = await _controller.regenerate(message.id, text: text);
    if (failure == null || !mounted) return;
    setState(() => _editing = message);
    _setText(text);
    await _toast(failure);
  }

  Future<void> _ask(String question) {
    _text.text = question;
    return _send();
  }

  void _startEdit(ChatMessage message) {
    setState(() {
      _editing = message;
      _files.clear();
    });
    _setText(message.text);
  }

  void _cancelEdit() {
    _text.clear();
    setState(() => _editing = null);
  }

  void _editFailed() {
    final failed = _controller.discard();
    if (failed == null) return;
    setState(() => _files.addAll(failed.files));
    _setText(failed.text);
  }

  Future<void> _retryAnswer(ChatMessage answer) async {
    final failure = await _controller.retryAnswer(answer);
    if (failure == null || !mounted) return;
    await _toast(failure);
  }

  Future<void> _toast(AppFailure failure) =>
      showOutcomeToast(context, failure, success: '');

  Future<void> _showOptions(ChatMessage message, {required bool busy}) async {
    final l10n = AppLocalizations.of(context);
    final options = [
      if (message.text.trim().isNotEmpty)
        PickerOption(
          value: MessageOption.copy,
          label: l10n.chatCopy,
          key: ConversationScreen.optionKey(MessageOption.copy),
          icon: Symbols.content_copy_rounded,
        ),
      if (message.isMine && !busy)
        PickerOption(
          value: MessageOption.edit,
          label: l10n.chatEdit,
          key: ConversationScreen.optionKey(MessageOption.edit),
          icon: Symbols.edit_rounded,
        ),
      if (!message.isMine && !busy)
        PickerOption(
          value: MessageOption.regenerate,
          label: l10n.chatRegenerate,
          key: ConversationScreen.optionKey(MessageOption.regenerate),
          icon: Symbols.refresh_rounded,
        ),
    ];
    if (options.isEmpty) return;
    final chosen = await showOptionsSheet<MessageOption>(
      context,
      title: l10n.chatMessageOptions,
      options: options,
    );
    if (chosen == null || !mounted) return;
    switch (chosen.$1) {
      case MessageOption.copy:
        await Clipboard.setData(ClipboardData(text: message.text.trim()));
        if (!mounted) return;
        await showCdToast(
          context,
          icon: Symbols.content_copy_rounded,
          message: l10n.chatCopied,
        );
      case MessageOption.edit:
        _startEdit(message);
      case MessageOption.regenerate:
        await _retryAnswer(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = conversationControllerProvider(_key);
    final conversation = ref.watch(provider);
    final threads = ref.watch(chatThreadsControllerProvider).value ?? const [];
    if (_contactsWanted) ref.watch(pixContactsControllerProvider);
    final threadId = conversation.value?.threadId;
    final thread = threads.where((item) => item.id == threadId).firstOrNull;
    final mention = _mention;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: threadId == null
            ? const Align(alignment: Alignment.centerLeft, child: EntityChip())
            : _ThreadTitle(thread: thread),
        actions: [
          IconButton(
            key: ConversationScreen.historyKey,
            tooltip: AppLocalizations.of(context).chatHistory,
            icon: const Icon(Symbols.history_rounded),
            onPressed: () => context.push(AppRoutes.chat),
          ),
        ],
      ),
      body: switch (conversation) {
        AsyncData(:final value) => Column(
          children: [
            Expanded(
              child: value.messages.isEmpty && value.outgoing == null
                  ? ChatSuggestions(
                      onAsk: _ask,
                      onPix: () => _setText(
                        AppLocalizations.of(context).chatSuggestionPixDraft,
                      ),
                    )
                  : _messages(value),
            ),
            if (mention != null)
              MentionPanel(query: mention.query, onPick: _pickMention),
            ChatComposer(
              controller: _text,
              focus: _focus,
              files: _files,
              sending: value.sending,
              editing: _editing != null,
              editingEarlier: _editsEarlier(value),
              autofocus: widget.threadId == null,
              onAttach: _attach,
              onSend: _send,
              onRemoveFile: (index) => setState(() => _files.removeAt(index)),
              onCancelEdit: _cancelEdit,
            ),
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

  /// The message being edited has later user messages, which will go.
  bool _editsEarlier(Conversation conversation) {
    final editing = _editing;
    if (editing == null) return false;
    final lastMine = conversation.messages.lastWhere(
      (message) => message.isMine,
      orElse: () => editing,
    );
    return lastMine.id != editing.id;
  }

  Widget _messages(Conversation conversation) {
    final messages = conversation.messages;
    final outgoing = conversation.outgoing;
    final busy = conversation.sending;
    final last = messages.lastOrNull;
    final entries = <Widget>[
      for (final message in messages)
        MessageBubble(
          conversation: _key,
          message: message,
          resolving: conversation.resolving,
          onOptions: () => _showOptions(message, busy: busy),
          onRetry: message == last && message.canRetry && !busy
              ? () => _retryAnswer(message)
              : null,
        ),
      if (outgoing != null)
        OutgoingBubble(
          outgoing: outgoing,
          onRetry: _controller.retry,
          onEdit: _editFailed,
          onDiscard: () => _controller.discard(),
        ),
      if (busy) const TypingBubble(),
    ].reversed.toList();
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      itemCount: entries.length,
      itemBuilder: (_, index) => entries[index],
    );
  }
}

class _ThreadTitle extends StatelessWidget {
  const new({required this.thread});

  final ChatThread? thread;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final thread = this.thread;
    final title = Text(
      thread?.title ?? l10n.chatUntitledThread,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.titleMd.copyWith(color: context.palette.onSurface),
    );
    if (thread == null) return title;
    return Row(
      children: [
        EntityScopeBadge(scope: thread.scope, size: 28),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: title),
      ],
    );
  }
}
