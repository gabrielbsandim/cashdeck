import 'package:cashdeck/core/location/geocoder.dart';
import 'package:cashdeck/core/location/location_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

void main() {
  const point = GeoPoint(-10, -50);

  test('the fake answers what it holds', () async {
    final geocoder = FakeGeocoder();
    expect(await geocoder.addressOf(point), isNull);
    expect(await geocoder.pointOf('Rua A, 1'), isNull);

    geocoder
      ..address = 'Rua A, 1'
      ..point = point;
    expect(await geocoder.addressOf(point), 'Rua A, 1');
    expect(await geocoder.pointOf('Rua B, 2'), point);
    expect(geocoder.searched, ['Rua A, 1', 'Rua B, 2']);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(geocoderProvider), isA<FakeGeocoder>());
  });

  test('keeps the street, number and neighborhood', () {
    expect(
      DeviceGeocoder.format(
        const Placemark(
          thoroughfare: 'Rua das Flores',
          subThoroughfare: '10',
          subLocality: 'Centro',
          street: 'Rua das Flores, 10 - Centro, Cidade - UF, 00000-000',
        ),
      ),
      'Rua das Flores, 10, Centro',
    );
    expect(
      DeviceGeocoder.format(const Placemark(subLocality: ' Centro ')),
      'Centro',
    );
    expect(
      DeviceGeocoder.format(const Placemark(street: 'Linha 1', name: '')),
      'Linha 1',
    );
    expect(DeviceGeocoder.format(const Placemark(street: ' ')), isNull);
  });

  test('reads the first place that has an address', () async {
    final asked = <(double, double)>[];
    final geocoder = DeviceGeocoder(
      placemarks: (latitude, longitude) async {
        asked.add((latitude, longitude));
        return const [Placemark(), Placemark(thoroughfare: 'Rua B')];
      },
    );

    expect(await geocoder.addressOf(point), 'Rua B');
    expect(asked, [(-10.0, -50.0)]);
  });

  test('finds the first point for an address', () async {
    final asked = <String>[];
    final geocoder = DeviceGeocoder(
      locations: (address) async {
        asked.add(address);
        return const [
          Location(latitude: -10, longitude: -50),
          Location(latitude: 1, longitude: 2),
        ];
      },
    );

    expect(await geocoder.pointOf('Rua A, 1, Cidade'), point);
    expect(asked, ['Rua A, 1, Cidade']);
  });

  test('nothing found or an error is no answer', () async {
    final empty = DeviceGeocoder(
      placemarks: (_, _) async => const [],
      locations: (_) async => const [],
    );
    expect(await empty.addressOf(point), isNull);
    expect(await empty.pointOf('Rua A'), isNull);

    final offline = DeviceGeocoder(
      placemarks: (_, _) async => throw Exception('offline'),
      locations: (_) async => throw Exception('offline'),
    );
    expect(await offline.addressOf(point), isNull);
    expect(await offline.pointOf('Rua A'), isNull);
    expect(DeviceGeocoder(), isA<Geocoder>());
  });
}
