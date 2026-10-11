import 'dart:math';

import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/chat/chat_providers.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

class ChatThreadsController extends AsyncNotifier<List<ChatThread>> {
  @override
  Future<List<ChatThread>> build() async =>
      (await ref.watch(listChatThreadsProvider).call()).orThrow;

  Future<Result<ChatThread>> start(EntityScope scope) async {
    final result = await ref.read(startChatThreadProvider).call(scope);
    if (result case Ok(:final value)) {
      state = AsyncData([value, ...?state.value]);
    }
    return result;
  }
}

final AsyncNotifierProvider<ChatThreadsController, List<ChatThread>>
chatThreadsControllerProvider =
    AsyncNotifierProvider.autoDispose<ChatThreadsController, List<ChatThread>>(
      ChatThreadsController.new,
      retry: noRetry,
    );

/// A stored thread, or a new conversation that has no thread until its first
/// message; each new screen gets its own [draftId].
final class ConversationKey extends Equatable {
  const new thread(String this.threadId) : draftId = null;

  const new draft(String this.draftId) : threadId = null;

  final String? threadId;
  final String? draftId;

  @override
  List<Object?> get props => [threadId, draftId];
}

final _random = Random.secure();

/// 32 hex characters, sent again on a retry so the server answers once.
String newClientId() =>
    [for (var i = 0; i < 16; i++) _random.nextInt(256).toRadixString(16)]
        .map((byte) => byte.padLeft(2, '0'))
        .join();

final class Conversation extends Equatable {
  const new({
    required this.messages,
    this.threadId,
    this.outgoing,
    this.resolving = const {},
  });

  /// Null until a new conversation sends its first message.
  final String? threadId;
  final List<ChatMessage> messages;

  /// The message on its way, or the one that failed to go.
  final OutgoingMessage? outgoing;

  /// The actions with a confirm or a cancel on the way.
  final Set<String> resolving;

  /// An answer is being written; nothing else can be sent meanwhile.
  bool get sending => outgoing?.delivery == Delivery.sending;

  Conversation copyWith({
    String? threadId,
    List<ChatMessage>? messages,
    OutgoingMessage? Function()? outgoing,
    Set<String>? resolving,
  }) => Conversation(
    threadId: threadId ?? this.threadId,
    messages: messages ?? this.messages,
    outgoing: outgoing == null ? this.outgoing : outgoing(),
    resolving: resolving ?? this.resolving,
  );

  @override
  List<Object?> get props => [threadId, messages, outgoing, resolving];
}

class ConversationController extends AsyncNotifier<Conversation> {
  new(this.key);

  final ConversationKey key;

  @override
  Future<Conversation> build() async {
    final threadId = key.threadId;
    if (threadId == null) return const Conversation(messages: []);
    return Conversation(
      threadId: threadId,
      messages: (await ref.watch(loadConversationProvider).call(threadId))
          .orThrow,
    );
  }

  Conversation? get _idle {
    final current = state.value;
    if (current == null || current.sending) return null;
    return current;
  }

  /// Shows [draft] at once and sends it; a failure stays on the bubble.
  Future<void> send(ChatDraft draft) async {
    final current = _idle;
    if (current == null) return;
    final outgoing = OutgoingMessage(
      clientId: newClientId(),
      text: draft.text.trim(),
      files: draft.files,
      createdAt: ref.read(clockProvider).now(),
    );
    state = AsyncData(current.copyWith(outgoing: () => outgoing));
    await _deliver(outgoing);
  }

  /// Sends the failed message again with the same client id.
  Future<void> retry() async {
    final failed = _idle?.outgoing;
    if (failed == null) return;
    final outgoing = failed.sending();
    state = AsyncData(state.requireValue.copyWith(outgoing: () => outgoing));
    await _deliver(outgoing);
  }

  /// Drops the failed message, returning it so it can be edited.
  OutgoingMessage? discard() {
    final current = _idle;
    final failed = current?.outgoing;
    if (current == null || failed == null) return null;
    state = AsyncData(current.copyWith(outgoing: () => null));
    return failed;
  }

  Future<void> _deliver(OutgoingMessage outgoing) async {
    final thread = await _thread();
    if (!ref.mounted) return;
    final threadId = thread.$1;
    if (threadId == null) {
      _fail(outgoing, thread.$2!);
      return;
    }
    final result = await ref
        .read(sendChatMessageProvider)
        .call(
          threadId,
          ChatDraft(text: outgoing.text, files: outgoing.files),
          clientId: outgoing.clientId,
        );
    if (!ref.mounted) return;
    final latest = state.requireValue;
    switch (result) {
      case Ok(:final value):
        state = AsyncData(
          latest.copyWith(
            messages: [...latest.messages, ...value],
            outgoing: () => null,
          ),
        );
        ref.invalidate(chatThreadsControllerProvider);
      case Err(:final failure):
        _fail(outgoing, failure);
    }
  }

