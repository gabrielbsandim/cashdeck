import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/chat/application/chat_use_cases.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/builders.dart';
import '../../../support/mocks.dart';

void main() {
  late MockChatRepository repository;

  setUpAll(() => registerFallbackValue(const ChatDraft()));

  setUp(() => repository = MockChatRepository());

  test('each use case forwards to the repository', () async {
    final thread = testThread();
    final message = testMessage();
    final action = testAction();
    when(repository.threads).thenAnswer((_) async => Ok([thread]));
    when(() => repository.startThread(EntityScope.company))
        .thenAnswer((_) async => Ok(thread));
    when(() => repository.messages('thread-1'))
        .thenAnswer((_) async => Ok([message]));
    when(() => repository.send('thread-1', const ChatDraft(text: 'Oi')))
        .thenAnswer((_) async => Ok([message]));
    when(() => repository.confirm('action-1', entity: EntityKind.company))
        .thenAnswer((_) async => Ok(action));
    when(() => repository.cancel('action-1'))
        .thenAnswer((_) async => Ok(action));

    expect(await ListChatThreads(repository).call(), Ok([thread]));
    expect(
      await StartChatThread(repository).call(EntityScope.company),
      Ok(thread),
    );
    expect(await LoadConversation(repository).call('thread-1'), Ok([message]));
    expect(
      await SendChatMessage(repository)
          .call('thread-1', const ChatDraft(text: 'Oi')),
      Ok([message]),
    );
    expect(
      await ConfirmChatAction(repository)
          .call('action-1', entity: EntityKind.company),
      Ok(action),
    );
    expect(await CancelChatAction(repository).call('action-1'), Ok(action));
  });

  test('a draft that breaks a rule never reaches the server', () async {
    final result = await SendChatMessage(repository)
        .call('thread-1', const ChatDraft());

    expect(result, const Err<List<ChatMessage>>(UnexpectedFailure()));
    verifyNever(() => repository.send(any(), any()));
  });
}
