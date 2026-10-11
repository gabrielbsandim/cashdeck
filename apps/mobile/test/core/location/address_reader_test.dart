import 'package:cashdeck/core/location/address_reader.dart';
import 'package:cashdeck/core/location/location_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';

void main() {
  const point = GeoPoint(-10, -50);

  test('the fake answers what it holds', () async {
    final reader = FakeAddressReader();
    expect(await reader.addressOf(point), isNull);

    reader.address = 'Rua A, 1';
    expect(await reader.addressOf(point), 'Rua A, 1');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(addressReaderProvider), isA<FakeAddressReader>());
  });

  test('keeps the street, number and neighborhood', () {
    expect(
      DeviceAddressReader.format(
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
      DeviceAddressReader.format(const Placemark(subLocality: ' Centro ')),
      'Centro',
    );
    expect(
      DeviceAddressReader.format(const Placemark(street: 'Linha 1', name: '')),
      'Linha 1',
    );
    expect(DeviceAddressReader.format(const Placemark(street: ' ')), isNull);
  });

  test('reads the first place that has an address', () async {
    final asked = <(double, double)>[];
    final reader = DeviceAddressReader((latitude, longitude) async {
      asked.add((latitude, longitude));
      return const [Placemark(), Placemark(thoroughfare: 'Rua B')];
    });

    expect(await reader.addressOf(point), 'Rua B');
    expect(asked, [(-10.0, -50.0)]);
  });

  test('nothing found or an error is no address', () async {
    expect(
      await DeviceAddressReader((_, _) async => const []).addressOf(point),
      isNull,
    );
    expect(
      await DeviceAddressReader((_, _) async => throw Exception('offline'))
          .addressOf(point),
      isNull,
    );
    expect(DeviceAddressReader(), isA<AddressReader>());
  });
}
