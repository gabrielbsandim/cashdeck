import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/chat/chat_providers.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
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

final class Conversation extends Equatable {
  const new({
    required this.messages,
    this.sending = false,
    this.resolving = const {},
  });

  final List<ChatMessage> messages;
  final bool sending;

  /// The actions with a confirm or a cancel on the way.
  final Set<String> resolving;

  Conversation copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    Set<String>? resolving,
  }) => Conversation(
    messages: messages ?? this.messages,
    sending: sending ?? this.sending,
    resolving: resolving ?? this.resolving,
  );

  @override
  List<Object?> get props => [messages, sending, resolving];
}

class ConversationController extends AsyncNotifier<Conversation> {
  new(this.threadId);

  final String threadId;

  @override
  Future<Conversation> build() async => Conversation(
    messages: (await ref.watch(loadConversationProvider).call(threadId))
        .orThrow,
  );

  Future<AppFailure?> send(ChatDraft draft) async {
    final current = state.value;
    if (current == null || current.sending) return null;
    state = AsyncData(current.copyWith(sending: true));
    final result = await ref
        .read(sendChatMessageProvider)
        .call(threadId, draft);
    final latest = state.value ?? current;
    switch (result) {
      case Ok(:final value):
        state = AsyncData(
          latest.copyWith(
            messages: [...latest.messages, ...value],
            sending: false,
          ),
        );
        ref.invalidate(chatThreadsControllerProvider);
        return null;
      case Err(:final failure):
        state = AsyncData(latest.copyWith(sending: false));
        return failure;
    }
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

final AsyncNotifierProviderFamily<ConversationController, Conversation, String>
conversationControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ConversationController, Conversation, String>(
      ConversationController.new,
      retry: noRetry,
    );
