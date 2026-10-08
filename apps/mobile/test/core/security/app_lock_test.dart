import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/security/app_lock.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Clock implements Clock {
  DateTime value = DateTime.utc(2026, 10, 8, 15);

  @override
  DateTime now() => value;
}

void main() {
  test('locks after five minutes away, not after a short switch', () {
    final clock = _Clock();
    final container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(clock)],
    );
    addTearDown(container.dispose);
    final lock = container.read(appLockProvider.notifier);
    expect(container.read(appLockProvider), isFalse);

    lock.shown();
    expect(container.read(appLockProvider), isFalse);

    lock.hidden();
    clock.value = clock.value.add(const Duration(minutes: 4));
    lock.shown();
    expect(container.read(appLockProvider), isFalse);

    lock.hidden();
    clock.value = clock.value.add(AppLockController.idleLimit);
    lock.shown();
    expect(container.read(appLockProvider), isTrue);

    lock.unlock();
    expect(container.read(appLockProvider), isFalse);
    lock.lock();
    expect(container.read(appLockProvider), isTrue);
  });

  test('never locks a device that is signed out', () {
    final clock = _Clock();
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock),
        initialCredentialsProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    final lock = container.read(appLockProvider.notifier)..hidden();
    clock.value = clock.value.add(const Duration(hours: 1));
    lock.shown();

    expect(container.read(appLockProvider), isFalse);
  });
}
