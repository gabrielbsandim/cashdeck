import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small, non-secret settings kept on the device between launches.
abstract interface class KeyValueStore {
  String? getString(String key);

  bool? getBool(String key);

  Future<void> setString(String key, String value);

  Future<void> setBool(String key, {required bool value});
}

final class InMemoryKeyValueStore implements KeyValueStore {
  new([Map<String, Object>? values]) : _values = {...?values};

  final Map<String, Object> _values;

  @override
  String? getString(String key) => switch (_values[key]) {
    final String value => value,
    _ => null,
  };

  @override
  bool? getBool(String key) => switch (_values[key]) {
    final bool value => value,
    _ => null,
  };

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<void> setBool(String key, {required bool value}) async =>
      _values[key] = value;
}

final class SharedPreferencesStore implements KeyValueStore {
  const new(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  bool? getBool(String key) => _preferences.getBool(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> setBool(String key, {required bool value}) =>
      _preferences.setBool(key, value);
}

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => InMemoryKeyValueStore(),
);
