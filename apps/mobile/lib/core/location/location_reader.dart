import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// A place on Earth, in degrees.
final class GeoPoint extends Equatable {
  const new(this.latitude, this.longitude);

  static const _earthRadiusMeters = 6371000.0;

  final double latitude;
  final double longitude;

  /// The great-circle distance, which is what a radius around home means.
  double metersTo(GeoPoint other) {
    double radians(double degrees) => degrees * math.pi / 180;
    final dLat = radians(other.latitude - latitude);
    final dLon = radians(other.longitude - longitude);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(radians(latitude)) *
            math.cos(radians(other.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * _earthRadiusMeters * math.asin(math.sqrt(a));
  }

  @override
  List<Object?> get props => [latitude, longitude];
}

/// Where the phone is now; null when the location is off, refused or slow.
abstract interface class LocationReader {
  Future<GeoPoint?> current();
}

final class FakeLocationReader implements LocationReader {
  new([this.point]);

  GeoPoint? point;

  @override
  Future<GeoPoint?> current() async => point;
}

final class DeviceLocationReader implements LocationReader {
  new([GeolocatorPlatform? platform])
    : _platform = platform ?? GeolocatorPlatform.instance;

  static const timeLimit = Duration(seconds: 10);

  final GeolocatorPlatform _platform;

  /// Asks for the permission the first time; any refusal or error is no
  /// location, which the safe mode reads as away from home.
  @override
  Future<GeoPoint?> current() async {
    try {
      if (!await _platform.isLocationServiceEnabled()) return null;
      var permission = await _platform.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _platform.requestPermission();
      }
      final granted =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
      if (!granted) return null;
      final position = await _platform.getCurrentPosition(
        locationSettings: const LocationSettings(timeLimit: timeLimit),
      );
      return GeoPoint(position.latitude, position.longitude);
    } on Exception {
      return null;
    }
  }
}

final locationReaderProvider = Provider<LocationReader>(
  (ref) => FakeLocationReader(),
);
