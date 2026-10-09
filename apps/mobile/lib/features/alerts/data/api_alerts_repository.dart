import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:dio/dio.dart';

AppAlert alertFromJson(JsonMap json) => AppAlert(
  id: readString(json, 'id'),
  kind: AlertKind.fromWire(readString(json, 'type')),
  title: readString(json, 'title'),
  body: readString(json, 'body'),
  createdAt: readDateTime(json, 'createdAt'),
  billId: readOptionalString(json, 'billId'),
  readAt: readOptionalDateTime(json, 'readAt'),
  data: {
    for (final entry in (readOptionalMap(json, 'data') ?? const {}).entries)
      entry.key: '${entry.value}',
  },
);

Map<AlertKind, bool> alertSettingsFromJson(JsonMap json) => {
  for (final row in readMapList(json, 'types'))
    if (AlertKind.fromWire(readString(row, 'type')) case final kind
        when kind != AlertKind.other)
      kind: readBool(row, 'muted'),
};

final class ApiAlertsRepository implements AlertsRepository {
  const new(this._dio);

  final Dio _dio;

  static const path = '/api/v1/alerts';
  static const devicesPath = '/api/v1/devices';

  JsonMap _data(Response<Object?> response) =>
      asJsonMap(unwrapData(response.data));

  @override
  Future<Result<AlertPage>> list({String? cursor}) => guardRequest(() async {
    final response = await _dio.get<Object?>(
      path,
      queryParameters: {'cursor': ?cursor, 'limit': 30},
    );
    final body = asJsonMap(response.data);
    return AlertPage(
      items: asJsonMapList(unwrapData(body)).map(alertFromJson).toList(),
      nextCursor: readOptionalString(body, 'nextCursor'),
    );
  });

  @override
  Future<Result<int>> unreadCount() => guardRequest(
    () async =>
        readInt(_data(await _dio.get<Object?>('$path/unread-count')), 'unread'),
  );

  @override
  Future<Result<AppAlert>> markRead(String id) => guardRequest(
    () async => alertFromJson(
      _data(
        await _dio.post<Object?>(
          '$path/${Uri.encodeComponent(id)}/read',
          data: const <String, Object?>{},
        ),
      ),
    ),
  );

  @override
  Future<Result<int>> markAllRead() => guardRequest(
    () async => readInt(
      _data(
        await _dio.post<Object?>(
          '$path/read-all',
          data: const <String, Object?>{},
        ),
      ),
      'updated',
    ),
  );

  @override
  Future<Result<Map<AlertKind, bool>>> settings() => guardRequest(
    () async =>
        alertSettingsFromJson(_data(await _dio.get<Object?>('$path/settings'))),
  );

  @override
  Future<Result<Map<AlertKind, bool>>> setMuted(
    AlertKind kind, {
    required bool muted,
  }) => guardRequest(
    () async => alertSettingsFromJson(
      _data(
        await _dio.patch<Object?>(
          '$path/settings',
          data: {
            'muted': {kind.wire: muted},
          },
        ),
      ),
    ),
  );

  @override
  Future<Result<void>> registerDevice(String token, String platform) =>
      guardRequest(() async {
        await _dio.post<Object?>(
          devicesPath,
          data: {'token': token, 'platform': platform},
        );
      });
}
