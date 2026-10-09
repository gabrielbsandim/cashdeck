import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';

/// A scripted assistant over fictional data. Asking to pay proposes the
/// energy bill; a file proposes a bill read from it. Lives in memory.
final class FakeChatRepository implements ChatRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 400)});

  final Clock _clock;
  final Duration latency;
  final Map<String, ChatThread> _threads = {};
  final Map<String, List<ChatMessage>> _messages = {};
  var _seeded = false;
  var _counter = 0;

  static const welcomeThreadId = 'thread-welcome';

  String _next(String prefix) => '$prefix-${++_counter}';

  void _seed() {
    if (_seeded) return;
    _seeded = true;
    final at = _clock.now().subtract(const Duration(hours: 2));
    _threads[welcomeThreadId] = ChatThread(
      id: welcomeThreadId,
      scope: EntityScope.personal,
      title: 'Gastos com mercado',
      createdAt: at,
      updatedAt: at,
    );
    _messages[welcomeThreadId] = [
      ChatMessage(
        id: 'msg-welcome-1',
        threadId: welcomeThreadId,
        role: ChatRole.user,
        text: 'Quanto gastei com mercado este mês?',
        createdAt: at,
      ),
      ChatMessage(
        id: 'msg-welcome-2',
        threadId: welcomeThreadId,
        role: ChatRole.assistant,
        text:
            r'Você gastou R$ 602,00 com mercado neste mês, 12% a menos que no '
            'mês passado. A maior compra foi no Mercado Bom Preço.',
        createdAt: at,
      ),
    ];
  }

  @override
  Future<Result<List<ChatThread>>> threads() async {
    await Future<void>.delayed(latency);
    _seed();
    return Ok(
      _threads.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
    );
  }

  @override
  Future<Result<ChatThread>> startThread(EntityScope scope) async {
    await Future<void>.delayed(latency);
    _seed();
    final now = _clock.now();
    final thread = ChatThread(
      id: _next('thread'),
      scope: scope,
      createdAt: now,
      updatedAt: now,
    );
    _threads[thread.id] = thread;
    _messages[thread.id] = [];
    return Ok(thread);
  }

  @override
  Future<Result<List<ChatMessage>>> messages(String threadId) async {
    await Future<void>.delayed(latency);
    _seed();
    final found = _messages[threadId];
    if (found == null) return const Err(NotFoundFailure());
    return Ok(List.of(found));
  }

  @override
  Future<Result<List<ChatMessage>>> send(
    String threadId,
    ChatDraft draft,
  ) async {
    await Future<void>.delayed(latency);
    _seed();
    final thread = _threads[threadId];
    if (thread == null) return const Err(NotFoundFailure());
    final now = _clock.now();
    final text = draft.text.trim();
    final user = ChatMessage(
      id: _next('msg'),
      threadId: threadId,
      role: ChatRole.user,
      text: text,
      createdAt: now,
      attachments: [
        for (final file in draft.files)
          ChatAttachment(
            id: _next('att'),
            fileName: file.name,
            mimeType: file.contentType,
            size: file.bytes.length,
          ),
      ],
    );
    final reply = _reply(thread, user, now);
    _messages[threadId]!.addAll([user, reply]);
    _threads[threadId] = ChatThread(
      id: thread.id,
      scope: thread.scope,
      title: thread.title ?? _titleOf(text, draft),
      createdAt: thread.createdAt,
      updatedAt: now,
    );
    return Ok([user, reply]);
  }

  static String _titleOf(String text, ChatDraft draft) {
    if (text.isEmpty) return draft.files.first.name;
    return text.length > 40 ? '${text.substring(0, 40)}...' : text;
  }

  ChatMessage _reply(ChatThread thread, ChatMessage user, DateTime now) {
    final asksToPay = RegExp(
      'pag|pay',
      caseSensitive: false,
    ).hasMatch(user.text);
    final action = switch ((user.attachments.firstOrNull, asksToPay)) {
      (final ChatAttachment file, _) => _action(
        thread,
        ChatTool.createBillFromAttachment,
        ChatActionDetails(fileName: file.fileName),
        now,
      ),
      (null, true) => _action(
        thread,
        ChatTool.payBill,
        ChatActionDetails(
          payee: 'Energia Lumina',
          amount: const Money(28_740),
          dueDate: CalendarDate.brazilToday(now).addDays(4),
        ),
        now,
      ),
      (null, false) => null,
    };
    return ChatMessage(
      id: _next('msg'),
      threadId: thread.id,
      role: ChatRole.assistant,
      text: switch (action?.tool) {
        ChatTool.createBillFromAttachment =>
          'Li o arquivo e encontrei um boleto. Confirme para criar a conta.',
        ChatTool.payBill =>
          'A conta de energia vence em 4 dias. Confirme para pagar agora.',
        _ =>
          r'Neste mês entraram R$ 6.500,00 e saíram R$ 4.120,00. As maiores '
              'categorias foram moradia, mercado e transporte.',
      },
      createdAt: now,
      actions: [?action],
    );
  }

  final Map<String, ChatAction> _actions = {};

  ChatAction _action(
    ChatThread thread,
    ChatTool tool,
    ChatActionDetails details,
    DateTime now,
  ) {
    final entity = switch (thread.scope) {
      EntityScope.personal => EntityKind.personal,
      EntityScope.company => EntityKind.company,
      EntityScope.consolidated => null,
    };
    final action = ChatAction(
      id: _next('action'),
      threadId: thread.id,
      tool: tool,
      status: ChatActionStatus.pending,
      entity: entity,
      needsEntity: entity == null,
      details: details,
      createdAt: now,
    );
    _actions[action.id] = action;
    return action;
  }

  @override
  Future<Result<ChatAction>> confirm(String actionId, {EntityKind? entity}) =>
      _resolve(
        actionId,
        ChatActionStatus.confirmed,
        entity: entity,
        result: const ChatActionResult(billId: 'bill-energy'),
      );

  @override
  Future<Result<ChatAction>> cancel(String actionId) =>
      _resolve(actionId, ChatActionStatus.cancelled);

  Future<Result<ChatAction>> _resolve(
    String actionId,
    ChatActionStatus status, {
    EntityKind? entity,
    ChatActionResult? result,
  }) async {
    await Future<void>.delayed(latency);
    final action = _actions[actionId];
    if (action == null) return const Err(NotFoundFailure());
    if (!action.isPending) return Ok(action);
    if (action.needsEntity && entity == null && result != null) {
      return const Err(ValidationFailure('Escolha PF ou PJ.'));
    }
    final resolved = ChatAction(
      id: action.id,
      threadId: action.threadId,
      tool: action.tool,
      status: status,
      entity: entity ?? action.entity,
      needsEntity: action.needsEntity,
      details: action.details,
      result: result,
      createdAt: action.createdAt,
    );
    _actions[actionId] = resolved;
    final messages = _messages[action.threadId]!;
    for (final (index, message) in messages.indexed) {
      messages[index] = message.withAction(resolved);
    }
    return Ok(resolved);
  }
}
