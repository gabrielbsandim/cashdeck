import 'dart:convert';

import 'package:cashdeck/core/location/location_reader.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:flutter_riverpod/misc.dart';

/// A fictional home and a point about 11 km south of it.
const homePoint = GeoPoint(-10, -50);
const awayPoint = GeoPoint(-10.1, -50);

/// One saved zone around [homePoint], with the phone at [at].
List<Override> safeModeOverrides({GeoPoint? at = awayPoint}) => [
  keyValueStoreProvider.overrideWithValue(
    InMemoryKeyValueStore({
      SafeModeController.zonesKey: jsonEncode([
        const SafeZone(homePoint).toJson(),
      ]),
    }),
  ),
  locationReaderProvider.overrideWithValue(FakeLocationReader(at)),
];
