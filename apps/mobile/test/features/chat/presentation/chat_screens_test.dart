import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/chat/chat_providers.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/chat/presentation/chat_action_card.dart';
import 'package:cashdeck/features/chat/presentation/chat_composer.dart';
import 'package:cashdeck/features/chat/presentation/chat_labels.dart';
import 'package:cashdeck/features/chat/presentation/chat_screen.dart';
import 'package:cashdeck/features/chat/presentation/conversation_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

Finder _keyStarting(String prefix) => find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith(prefix),
    _ => false,
  },
);

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(ConversationScreen.inputKey), text);
  await tester.tap(find.byKey(ConversationScreen.sendKey));
  await settle(tester);
}

EditableText _editable(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(
    of: find.byKey(ConversationScreen.inputKey),
    matching: find.byType(EditableText),
  ),
);

Future<void> _options(WidgetTester tester, String text) async {
  await tester.longPress(find.textContaining(text).first);
  await settle(tester);
}

Future<void> _attach(WidgetTester tester, AttachKind kind) async {
  await tester.tap(find.byKey(ConversationScreen.attachKey));
  await settle(tester);
  await tester.tap(find.byKey(ConversationScreen.attachOptionKey(kind)));
  await settle(tester);
}

final _notSent = '${l10n.chatNotSent}. ${l10n.errorNetwork}';

