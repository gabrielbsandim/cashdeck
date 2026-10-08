import 'package:cashdeck/core/time/calendar_date.dart';

typedef JsonMap = Map<String, dynamic>;

String readString(JsonMap json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected a string at "$key"', json);
}

String? readOptionalString(JsonMap json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('Expected a string or null at "$key"', json);
}

int readInt(JsonMap json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Expected an integer at "$key"', json);
}

JsonMap readMap(JsonMap json, String key) {
  final value = json[key];
  if (value is JsonMap) return value;
  throw FormatException('Expected an object at "$key"', json);
}

/// A missing key reads as an empty list; any other shape is a format error.
List<JsonMap> readMapList(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is List && value.every((item) => item is JsonMap)) {
    return value.cast<JsonMap>();
  }
  throw FormatException('Expected a list of objects at "$key"', json);
}

List<String> readStringList(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is List && value.every((item) => item is String)) {
    return value.cast<String>();
  }
  throw FormatException('Expected a list of strings at "$key"', json);
}

CalendarDate readDate(JsonMap json, String key) =>
    CalendarDate.parse(readString(json, key));

DateTime readDateTime(JsonMap json, String key) {
  final value = DateTime.tryParse(readString(json, key));
  if (value != null) return value;
  throw FormatException('Expected an ISO 8601 timestamp at "$key"', json);
}

/// Every API response carries its payload in a `data` envelope.
Object? unwrapData(Object? body) {
  if (body is JsonMap && body.containsKey('data')) return body['data'];
  throw FormatException('Expected a data envelope', body);
}

JsonMap asJsonMap(Object? data) {
  if (data is JsonMap) return data;
  throw FormatException('Expected a JSON object', data);
}

List<JsonMap> asJsonMapList(Object? data) {
  if (data is List && data.every((item) => item is JsonMap)) {
    return data.cast<JsonMap>();
  }
  throw FormatException('Expected a list of objects', data);
}
