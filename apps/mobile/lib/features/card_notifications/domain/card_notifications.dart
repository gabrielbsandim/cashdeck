import 'package:cashdeck/core/result/result.dart';
import 'package:equatable/equatable.dart';

/// An app that posted a notification on this phone.
final class NotifyingApp extends Equatable {
  const new({required this.package, required this.label});

  final String package;
  final String label;

  @override
  List<Object?> get props => [package, label];
}

/// Where forwarding stands on this phone.
final class CardNotificationStatus extends Equatable {
  const new({
    required this.access,
    required this.enabled,
    required this.packages,
    required this.accountId,
    required this.pending,
    required this.apps,
  });

  static const unsupported = CardNotificationStatus(
    access: false,
    enabled: false,
    packages: {},
    accountId: null,
    pending: 0,
    apps: [],
  );

  /// Whether the user let Cashdeck read notifications in system settings.
  final bool access;
  final bool enabled;
  final Set<String> packages;
  final String? accountId;

  /// Notifications waiting for the network.
  final int pending;
  final List<NotifyingApp> apps;

  @override
  List<Object?> get props => [
    access,
    enabled,
    packages,
    accountId,
    pending,
    apps,
  ];
}

/// What forwarding sends and where; the server and token are the session's.
final class CardNotificationConfig extends Equatable {
  const new({
    required this.enabled,
    required this.packages,
    required this.accountId,
    this.baseUrl,
    this.token,
  });

  static const off = CardNotificationConfig(
    enabled: false,
    packages: {},
    accountId: null,
  );

  final bool enabled;
  final Set<String> packages;
  final String? accountId;
  final String? baseUrl;
  final String? token;

  @override
  List<Object?> get props => [enabled, packages, accountId, baseUrl, token];
}

/// The phone side that reads other apps' notifications, Android only.
abstract interface class CardNotificationBridge {
  bool get supported;

  Future<Result<CardNotificationStatus>> status();

  Future<Result<void>> openAccessSettings();

  Future<Result<CardNotificationStatus>> configure(
    CardNotificationConfig config,
  );
}
