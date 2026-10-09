import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

final class ListChatThreads {
  const new(this._repository);

  final ChatRepository _repository;

  Future<Result<List<ChatThread>>> call() => _repository.threads();
}

/// A new thread over [EntityScope], the one the switcher shows.
final class StartChatThread {
  const new(this._repository);

  final ChatRepository _repository;

  Future<Result<ChatThread>> call(EntityScope scope) =>
      _repository.startThread(scope);
}

final class LoadConversation {
  const new(this._repository);

  final ChatRepository _repository;

  Future<Result<List<ChatMessage>>> call(String threadId) =>
      _repository.messages(threadId);
}

/// Sends a draft the composer already checked; one that breaks a rule never
/// reaches the server.
final class SendChatMessage {
  const new(this._repository);

  final ChatRepository _repository;

  Future<Result<List<ChatMessage>>> call(String threadId, ChatDraft draft) {
    if (draft.problem != null) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    return _repository.send(threadId, draft);
  }
}

final class ConfirmChatAction {
  const new(this._repository);

  final ChatRepository _repository;

  Future<Result<ChatAction>> call(String actionId, {EntityKind? entity}) =>
      _repository.confirm(actionId, entity: entity);
}

final class CancelChatAction {
  const new(this._repository);

  final ChatRepository _repository;

  Future<Result<ChatAction>> call(String actionId) =>
      _repository.cancel(actionId);
}
