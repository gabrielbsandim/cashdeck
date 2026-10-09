import 'dart:typed_data';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/chat/chat_providers.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/chat/presentation/chat_action_card.dart';
import 'package:cashdeck/features/chat/presentation/chat_labels.dart';
import 'package:cashdeck/features/chat/presentation/chat_screen.dart';
import 'package:cashdeck/features/chat/presentation/conversation_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:flutter/material.dart';
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

Future<void> _attach(WidgetTester tester, AttachKind kind) async {
  await tester.tap(find.byKey(ConversationScreen.attachKey));
  await settle(tester);
  await tester.tap(find.byKey(ConversationScreen.attachOptionKey(kind)));
  await settle(tester);
}

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

  testWidgets('a new thread asks to pay a bill and confirms it', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.chat);

    await tester.tap(find.byKey(ChatScreen.newThreadKey));
    await settle(tester);
    expect(app.location, startsWith('${AppRoutes.chat}/'));
    expect(find.text(l10n.chatConversationEmptyTitle), findsOneWidget);
    expect(find.text(l10n.chatUntitledThread), findsOneWidget);

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
    expect(find.byKey(ConversationScreen.thinkingKey), findsOneWidget);
    await settle(tester);

    expect(find.byKey(ConversationScreen.thinkingKey), findsNothing);
    expect(find.text(l10n.chatToolPayBill), findsOneWidget);
    expect(find.text('Energia Lumina'), findsOneWidget);
    expect(find.text(l10n.chatActionPending), findsOneWidget);
    expect(find.text(l10n.chatActionWhichEntity), findsNothing);

    await tester.tap(_keyStarting('chat-action-confirm-'));
    await settle(tester);
    expect(find.text(l10n.chatActionConfirmed), findsOneWidget);
    expect(find.text(l10n.chatActionDone), findsOneWidget);
    expect(_keyStarting('chat-action-confirm-'), findsNothing);
    expect(find.text('Quero pagar a luz'), findsWidgets);
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

  testWidgets('failures show a retry or a toast', (tester) async {
    final repository = MockChatRepository();
    var threadCalls = 0;
    var messageCalls = 0;
    final failed = testAction(
      id: 'action-2',
      status: ChatActionStatus.failed,
      error: 'Saldo insuficiente.',
    );
    when(repository.threads).thenAnswer(
      (_) async => threadCalls++ == 0
          ? const Err(NetworkFailure())
          : Ok([testThread(title: null)]),
    );
    when(() => repository.startThread(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.messages('thread-1')).thenAnswer(
      (_) async => messageCalls++ == 0
          ? const Err(NetworkFailure())
          : Ok([
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
    when(() => repository.send(any(), any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.confirm(any(), entity: any(named: 'entity')))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    when(() => repository.cancel(any()))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final app = await pumpRoute(
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
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(app.location, AppRoutes.chat);
    await waitForToast(tester);

    await tester.tap(find.byKey(ChatScreen.threadKey('thread-1')));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);

    expect(find.text(l10n.chatNoticeRoundLimit), findsOneWidget);
    expect(find.text('extrato.pdf'), findsOneWidget);
    expect(find.text(l10n.chatActionFailed), findsOneWidget);
    expect(find.text('Saldo insuficiente.'), findsOneWidget);

    await _send(tester, 'Oi');
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.text('Oi'), findsOneWidget);
    await waitForToast(tester);

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
