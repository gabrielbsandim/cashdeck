import 'dart:async';
import 'dart:convert';

import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/location/location_reader.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A circle around a place the user trusts, such as home.
final class SafeZone extends Equatable {
  const new(this.center, {this.radiusMeters = defaultRadiusMeters});

  /// Wide enough for the drift of a phone fix indoors.
  static const defaultRadiusMeters = 300;

  final GeoPoint center;
  final int radiusMeters;

  bool contains(GeoPoint point) => center.metersTo(point) <= radiusMeters;

  Map<String, Object> toJson() => {
    'lat': center.latitude,
    'lng': center.longitude,
    'radius': radiusMeters,
  };

  static SafeZone? fromJson(Object? json) {
    if (json is! Map) return null;
    final (lat, lng, radius) = (json['lat'], json['lng'], json['radius']);
    if (lat is! num || lng is! num || radius is! int) return null;
    return SafeZone(
      GeoPoint(lat.toDouble(), lng.toDouble()),
      radiusMeters: radius,
    );
  }

  @override
  List<Object?> get props => [center, radiusMeters];
}

enum ZoneStatus { unknown, inside, outside }

/// With no zone the mode is off. With one, the app is limited until a fix
/// puts the phone inside a zone or the user releases it for a while.
final class SafeModeState extends Equatable {
  const new({
    this.zones = const [],
    this.status = ZoneStatus.unknown,
    this.releasedUntil,
  });

  final List<SafeZone> zones;
  final ZoneStatus status;
  final DateTime? releasedUntil;

  bool get enabled => zones.isNotEmpty;

  bool get limited =>
      enabled && status != ZoneStatus.inside && releasedUntil == null;

  SafeModeState copyWith({
    List<SafeZone>? zones,
    ZoneStatus? status,
    DateTime? Function()? releasedUntil,
  }) => SafeModeState(
    zones: zones ?? this.zones,
    status: status ?? this.status,
    releasedUntil: releasedUntil == null ? this.releasedUntil : releasedUntil(),
  );

  @override
  List<Object?> get props => [zones, status, releasedUntil];
}

enum SafeZoneChange { saved, limited, noLocation }

class SafeModeController extends Notifier<SafeModeState> {
  static const zonesKey = 'safe_zones';
  static const releaseWindow = Duration(hours: 1);

  Timer? _expiry;

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  DateTime get _now => ref.read(clockProvider).now();

  @override
  SafeModeState build() {
    ref.onDispose(() => _expiry?.cancel());
    return SafeModeState(zones: _readZones());
  }

  List<SafeZone> _readZones() {
    final raw = _store.getString(zonesKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(SafeZone.fromJson).nonNulls.toList();
    } on FormatException {
      return const [];
    }
  }

  /// Runs at launch and every time the app comes back to the screen.
  Future<void> check() async {
    _dropExpiredRelease();
    if (!state.enabled) return;
    final point = await ref.read(locationReaderProvider).current();
    final inside = point != null && state.zones.any((z) => z.contains(point));
    state = state.copyWith(
      status: inside ? ZoneStatus.inside : ZoneStatus.outside,
    );
  }

  void _dropExpiredRelease() {
    final until = state.releasedUntil;
    if (until == null || _now.isBefore(until)) return;
    endRelease();
  }

  /// The secret gesture already passed the device check; the release ends
  /// by itself so a phone left unlocked does not stay open.
  void release() {
    _expiry?.cancel();
    _expiry = Timer(releaseWindow, endRelease);
    state = state.copyWith(releasedUntil: () => _now.add(releaseWindow));
  }

  void endRelease() {
    _expiry?.cancel();
    _expiry = null;
    state = state.copyWith(releasedUntil: () => null);
  }

  /// Zones change only while the app is not limited, or the limit would be
  /// one tap away from anyone holding the phone.
  Future<SafeZoneChange> addCurrentLocation() async {
    if (state.limited) return SafeZoneChange.limited;
    final point = await ref.read(locationReaderProvider).current();
    if (point == null) return SafeZoneChange.noLocation;
    await _save([...state.zones, SafeZone(point)]);
    state = state.copyWith(status: ZoneStatus.inside);
    return SafeZoneChange.saved;
  }

  Future<SafeZoneChange> removeZone(SafeZone zone) async {
    if (state.limited) return SafeZoneChange.limited;
    await _save([...state.zones]..remove(zone));
    return SafeZoneChange.saved;
  }

  Future<void> _save(List<SafeZone> zones) async {
    state = state.copyWith(zones: List.unmodifiable(zones));
    await _store.setString(
      zonesKey,
      jsonEncode([for (final zone in zones) zone.toJson()]),
    );
  }
}

final safeModeProvider = NotifierProvider<SafeModeController, SafeModeState>(
  SafeModeController.new,
);

/// True while the phone is away from every safe zone: amounts stay hidden,
/// nothing that changes data reaches the server and sensitive screens close.
final safeModeLimitedProvider = Provider<bool>(
  (ref) => ref.watch(safeModeProvider.select((mode) => mode.limited)),
);
