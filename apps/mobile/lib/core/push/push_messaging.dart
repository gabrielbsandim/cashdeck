import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One push as the app sees it, whatever delivered it.
final class PushMessage extends Equatable {
  const new({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, String> data;

  String? get billId => data['billId'];

  @override
  List<Object?> get props => [title, body, data];
}

/// Push delivery behind a port, so the app runs and tests pass without a
/// Firebase project; [start] answers false when push is unavailable.
abstract interface class PushMessaging {
  Future<bool> start();

  Future<String?> token();

  Stream<String> tokenRefreshes();

  /// Pushes that arrive while the app is open.
  Stream<PushMessage> foreground();

  /// Pushes the user tapped while the app ran in the background.
  Stream<PushMessage> opened();

  /// The push that launched the app from a cold start, if any.
  Future<PushMessage?> launchedBy();
}

final class DisabledPushMessaging implements PushMessaging {
  const new();

  @override
  Future<bool> start() async => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> tokenRefreshes() => const Stream.empty();

  @override
  Stream<PushMessage> foreground() => const Stream.empty();

  @override
  Stream<PushMessage> opened() => const Stream.empty();

  @override
  Future<PushMessage?> launchedBy() async => null;
}

final pushMessagingProvider = Provider<PushMessaging>(
  (ref) => const DisabledPushMessaging(),
);