void main() {
  setUpAll(() {
    registerFallbackValue(const ChatDraft());
    registerFallbackValue(EntityKind.personal);
    registerFallbackValue(EntityScope.personal);
  });

  testWidgets('lists the threads and opens one', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.chat);

    expect(find.text('Gastos com mercado'), findsOneWidget);
    await tester.tap(find.byKey(ChatScreen.threadKey('thread-welcome')));
    await settle(tester);

    expect(app.location, AppRoutes.chatThread('thread-welcome'));
    expect(find.text('Quanto gastei com mercado este mês?'), findsOneWidget);
  });

  testWidgets('a new conversation starts its thread with the first message', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.chat);

    await tester.tap(find.byKey(ChatScreen.newThreadKey));
    await settle(tester);
    expect(app.location, AppRoutes.chatNew);
    expect(find.byType(EntityChip), findsOneWidget);
    expect(find.byKey(ChatSuggestions.suggestionKey(0)), findsOneWidget);
    expect(_editable(tester).focusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(ConversationScreen.sendKey));
    await settle(tester);
    expect(find.text(l10n.chatDraftEmpty), findsOneWidget);
    await waitForToast(tester);

    await tester.enterText(
      find.byKey(ConversationScreen.inputKey),
      'Quero pagar a luz',
    );
    await tester.tap(find.byKey(ConversationScreen.sendKey));
    await tester.pump();
    expect(find.byKey(ConversationScreen.outgoingKey), findsOneWidget);
    expect(find.text(l10n.chatSending), findsOneWidget);
    expect(find.byKey(ConversationScreen.thinkingKey), findsOneWidget);
    await settle(tester);

    expect(find.byKey(ConversationScreen.thinkingKey), findsNothing);
    expect(find.byKey(ConversationScreen.outgoingKey), findsNothing);
    expect(find.text(l10n.chatToolPayBill), findsOneWidget);
    expect(find.text('Energia Lumina'), findsOneWidget);
    expect(find.text(l10n.chatActionPending), findsOneWidget);
    expect(find.text(l10n.chatActionWhichEntity), findsNothing);
    expect(find.byType(EntityChip), findsNothing);

    await tester.tap(_keyStarting('chat-action-confirm-'));
    await settle(tester);
    expect(find.text(l10n.chatActionConfirmed), findsOneWidget);
    expect(find.text(l10n.chatActionDone), findsOneWidget);
    expect(_keyStarting('chat-action-confirm-'), findsNothing);
    expect(find.text('Quero pagar a luz'), findsWidgets);

    await tester.tap(find.byKey(ConversationScreen.historyKey));
    await settle(tester);
    expect(app.location, AppRoutes.chat);
    expect(find.byKey(ChatScreen.threadKey('thread-1')), findsOneWidget);
  });

  testWidgets('a suggestion asks at once', (tester) async {
    await pumpRoute(tester, AppRoutes.chatNew);

    await tester.tap(find.byKey(ChatSuggestions.suggestionKey(2)));
    await settle(tester);

    expect(find.text(l10n.chatSuggestionMonth), findsWidgets);
    expect(find.textContaining('Neste mês entraram'), findsOneWidget);
  });

  testWidgets('the Pix suggestion mentions a saved contact', (tester) async {
    await pumpRoute(tester, AppRoutes.chatNew);

    await tester.tap(find.byKey(ChatSuggestions.pixKey));
    await settle(tester);
    expect(_editable(tester).controller.text, l10n.chatSuggestionPixDraft);
    expect(find.byKey(ConversationScreen.mentionPanelKey), findsOneWidget);
    expect(find.byKey(ConversationScreen.mentionKey('diarista')), findsOne);

    await tester.enterText(find.byKey(ConversationScreen.inputKey), '@zzz');
    await settle(tester);
    expect(find.text(l10n.chatMentionsEmpty), findsOneWidget);

    await tester.enterText(
      find.byKey(ConversationScreen.inputKey),
      'Fazer um Pix para @mar',
    );
    await settle(tester);
    expect(find.byKey(ConversationScreen.mentionKey('diarista')), findsNothing);
    await tester.tap(find.byKey(ConversationScreen.mentionKey('marina')));
    await settle(tester);

    expect(_editable(tester).controller.text, 'Fazer um Pix para @marina ');
    expect(find.byKey(ConversationScreen.mentionPanelKey), findsNothing);

    await tester.tap(find.byKey(ConversationScreen.sendKey));
    await settle(tester);

    expect(find.text(l10n.chatToolSendPix), findsOneWidget);
    expect(find.text('@marina'), findsWidgets);
    expect(find.byKey(ChatActionCard.newContactKey), findsNothing);
  });

  testWidgets('a Pix to someone new says the contact will be saved', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.chatNew);

    await _send(tester, r'Pix de R$ 20,50 para a Ana');

    expect(find.byKey(ChatActionCard.newContactKey), findsOneWidget);
    expect(find.text(l10n.chatNewContactNote('ana.exemplo')), findsOneWidget);
    expect(find.textContaining('ana@exemplo.com'), findsOneWidget);

    await tester.tap(_keyStarting('chat-action-confirm-'));
    await settle(tester);

    expect(find.text(l10n.chatActionConfirmed), findsOneWidget);
    expect(find.byKey(ChatActionCard.newContactKey), findsNothing);
  });

  testWidgets('a message can be copied, edited or answered again', (
    tester,
  ) async {
    const question = 'Quanto gastei com mercado este mês?';
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpRoute(tester, AppRoutes.chatThread('thread-welcome'));

    await _options(tester, question);
    expect(
      find.byKey(ConversationScreen.optionKey(MessageOption.regenerate)),
      findsNothing,
    );
    await tester.tap(
      find.byKey(ConversationScreen.optionKey(MessageOption.copy)),
    );
    await settle(tester);
    expect(copied, [question]);
    expect(find.text(l10n.chatCopied), findsOneWidget);
    await waitForToast(tester);

    await _options(tester, question);
    await tester.tap(
      find.byKey(ConversationScreen.optionKey(MessageOption.edit)),
    );
    await settle(tester);
    expect(find.byKey(ConversationScreen.editBannerKey), findsOneWidget);
    expect(_editable(tester).controller.text, question);
    await tester.tap(find.byKey(ConversationScreen.cancelEditKey));
    await settle(tester);
    expect(find.byKey(ConversationScreen.editBannerKey), findsNothing);
    expect(_editable(tester).controller.text, isEmpty);

    await _options(tester, question);
    await tester.tap(
      find.byKey(ConversationScreen.optionKey(MessageOption.edit)),
    );
    await settle(tester);
    await _send(tester, 'Quanto gastei com farmácia?');

    expect(find.byKey(ConversationScreen.editBannerKey), findsNothing);
    expect(find.text(question), findsNothing);
    expect(find.text('Quanto gastei com farmácia?'), findsOneWidget);
    expect(find.textContaining('Neste mês entraram'), findsOneWidget);
    expect(find.textContaining('Você gastou'), findsNothing);

    await _options(tester, 'Neste mês entraram');
    expect(
      find.byKey(ConversationScreen.optionKey(MessageOption.edit)),
      findsNothing,
    );
    await tester.tap(
      find.byKey(ConversationScreen.optionKey(MessageOption.regenerate)),
    );
    await settle(tester);

    expect(find.text('Quanto gastei com farmácia?'), findsOneWidget);
    expect(find.textContaining('Neste mês entraram'), findsOneWidget);
  });

  testWidgets('a consolidated thread takes a file and asks for the entity', (
    tester,
  ) async {
    final chooser = FakeFileChooser();
    await pumpRoute(
      tester,
      AppRoutes.chat,
      overrides: [fileChooserProvider.overrideWithValue(chooser)],
    );
    await tester.tap(
      find.byKey(EntitySwitcher.segmentKey(EntityScope.consolidated)),
    );
    await settle(tester);
    await tester.tap(find.byKey(ChatScreen.newThreadKey));
    await settle(tester);

    await _attach(tester, AttachKind.photo);
    expect(chooser.requests.single, attachExtensions[AttachKind.photo]);
    expect(find.byKey(ConversationScreen.fileChipKey(0)), findsNothing);

    await tester.tap(find.byKey(ConversationScreen.attachKey));
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(chooser.requests, hasLength(1));

    chooser.next = LocalFile(name: 'boleto.pdf', bytes: Uint8List(10));
    await _attach(tester, AttachKind.pdf);
    await _attach(tester, AttachKind.file);
    expect(find.byKey(ConversationScreen.fileChipKey(1)), findsOneWidget);
    tester
        .widget<InputChip>(find.byKey(ConversationScreen.fileChipKey(1)))
        .onDeleted!();
    await settle(tester);
    expect(find.byKey(ConversationScreen.fileChipKey(1)), findsNothing);

    await tester.tap(find.byKey(ConversationScreen.sendKey));
    await settle(tester);

    expect(find.byKey(ConversationScreen.fileChipKey(0)), findsNothing);
    expect(find.text(l10n.chatToolCreateBill), findsOneWidget);
    expect(find.text('boleto.pdf'), findsNWidgets(3));
    expect(find.text(l10n.chatActionWhichEntity), findsOneWidget);

    await tester.tap(_keyStarting('chat-action-confirm-'));
    await settle(tester);
    expect(find.text(l10n.chatActionPending), findsOneWidget);

    await tester.tap(find.byKey(ChatActionCard.entityKey(EntityKind.company)));
    await settle(tester);
    await tester.tap(_keyStarting('chat-action-confirm-'));
    await settle(tester);
    expect(find.text(l10n.chatActionConfirmed), findsOneWidget);
  });

  testWidgets('a proposal can be cancelled', (tester) async {
    await pumpRoute(tester, AppRoutes.chat);
    await tester.tap(find.byKey(ChatScreen.newThreadKey));
    await settle(tester);
    await _send(tester, 'Pagar energia');

    await tester.tap(_keyStarting('chat-action-cancel-'));
    await settle(tester);

    expect(find.text(l10n.chatActionCancelled), findsOneWidget);
    expect(_keyStarting('chat-action-cancel-'), findsNothing);
  });

  testWidgets('a plain question gets a plain answer', (tester) async {
    await pumpRoute(tester, AppRoutes.chatThread('thread-welcome'));
    await _send(tester, 'Como foi o mês?');

    expect(find.textContaining('Neste mês entraram'), findsWidgets);
  });

  testWidgets('a list or a new thread that fails can be tried again', (
    tester,
  ) async {
    final repository = MockChatRepository();
    var threadCalls = 0;
    when(repository.threads).thenAnswer(
      (_) async => threadCalls++ == 0
          ? const Err(NetworkFailure())
          : Ok([testThread(title: null)]),
    );
    when(() => repository.startThread(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.chat,
      overrides: [chatRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.text(l10n.errorNetwork), findsOneWidget);
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    expect(find.byKey(ChatScreen.threadKey('thread-1')), findsOneWidget);

    await tester.tap(find.byKey(ChatScreen.newThreadKey));
    await settle(tester);
    await _send(tester, 'Oi');

    expect(find.text(_notSent), findsOneWidget);
    expect(find.byKey(ChatSuggestions.pixKey), findsNothing);
    await tester.tap(find.byKey(ConversationScreen.retrySendKey));
    await settle(tester);
    expect(find.text(_notSent), findsOneWidget);
    verify(() => repository.startThread(any())).called(2);

    await tester.tap(find.byKey(ConversationScreen.discardKey));
    await settle(tester);
    expect(find.byKey(ConversationScreen.outgoingKey), findsNothing);
    expect(find.byKey(ChatSuggestions.pixKey), findsOneWidget);

    await _send(tester, 'Oi de novo');
    await tester.tap(find.byKey(ConversationScreen.editFailedKey));
    await settle(tester);
    expect(find.byKey(ConversationScreen.outgoingKey), findsNothing);
    expect(_editable(tester).controller.text, 'Oi de novo');
  });

  testWidgets('a stored thread retries sends, answers and actions', (
    tester,
  ) async {
    final repository = MockChatRepository();
    var messageCalls = 0;
    var sendCalls = 0;
    final failed = testAction(
      id: 'action-2',
      status: ChatActionStatus.failed,
      error: 'Saldo insuficiente.',
    );
    final question = testMessage(
      id: 'msg-0',
      role: ChatRole.user,
      text: 'Pague a conta',
    );
    when(repository.threads).thenAnswer((_) async => Ok([testThread()]));
    when(() => repository.messages('thread-1')).thenAnswer(
      (_) async => messageCalls++ == 0
          ? const Err(NetworkFailure())
          : Ok([
              question,
              testMessage(
                notice: ChatNotice.roundLimit,
                actions: [testAction(), failed],
                attachments: const [
                  ChatAttachment(
                    id: 'att-1',
                    fileName: 'extrato.pdf',
                    mimeType: 'application/pdf',
                    size: 10,
                  ),
                ],
              ),
            ]),
    );
    when(() => repository.send(any(), any(), clientId: any(named: 'clientId')))
        .thenAnswer(
          (_) async => sendCalls++ == 0
              ? const Err(NetworkFailure())
              : Ok([
                  testMessage(id: 'msg-2', role: ChatRole.user, text: 'Oi'),
                  testMessage(id: 'msg-3', text: 'Olá! Como posso ajudar?'),
                ]),
        );
    when(() => repository.regenerate(any(), any(), text: any(named: 'text')))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.confirm(any(), entity: any(named: 'entity')))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.cancel(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.chatThread('thread-1'),
      overrides: [chatRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.text(l10n.errorNetwork), findsOneWidget);
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);

    expect(find.text('Conversa de exemplo'), findsOneWidget);
    expect(find.text(l10n.chatNoticeRoundLimit), findsOneWidget);
    expect(find.text('extrato.pdf'), findsOneWidget);
    expect(find.text(l10n.chatActionFailed), findsOneWidget);
    expect(find.text('Saldo insuficiente.'), findsOneWidget);

    await tester.tap(find.byKey(ConversationScreen.retryAnswerKey('msg-1')));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.text(l10n.chatNoticeRoundLimit), findsOneWidget);
    verify(() => repository.regenerate('thread-1', 'msg-0')).called(1);
    await waitForToast(tester);

    await _options(tester, 'Pague a conta');
    await tester.tap(
      find.byKey(ConversationScreen.optionKey(MessageOption.edit)),
    );
    await settle(tester);
    expect(find.text(l10n.chatEditingNote), findsNothing);
    await _send(tester, 'Pague a luz');
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.byKey(ConversationScreen.editBannerKey), findsOneWidget);
    expect(_editable(tester).controller.text, 'Pague a luz');
    await waitForToast(tester);
    await tester.tap(find.byKey(ConversationScreen.cancelEditKey));
    await settle(tester);

    await _send(tester, 'Oi');
    expect(find.text(_notSent), findsOneWidget);
    expect(find.text('Oi'), findsOneWidget);
    await tester.tap(find.byKey(ConversationScreen.retrySendKey));
    await settle(tester);
    expect(find.text(_notSent), findsNothing);
    expect(find.text('Olá! Como posso ajudar?'), findsOneWidget);
    final clientIds = verify(
      () => repository.send(
        'thread-1',
        any(),
        clientId: captureAny(named: 'clientId'),
      ),
    ).captured;
    expect(clientIds, hasLength(2));
    expect(clientIds.first, clientIds.last);
    expect(clientIds.first as String, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(
      find.byKey(ConversationScreen.retryAnswerKey('msg-1')),
      findsNothing,
    );

    await _options(tester, 'Pague a conta');
    await tester.tap(
      find.byKey(ConversationScreen.optionKey(MessageOption.edit)),
    );
    await settle(tester);
    expect(find.text(l10n.chatEditingNote), findsOneWidget);
    await tester.tap(find.byKey(ConversationScreen.cancelEditKey));
    await settle(tester);

    await tester.tap(find.byKey(ChatActionCard.confirmKey('action-1')));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    await waitForToast(tester);

    await tester.tap(find.byKey(ChatActionCard.cancelKey('action-1')));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.text(l10n.chatActionPending), findsOneWidget);
  });

  testWidgets('no threads yet shows the empty state', (tester) async {
    final repository = MockChatRepository();
    when(repository.threads).thenAnswer((_) async => const Ok([]));
    await pumpRoute(
      tester,
      AppRoutes.chat,
      overrides: [chatRepositoryProvider.overrideWithValue(repository)],
    );

    expect(find.text(l10n.chatEmptyTitle), findsOneWidget);
  });

  test('labels cover every tool, status, notice and draft problem', () {
    for (final tool in ChatTool.values) {
      expect(chatToolTitle(l10n, tool), isNotEmpty);
      expect(chatToolIcon(tool), isNotNull);
    }
    for (final status in ChatActionStatus.values) {
      expect(chatActionStatusOf(l10n, status).$1, isNotEmpty);
    }
    for (final notice in ChatNotice.values) {
      expect(chatNoticeText(l10n, notice), isNotEmpty);
    }
    for (final problem in DraftProblem.values) {
      expect(draftProblemText(l10n, problem), isNotEmpty);
    }
  });
}
