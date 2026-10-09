import 'dart:typed_data';

import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/chat/chat_providers.dart';
import 'package:cashdeck/features/chat/data/api_chat_repository.dart';
import 'package:cashdeck/features/chat/data/chat_dtos.dart';
import 'package:cashdeck/features/chat/data/fake_chat_repository.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

Map<String, dynamic> _thread([String id = 'thread-1']) => {
  'id': id,
  'scope': 'ALL',
  'title': null,
  'createdAt': '2026-10-08T12:00:00.000Z',
  'updatedAt': '2026-10-08T12:00:00.000Z',
};

Map<String, dynamic> _action({String status = 'PENDING', Object? result}) => {
  'id': 'action-1',
  'threadId': 'thread-1',
  'tool': 'PAY_BILL',
  'status': status,
  'entity': null,
  'needsEntity': true,
  'details': {
    'payee': 'Energia Exemplo',
    'amount': {'cents': 28740, 'currency': 'BRL'},
    'dueDate': '2026-10-12',
    'fileName': null,
    'pattern': null,
    'category': null,
    'payer': null,
  },
  'result': result,
  'error': null,
  'createdAt': '2026-10-08T12:00:00.000Z',
};

Map<String, dynamic> _message({
  String id = 'msg-1',
  String role = 'assistant',
  String? notice,
}) => {
  'id': id,
  'threadId': 'thread-1',
  'role': role,
  'text': 'Olá',
  'notice': notice,
  'attachments': [
    {
      'id': 'att-1',
      'fileName': 'boleto.pdf',
      'mimeType': 'application/pdf',
      'size': 10,
    },
  ],
  'actions': [_action()],
  'createdAt': '2026-10-08T12:00:00.000Z',
};

