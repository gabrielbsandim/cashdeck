import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/domain/device_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceSessionsController extends AsyncNotifier<List<DeviceSession>> {
  @override
  Future<List<DeviceSession>> build() async =>
      (await ref.watch(listDeviceSessionsProvider).call()).orThrow;

  /// Signs [session] out, or this phone when it is the current one; null when
  /// it worked.
  Future<AppFailure?> revoke(DeviceSession session) async {
    if (session.current) {
      await ref.read(signOutProvider).call();
      return null;
    }
    final result = await ref.read(revokeDeviceSessionProvider).call(session.id);
    switch (result) {
      case Ok():
        state = AsyncData([
          for (final kept in state.value ?? const <DeviceSession>[])
            if (kept.id != session.id) kept,
        ]);
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

final AsyncNotifierProvider<DeviceSessionsController, List<DeviceSession>>
deviceSessionsControllerProvider =
    AsyncNotifierProvider.autoDispose<
      DeviceSessionsController,
      List<DeviceSession>
    >(DeviceSessionsController.new, retry: noRetry);
