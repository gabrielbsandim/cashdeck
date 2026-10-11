import 'dart:convert';

import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/location/geocoder.dart';
import 'package:cashdeck/core/location/location_reader.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/safe_mode_support.dart';

void main() {
  late InMemoryKeyValueStore store;
  late FakeLocationReader reader;
  late FakeGeocoder geocoder;
  late FixedClock clock;

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        locationReaderProvider.overrideWithValue(reader),
        geocoderProvider.overrideWithValue(geocoder),
        clockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    store = InMemoryKeyValueStore();
    reader = FakeLocationReader(homePoint);
    geocoder = FakeGeocoder();
    clock = FixedClock(DateTime.utc(2026, 10, 8, 15));
  });

  test('is off with no zone, and a check changes nothing', () async {
    final app = container();

    await app.read(safeModeProvider.notifier).check();

    expect(app.read(safeModeProvider), const SafeModeState());
    expect(app.read(safeModeLimitedProvider), isFalse);
  });

  test('saves the current place and keeps it between launches', () async {
    final app = container();
    final mode = app.read(safeModeProvider.notifier);

    expect(await mode.addCurrentLocation(), SafeZoneChange.saved);
    expect(app.read(safeModeProvider).zones, [const SafeZone(homePoint)]);
    expect(app.read(safeModeProvider).status, ZoneStatus.inside);
    expect(app.read(safeModeLimitedProvider), isFalse);

    final relaunched = container();
    expect(relaunched.read(safeModeProvider).zones, [
      const SafeZone(homePoint),
    ]);
    expect(relaunched.read(safeModeLimitedProvider), isTrue);
    await relaunched.read(safeModeProvider.notifier).check();
    expect(relaunched.read(safeModeLimitedProvider), isFalse);
  });

  test('away or without a fix the app is limited and zones stay', () async {
    final app = container();
    final mode = app.read(safeModeProvider.notifier);
    await mode.addCurrentLocation();

    reader.point = awayPoint;
    await mode.check();
    expect(app.read(safeModeProvider).status, ZoneStatus.outside);
    expect(app.read(safeModeLimitedProvider), isTrue);
    expect(app.read(hideAmountsProvider), isTrue);
    expect(await mode.addCurrentLocation(), SafeZoneChange.limited);
    expect(
      await mode.removeZone(const SafeZone(homePoint)),
      SafeZoneChange.limited,
    );

    reader.point = null;
    await mode.check();
    expect(app.read(safeModeLimitedProvider), isTrue);
    expect(app.read(safeModeProvider).zones, hasLength(1));
  });

  test('a release opens the app for an hour', () async {
    final app = container();
    final mode = app.read(safeModeProvider.notifier);
    await mode.addCurrentLocation();
    reader.point = awayPoint;
    await mode.check();

    mode.release();
    expect(
      app.read(safeModeProvider).releasedUntil,
      clock.current.add(SafeModeController.releaseWindow),
    );
    expect(app.read(safeModeLimitedProvider), isFalse);

    clock.current = clock.current.add(const Duration(minutes: 59));
    await mode.check();
    expect(app.read(safeModeLimitedProvider), isFalse);

    clock.current = clock.current.add(const Duration(minutes: 1));
    await mode.check();
    expect(app.read(safeModeProvider).releasedUntil, isNull);
    expect(app.read(safeModeLimitedProvider), isTrue);

    mode.release();
    mode.endRelease();
    expect(app.read(safeModeLimitedProvider), isTrue);
  });

  test(
    'a release survives going to the background but not a relaunch',
    () async {
      final app = container();
      final mode = app.read(safeModeProvider.notifier);
      await mode.addCurrentLocation();
      reader.point = awayPoint;
      mode.release();

      await mode.check();
      expect(app.read(safeModeLimitedProvider), isFalse);

      final relaunched = container();
      await relaunched.read(safeModeProvider.notifier).check();
      expect(relaunched.read(safeModeProvider).releasedUntil, isNull);
      expect(relaunched.read(safeModeLimitedProvider), isTrue);
    },
  );

  testWidgets('the release ends on its own while the app stays open', (
    tester,
  ) async {
    store = InMemoryKeyValueStore({
      SafeModeController.zonesKey: jsonEncode([
        const SafeZone(homePoint).toJson(),
      ]),
    });
    final app = container();
    app.read(safeModeProvider.notifier).release();
    expect(app.read(safeModeLimitedProvider), isFalse);

    await tester.pump(SafeModeController.releaseWindow);

    expect(app.read(safeModeLimitedProvider), isTrue);
  });

  test('names a zone by its address and renames it at home', () async {
    geocoder.address = 'Rua A, 1';
    final app = container();
    final mode = app.read(safeModeProvider.notifier);
    await mode.addCurrentLocation();
    const named = SafeZone(homePoint, name: 'Rua A, 1');
    expect(app.read(safeModeProvider).zones, [named]);

    expect(await mode.renameZone(named, 'Casa'), SafeZoneChange.saved);
    expect(container().read(safeModeProvider).zones, [
      const SafeZone(homePoint, name: 'Casa'),
    ]);

    reader.point = awayPoint;
    await mode.check();
    expect(
      await mode.renameZone(app.read(safeModeProvider).zones.single, 'Outro'),
      SafeZoneChange.limited,
    );
    expect(app.read(safeModeProvider).zones.single.name, 'Casa');
  });

  test('saves a typed address and checks where the phone is', () async {
    final app = container();
    final mode = app.read(safeModeProvider.notifier);

    expect(await mode.addAddress('Rua B, 2'), SafeZoneChange.notFound);
    expect(app.read(safeModeProvider).enabled, isFalse);

    geocoder.point = awayPoint;
    expect(await mode.addAddress('Rua B, 2'), SafeZoneChange.saved);
    expect(app.read(safeModeProvider).zones, [
      const SafeZone(awayPoint, name: 'Rua B, 2'),
    ]);
    expect(app.read(safeModeProvider).status, ZoneStatus.outside);
    expect(app.read(safeModeLimitedProvider), isTrue);
    expect(await mode.addAddress('Rua C, 3'), SafeZoneChange.limited);
    expect(geocoder.searched, ['Rua B, 2', 'Rua B, 2']);
  });

  test('removing the last zone turns the mode off', () async {
    final app = container();
    final mode = app.read(safeModeProvider.notifier);
    await mode.addCurrentLocation();

    expect(
      await mode.removeZone(const SafeZone(homePoint)),
      SafeZoneChange.saved,
    );
    expect(app.read(safeModeProvider).enabled, isFalse);
    expect(store.getString(SafeModeController.zonesKey), '[]');
  });

  test('no fix while saving says so', () async {
    reader.point = null;
    final app = container();

    expect(
      await app.read(safeModeProvider.notifier).addCurrentLocation(),
      SafeZoneChange.noLocation,
    );
    expect(app.read(safeModeProvider).enabled, isFalse);
  });

  test('skips what it cannot read back', () {
    for (final raw in ['not json', '{"a":1}', '[1,{"lat":"x"}]']) {
      store = InMemoryKeyValueStore({SafeModeController.zonesKey: raw});
      expect(container().read(safeModeProvider).zones, isEmpty);
    }
    expect(
      SafeZone.fromJson({'lat': 1, 'lng': 2.5, 'radius': 50}),
      const SafeZone(GeoPoint(1, 2.5), radiusMeters: 50),
    );
    expect(
      SafeZone.fromJson({'lat': 1, 'lng': 2, 'radius': 50, 'name': 7}),
      const SafeZone(GeoPoint(1, 2), radiusMeters: 50),
    );
  });

  test('a zone holds what lies inside its radius', () {
    const zone = SafeZone(homePoint);

    expect(zone.contains(homePoint), isTrue);
    expect(zone.contains(const GeoPoint(-10.002, -50)), isTrue);
    expect(zone.contains(awayPoint), isFalse);
  });
}