void main() {
  group('dtos', () {
    test('read threads, messages and actions', () {
      final thread = threadFromJson(_thread());
      final message = messageFromJson(_message(notice: 'TIME_BUDGET'));
      final action = message.actions.single;

      expect(thread.scope, EntityScope.consolidated);
      expect(message.role, ChatRole.assistant);
      expect(message.notice, ChatNotice.timeBudget);
      expect(message.attachments.single.fileName, 'boleto.pdf');
      expect(action.tool, ChatTool.payBill);
      expect(action.needsEntity, isTrue);
      expect(action.entity, isNull);
      expect(action.details.amount, const Money(28_740));
      expect(action.result, isNull);
      expect(messageFromJson(_message()).notice, isNull);

      final done = actionFromJson({
        ..._action(
          status: 'CONFIRMED',
          result: {
            'billId': 'b1',
            'invoiceId': null,
            'ruleId': null,
            'updated': null,
          },
        ),
        'entity': 'PJ',
        'details': <String, dynamic>{},
      });
      expect(done.status, ChatActionStatus.confirmed);
      expect(done.entity, EntityKind.company);
      expect(done.result?.billId, 'b1');
      expect(done.details.amount, isNull);
    });

    test('every tool, status and notice is known', () {
      for (final tool in [
        'CREATE_BILL_FROM_ATTACHMENT',
        'PAY_BILL',
        'CREATE_CATEGORY_RULE',
        'DRAFT_INVOICE',
      ]) {
        expect(
          () => actionFromJson({..._action(), 'tool': tool}),
          returnsNormally,
        );
      }
      for (final status in [
        'PENDING',
        'CONFIRMED',
        'CANCELLED',
        'FAILED',
        'EXPIRED',
      ]) {
        expect(actionFromJson(_action(status: status)).status.name, isNotEmpty);
      }
      for (final notice in ['ROUND_LIMIT', 'TIME_BUDGET', 'EMPTY', 'ERROR']) {
        expect(messageFromJson(_message(notice: notice)).notice, isNotNull);
      }
      expect(
        () => messageFromJson(_message(notice: 'SLEEPY')),
        throwsFormatException,
      );
    });

    test('scopes and drafts travel as the server reads them', () {
      expect(scopeToJson(EntityScope.personal), 'PF');
      expect(scopeToJson(EntityScope.company), 'PJ');
      expect(scopeToJson(EntityScope.consolidated), 'ALL');
      expect(draftToJson(const ChatDraft(text: ' Oi ')), {'text': 'Oi'});
      final withFile = draftToJson(
        ChatDraft(
          files: [
            LocalFile(name: 'a.pdf', bytes: Uint8List.fromList([1])),
          ],
        ),
      );
      expect(withFile['attachments'], [
        {'fileName': 'a.pdf', 'mimeType': 'application/pdf', 'base64': 'AQ=='},
      ]);
    });
  });

  group('api', () {
    test('reads every page, starts, sends and resolves', () async {
      final dio = stubDio((options) {
        final key = '${options.method} ${options.path}';
        final cursor = options.queryParameters['cursor'];
        return switch (key) {
          'GET /api/v1/chat/threads' when cursor == null => StubResponse(200, {
            'data': [_thread()],
            'nextCursor': '1',
          }),
          'GET /api/v1/chat/threads' => StubResponse(200, {
            'data': [_thread('thread-2')],
            'nextCursor': null,
          }),
          'POST /api/v1/chat/threads' => StubResponse(201, {'data': _thread()}),
          'GET /api/v1/chat/threads/thread-1/messages' => StubResponse(200, {
            'data': [_message()],
            'nextCursor': null,
          }),
          'POST /api/v1/chat/threads/thread-1/messages' => StubResponse(201, {
            'data': {
              'messages': [_message(id: 'u', role: 'user'), _message()],
            },
          }),
          'POST /api/v1/chat/actions/action-1/confirm' => StubResponse(200, {
            'data': _action(status: 'CONFIRMED'),
          }),
          'POST /api/v1/chat/actions/action-1/cancel' => StubResponse(200, {
            'data': _action(status: 'CANCELLED'),
          }),
          _ => const StubResponse(404),
        };
      });
      final repository = ApiChatRepository(dio);

      final threads = _ok(await repository.threads());
      final started = _ok(await repository.startThread(EntityScope.company));
      final messages = _ok(await repository.messages('thread-1'));
      final sent = _ok(
        await repository.send('thread-1', const ChatDraft(text: 'Oi')),
      );
      final confirmed = _ok(
        await repository.confirm('action-1', entity: EntityKind.company),
      );
      final cancelled = _ok(await repository.cancel('action-1'));

      final requests = adapterOf(dio).requests;
      expect(threads.map((thread) => thread.id), ['thread-1', 'thread-2']);
      expect(started.id, 'thread-1');
      expect(requests[2].data, {'scope': 'PJ'});
      expect(messages, hasLength(1));
      expect(sent.map((message) => message.role), [
        ChatRole.user,
        ChatRole.assistant,
      ]);
      expect(requests[5].data, {'entity': 'PJ'});
      expect(confirmed.status, ChatActionStatus.confirmed);
      expect(cancelled.status, ChatActionStatus.cancelled);
      expect(requests[6].data, isEmpty);
    });

    test('the quota answer is a rate limit failure', () async {
      final dio = stubDio((_) => const StubResponse(429));

      expect(
        await ApiChatRepository(dio).send('t', const ChatDraft(text: 'Oi')),
        const Err<List<ChatMessage>>(RateLimitedFailure()),
      );
    });
  });

  group('fake', () {
    FakeChatRepository repository() =>
        FakeChatRepository(FixedClock(testNow), latency: Duration.zero);

    test('starts with a sample thread and keeps new ones on top', () async {
      final fake = repository();

      final seeded = _ok(await fake.threads());
      final started = _ok(await fake.startThread(EntityScope.company));
      final ordered = _ok(await fake.threads());

      expect(seeded.single.id, FakeChatRepository.welcomeThreadId);
      expect(ordered.first.id, started.id);
      expect(
        _ok(await fake.messages(FakeChatRepository.welcomeThreadId)),
        hasLength(2),
      );
      expect(
        await fake.messages('none'),
        const Err<List<ChatMessage>>(NotFoundFailure()),
      );
    });

    test('a plain question answers, asking to pay proposes a bill', () async {
      final fake = repository();
      final thread = _ok(await fake.startThread(EntityScope.personal));

      final plain = _ok(
        await fake.send(thread.id, const ChatDraft(text: 'Como foi o mês?')),
      );
      final pay = _ok(
        await fake.send(thread.id, const ChatDraft(text: 'Quero pagar')),
      );
      final threads = _ok(await fake.threads());

      expect(plain.last.actions, isEmpty);
      expect(pay.last.actions.single.tool, ChatTool.payBill);
      expect(pay.last.actions.single.entity, EntityKind.personal);
      expect(threads.first.title, 'Como foi o mês?');
      expect(
        await fake.send('none', const ChatDraft(text: 'x')),
        const Err<List<ChatMessage>>(NotFoundFailure()),
      );
    });

    test(
      'a file proposes a bill and a consolidated thread asks the entity',
      () async {
        final fake = repository();
        final thread = _ok(await fake.startThread(EntityScope.consolidated));
        final file = LocalFile(name: 'boleto.pdf', bytes: Uint8List(4));

        final sent = _ok(await fake.send(thread.id, ChatDraft(files: [file])));
        final action = sent.last.actions.single;

        expect(sent.first.attachments.single.fileName, 'boleto.pdf');
        expect(action.tool, ChatTool.createBillFromAttachment);
        expect(action.needsEntity, isTrue);
        expect(
          await fake.confirm(action.id),
          const Err<ChatAction>(ValidationFailure('Escolha PF ou PJ.')),
        );
        final confirmed = _ok(
          await fake.confirm(action.id, entity: EntityKind.company),
        );
        expect(confirmed.status, ChatActionStatus.confirmed);
        expect(confirmed.entity, EntityKind.company);
        expect(_ok(await fake.cancel(action.id)), confirmed);
        final stored = _ok(await fake.messages(thread.id));
        expect(stored.last.actions.single.status, ChatActionStatus.confirmed);
        expect(_ok(await fake.threads()).first.title, 'boleto.pdf');
        expect(
          await fake.cancel('none'),
          const Err<ChatAction>(NotFoundFailure()),
        );
      },
    );

    test('a long first message makes a short title', () async {
      final fake = repository();
      final thread = _ok(await fake.startThread(EntityScope.company));
      final text = 'Quanto a empresa gastou com software ' * 3;

      await fake.send(thread.id, ChatDraft(text: text));

      expect(_ok(await fake.threads()).first.title, endsWith('...'));
    });
  });

  test('the provider picks fake or api by the backend', () {
    final fake = ProviderContainer();
    addTearDown(fake.dispose);
    final api = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://api.test'),
        ),
      ],
    );
    addTearDown(api.dispose);

    expect(fake.read(chatRepositoryProvider), isA<FakeChatRepository>());
    expect(api.read(chatRepositoryProvider), isA<ApiChatRepository>());
    expect(fake.read(sendChatMessageProvider), isNotNull);
  });
}