  void _fail(OutgoingMessage outgoing, AppFailure failure) {
    state = AsyncData(
      state.requireValue.copyWith(outgoing: () => outgoing.failedWith(failure)),
    );
  }

  /// The thread to send to, started over the switcher's scope when this is a
  /// new conversation.
  Future<(String?, AppFailure?)> _thread() async {
    final known = state.requireValue.threadId;
    if (known != null) return (known, null);
    final result = await ref
        .read(chatThreadsControllerProvider.notifier)
        .start(ref.read(entityScopeProvider));
    if (!ref.mounted) return (null, const UnexpectedFailure());
    switch (result) {
      case Ok(:final value):
        state = AsyncData(state.requireValue.copyWith(threadId: value.id));
        return (value.id, null);
      case Err(:final failure):
        return (null, failure);
    }
  }

  /// A new answer to the user message [messageId], with [text] in place of
  /// what it said when given. Every later message goes; on a failure they
  /// come back and the failure is returned.
  Future<AppFailure?> regenerate(String messageId, {String? text}) async {
    final current = _idle;
    final threadId = current?.threadId;
    if (current == null || threadId == null) return null;
    final index = current.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return const NotFoundFailure();
    final original = current.messages[index];
    final outgoing = OutgoingMessage(
      clientId: newClientId(),
      text: text?.trim() ?? original.text,
      attachments: original.attachments,
      editOf: messageId,
      createdAt: original.createdAt,
    );
    state = AsyncData(
      current.copyWith(
        messages: current.messages.take(index).toList(),
        outgoing: () => outgoing,
      ),
    );
    final result = await ref
        .read(regenerateChatAnswerProvider)
        .call(threadId, messageId, text: text);
    if (!ref.mounted) return null;
    final latest = state.requireValue;
    switch (result) {
      case Ok(:final value):
        state = AsyncData(
          latest.copyWith(
            messages: [...latest.messages, ...value],
            outgoing: () => null,
          ),
        );
        ref.invalidate(chatThreadsControllerProvider);
        return null;
      case Err(:final failure):
        state = AsyncData(
          latest.copyWith(messages: current.messages, outgoing: () => null),
        );
        return failure;
    }
  }

  /// Asks again for the answer [answer], through the user message before it.
  Future<AppFailure?> retryAnswer(ChatMessage answer) {
    final messages = state.value?.messages ?? const <ChatMessage>[];
    final index = messages.indexWhere((m) => m.id == answer.id);
    final question = messages
        .take(index < 0 ? 0 : index)
        .lastWhere((m) => m.isMine, orElse: () => answer);
    if (!question.isMine) return Future.value(const NotFoundFailure());
    return regenerate(question.id);
  }

  Future<AppFailure?> confirm(ChatAction action, {EntityKind? entity}) =>
      _resolve(
        action,
        () =>
            ref.read(confirmChatActionProvider).call(action.id, entity: entity),
      );

  Future<AppFailure?> cancel(ChatAction action) => _resolve(
    action,
    () => ref.read(cancelChatActionProvider).call(action.id),
  );

  Future<AppFailure?> _resolve(
    ChatAction action,
    Future<Result<ChatAction>> Function() request,
  ) async {
    final current = state.value;
    if (current == null || current.resolving.contains(action.id)) return null;
    state = AsyncData(
      current.copyWith(resolving: {...current.resolving, action.id}),
    );
    final result = await request();
    final latest = state.value ?? current;
    final resolving = {...latest.resolving}..remove(action.id);
    switch (result) {
      case Ok(:final value):
        state = AsyncData(
          latest.copyWith(
            messages: [
              for (final message in latest.messages) message.withAction(value),
            ],
            resolving: resolving,
          ),
        );
        return null;
      case Err(:final failure):
        state = AsyncData(latest.copyWith(resolving: resolving));
        return failure;
    }
  }
}

final AsyncNotifierProviderFamily<
  ConversationController,
  Conversation,
  ConversationKey
>
conversationControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ConversationController, Conversation, ConversationKey>(
      ConversationController.new,
      retry: noRetry,
    );
