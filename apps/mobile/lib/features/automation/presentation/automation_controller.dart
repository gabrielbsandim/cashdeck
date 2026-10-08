import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/automation/automation_providers.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AutomationController extends AsyncNotifier<AutomationStatus> {
  @override
  Future<AutomationStatus> build() async {
    final result = await ref.watch(automationRepositoryProvider).status();
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw LoadFailure(failure),
    };
  }

  Future<AppFailure?> setPaused({required bool paused}) async {
    final result = await ref
        .read(setAutomationPausedProvider)
        .call(paused: paused);
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

final automationControllerProvider =
    AsyncNotifierProvider<AutomationController, AutomationStatus>(
      AutomationController.new,
      retry: noRetry,
    );
