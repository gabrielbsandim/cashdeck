import 'dart:async';

import 'package:cashdeck/core/location/location_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

/// Turns a point into a short street address and an address into a point;
/// null when the lookup fails.
abstract interface class Geocoder {
  Future<String?> addressOf(GeoPoint point);

  Future<GeoPoint?> pointOf(String address);
}

final class FakeGeocoder implements Geocoder {
  new([this.address, this.point]);

  String? address;
  GeoPoint? point;
  final searched = <String>[];

  @override
  Future<String?> addressOf(GeoPoint point) async => address;

  @override
  Future<GeoPoint?> pointOf(String address) async {
    searched.add(address);
    return point;
  }
}

typedef PlacemarkLookup = Future<List<Placemark>> Function(
  double latitude,
  double longitude,
);

typedef LocationLookup = Future<List<Location>> Function(String address);

final class DeviceGeocoder implements Geocoder {
  new({PlacemarkLookup? placemarks, LocationLookup? locations})
    : _placemarks = placemarks ?? _platformPlacemarks,
      _locations = locations ?? _platformLocations;

  static Future<List<Placemark>> _platformPlacemarks(double lat, double lng) =>
      Geocoding().placemarkFromCoordinates(lat, lng);

  static Future<List<Location>> _platformLocations(String address) =>
      Geocoding().locationFromAddress(address);

  static const timeLimit = Duration(seconds: 10);

  final PlacemarkLookup _placemarks;
  final LocationLookup _locations;

  @override
  Future<String?> addressOf(GeoPoint point) async {
    try {
      final places = await _placemarks(
        point.latitude,
        point.longitude,
      ).timeout(timeLimit);
      return places.map(format).nonNulls.firstOrNull;
    } on Exception {
      return null;
    }
  }

  @override
  Future<GeoPoint?> pointOf(String address) async {
    try {
      final found = await _locations(address).timeout(timeLimit);
      final first = found.firstOrNull;
      return first == null ? null : GeoPoint(first.latitude, first.longitude);
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

final geocoderProvider = Provider<Geocoder>((ref) => FakeGeocoder());
