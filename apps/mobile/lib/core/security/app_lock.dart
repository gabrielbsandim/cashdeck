import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app opens locked; main sets it when a session exists.
final initiallyLockedProvider = Provider<bool>((ref) => false);

/// Locks the app at launch and after five minutes in the background.
class AppLockController extends Notifier<bool> {
  static const idleLimit = Duration(minutes: 5);

  DateTime? _hiddenAt;

  @override
  bool build() => ref.read(initiallyLockedProvider);

  void hidden() => _hiddenAt = ref.read(clockProvider).now();

  void shown() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null || ref.read(serverSessionProvider) == null) return;
    final away = ref.read(clockProvider).now().difference(hiddenAt);
    if (away >= idleLimit) state = true;
  }

  void lock() => state = true;

  void unlock() => state = false;
}

final appLockProvider = NotifierProvider<AppLockController, bool>(
  AppLockController.new,
);
