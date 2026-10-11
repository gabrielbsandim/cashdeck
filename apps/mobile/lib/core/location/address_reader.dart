import 'dart:async';

import 'package:cashdeck/core/location/location_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

/// A short street address for a point; null when the lookup fails.
abstract interface class AddressReader {
  Future<String?> addressOf(GeoPoint point);
}

final class FakeAddressReader implements AddressReader {
  new([this.address]);

  String? address;

  @override
  Future<String?> addressOf(GeoPoint point) async => address;
}

typedef PlacemarkLookup = Future<List<Placemark>> Function(
  double latitude,
  double longitude,
);

final class DeviceAddressReader implements AddressReader {
  new([PlacemarkLookup? lookup]) : _lookup = lookup ?? _platformLookup;

  static Future<List<Placemark>> _platformLookup(double lat, double lng) =>
      Geocoding().placemarkFromCoordinates(lat, lng);

  static const timeLimit = Duration(seconds: 10);

  final PlacemarkLookup _lookup;

  @override
  Future<String?> addressOf(GeoPoint point) async {
    try {
      final places = await _lookup(
        point.latitude,
        point.longitude,
      ).timeout(timeLimit);
      return places.map(format).nonNulls.firstOrNull;
    } on Exception {
      return null;
    }
  }

  /// Street, number and neighborhood; the full line Android gives in
  /// `street` carries city, state and postcode, too long for a row.
  static String? format(Placemark place) {
    final street = _filled([place.thoroughfare, place.subThoroughfare]);
    final parts = _filled([street, place.subLocality]);
    return parts ?? _filled([place.street]);
  }

  static String? _filled(List<String?> parts) {
    final kept = parts.nonNulls.map((p) => p.trim()).where((p) => p.isNotEmpty);
    return kept.isEmpty ? null : kept.join(', ');
  }
}

final addressReaderProvider = Provider<AddressReader>(
  (ref) => FakeAddressReader(),
);
