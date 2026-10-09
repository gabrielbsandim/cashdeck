import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/chat/application/chat_use_cases.dart';
import 'package:cashdeck/features/chat/data/api_chat_repository.dart';
import 'package:cashdeck/features/chat/data/fake_chat_repository.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeChatRepository(ref.watch(clockProvider)),
    Backend.api => ApiChatRepository(ref.watch(dioProvider)),
  };
});

final listChatThreadsProvider = Provider<ListChatThreads>(
  (ref) => ListChatThreads(ref.watch(chatRepositoryProvider)),
);

final startChatThreadProvider = Provider<StartChatThread>(
  (ref) => StartChatThread(ref.watch(chatRepositoryProvider)),
);

final loadConversationProvider = Provider<LoadConversation>(
  (ref) => LoadConversation(ref.watch(chatRepositoryProvider)),
);

final sendChatMessageProvider = Provider<SendChatMessage>(
  (ref) => SendChatMessage(ref.watch(chatRepositoryProvider)),
);

final confirmChatActionProvider = Provider<ConfirmChatAction>(
  (ref) => ConfirmChatAction(ref.watch(chatRepositoryProvider)),
);

final cancelChatActionProvider = Provider<CancelChatAction>(
  (ref) => CancelChatAction(ref.watch(chatRepositoryProvider)),
);
