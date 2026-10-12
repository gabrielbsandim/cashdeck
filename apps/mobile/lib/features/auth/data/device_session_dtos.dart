import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/auth/domain/device_session.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';

const Map<String, SessionPlatform> _platforms = {
  'ANDROID': SessionPlatform.android,
  'IOS': SessionPlatform.ios,
  'WEB': SessionPlatform.web,
};

String sessionPlatformToJson(SessionPlatform platform) => switch (platform) {
  SessionPlatform.android => 'ANDROID',
  SessionPlatform.ios => 'IOS',
  SessionPlatform.web => 'WEB',
};

JsonMap deviceIdentityToJson(DeviceIdentity device) => {
  'deviceName': device.name,
  'platform': sessionPlatformToJson(device.platform),
};

DeviceSession deviceSessionFromJson(JsonMap json) => DeviceSession(
  id: readString(json, 'id'),
  deviceName: readString(json, 'deviceName'),
  platform: readEnum(json, 'platform', _platforms),
  createdAt: readDateTime(json, 'createdAt'),
  lastUsedAt: readDateTime(json, 'lastUsedAt'),
  current: readBool(json, 'current'),
);
