import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/chat/data/chat_dtos.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:dio/dio.dart';

final class ApiChatRepository implements ChatRepository {
  const new(this._dio);

  final Dio _dio;

  static const threadsPath = '/api/v1/chat/threads';
  static const actionsPath = '/api/v1/chat/actions';

  /// A turn runs the model and its tools for up to a minute on the server.
  static const answerTimeout = Duration(seconds: 90);

  static String messagesPath(String threadId) =>
      '$threadsPath/${Uri.encodeComponent(threadId)}/messages';

  /// Every page of a cursor list, in the order the server sends it.
  Future<List<JsonMap>> _all(String path) async {
    final items = <JsonMap>[];
    String? cursor;
    do {
      final response = await _dio.get<Object?>(
        path,
        queryParameters: {'limit': 100, 'cursor': ?cursor},
      );
      final body = asJsonMap(response.data);
      items.addAll(asJsonMapList(unwrapData(body)));
      cursor = readOptionalString(body, 'nextCursor');
    } while (cursor != null);
    return items;
  }

  @override
  Future<Result<List<ChatThread>>> threads() => guardRequest(
    () async => (await _all(threadsPath)).map(threadFromJson).toList(),
  );

  @override
  Future<Result<ChatThread>> startThread(EntityScope scope) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          threadsPath,
          data: {'scope': scopeToJson(scope)},
        );
        return threadFromJson(asJsonMap(unwrapData(response.data)));
      });

  @override
  Future<Result<List<ChatMessage>>> messages(String threadId) => guardRequest(
    () async =>
        (await _all(messagesPath(threadId))).map(messageFromJson).toList(),
  );

  @override
  Future<Result<List<ChatMessage>>> send(
    String threadId,
    ChatDraft draft, {
    String? clientId,
  }) => _answer(messagesPath(threadId), draftToJson(draft, clientId: clientId));

  @override
  Future<Result<List<ChatMessage>>> regenerate(
    String threadId,
    String messageId, {
    String? text,
  }) => _answer(
    '${messagesPath(threadId)}/${Uri.encodeComponent(messageId)}/regenerate',
    regenerateToJson(text),
  );

  Future<Result<List<ChatMessage>>> _answer(String path, JsonMap body) =>
      guardRequest(() async {
        final response = await _dio.post<Object?>(
          path,
          data: body,
          options: Options(receiveTimeout: answerTimeout),
        );
        final data = asJsonMap(unwrapData(response.data));
        return readMapList(data, 'messages').map(messageFromJson).toList();
      });

  @override
  Future<Result<ChatAction>> confirm(String actionId, {EntityKind? entity}) =>
      _resolve(actionId, 'confirm', {
        if (entity != null) 'entity': entityKindToJson(entity),
      });

  @override
  Future<Result<ChatAction>> cancel(String actionId) =>
      _resolve(actionId, 'cancel', const {});

  Future<Result<ChatAction>> _resolve(
    String actionId,
    String verb,
    JsonMap body,
  ) => guardRequest(() async {
    final response = await _dio.post<Object?>(
      '$actionsPath/${Uri.encodeComponent(actionId)}/$verb',
      data: body,
    );
    return actionFromJson(asJsonMap(unwrapData(response.data)));
  });
}
