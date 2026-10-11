import 'package:cashdeck/core/location/location_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

final class _MockGeolocator extends Mock implements GeolocatorPlatform;

Position _position(double latitude, double longitude) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026, 10, 8),
  accuracy: 20,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  setUpAll(() => registerFallbackValue(const LocationSettings()));

  test('measures the distance along the surface', () {
    const origin = GeoPoint(-10, -50);

    expect(origin.metersTo(origin), 0);
    expect(origin.metersTo(const GeoPoint(-10.01, -50)), closeTo(1112, 1));
    expect(origin, const GeoPoint(-10, -50));
  });

  test('the fake answers what it holds', () async {
    final reader = FakeLocationReader();
    expect(await reader.current(), isNull);

    reader.point = const GeoPoint(1, 2);
    expect(await reader.current(), const GeoPoint(1, 2));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(locationReaderProvider), isA<FakeLocationReader>());
  });

  test('asks once for the permission, then reads a fix', () async {
    final platform = _MockGeolocator();
    when(platform.isLocationServiceEnabled).thenAnswer((_) async => true);
    when(platform.checkPermission)
        .thenAnswer((_) async => LocationPermission.denied);
    when(platform.requestPermission)
        .thenAnswer((_) async => LocationPermission.whileInUse);
    when(
      () => platform.getCurrentPosition(
        locationSettings: any(named: 'locationSettings'),
      ),
    ).thenAnswer((_) async => _position(-10, -50));

    expect(
      await DeviceLocationReader(platform).current(),
      const GeoPoint(-10, -50),
    );

    when(platform.checkPermission)
        .thenAnswer((_) async => LocationPermission.always);
    expect(await DeviceLocationReader(platform).current(), isNotNull);
    verify(platform.requestPermission).called(1);
  });

  test('no service, a refusal or an error is no location', () async {
    final platform = _MockGeolocator();
    when(platform.isLocationServiceEnabled).thenAnswer((_) async => false);
    final reader = DeviceLocationReader(platform);
    expect(await reader.current(), isNull);

    when(platform.isLocationServiceEnabled).thenAnswer((_) async => true);
    when(platform.checkPermission)
        .thenAnswer((_) async => LocationPermission.deniedForever);
    expect(await reader.current(), isNull);

    when(platform.checkPermission)
        .thenAnswer((_) async => LocationPermission.whileInUse);
    when(
      () => platform.getCurrentPosition(
        locationSettings: any(named: 'locationSettings'),
      ),
    ).thenThrow(const LocationServiceDisabledException());
    expect(await reader.current(), isNull);
    expect(DeviceLocationReader(), isA<LocationReader>());
  });
}
