import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/automation/application/automation_use_cases.dart';
import 'package:cashdeck/features/automation/automation_providers.dart';
import 'package:cashdeck/features/automation/data/fake_automation_repository.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:cashdeck/features/automation/presentation/automation_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/builders.dart';
import '../../support/mocks.dart';

void main() {
  test('pausing records since when, resuming clears it', () async {
    final repository = FakeAutomationRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    final setPaused = SetAutomationPaused(repository);

    expect(await repository.status(), const Ok(AutomationStatus()));
    final paused = await setPaused(paused: true);
    expect(paused, Ok(AutomationStatus(pausedSince: testNow)));
    expect(
      (await repository.status() as Ok<AutomationStatus>).value.paused,
      isTrue,
    );
    expect(await setPaused(paused: false), const Ok(AutomationStatus()));
  });

  test('the controller loads, toggles and reports a failure', () async {
    final repository = MockAutomationRepository();
    when(repository.status)
        .thenAnswer((_) async => const Ok(AutomationStatus()));
    when(repository.pause)
        .thenAnswer((_) async => Ok(AutomationStatus(pausedSince: testNow)));
    when(repository.resume)
        .thenAnswer((_) async => const Err(NetworkFailure()));
    final container = ProviderContainer(
      overrides: [automationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(automationControllerProvider.notifier);
    await container.read(automationControllerProvider.future);

    expect(await controller.setPaused(paused: true), isNull);
    expect(container.read(automationControllerProvider).value?.paused, isTrue);
    expect(await controller.setPaused(paused: false), const NetworkFailure());
    expect(container.read(automationControllerProvider).value?.paused, isTrue);
  });

  test('a failed status load surfaces as an error', () async {
    final repository = MockAutomationRepository();
    when(repository.status).thenAnswer((_) async => const Err(ServerFailure()));
    final container = ProviderContainer(
      overrides: [automationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(automationControllerProvider.future),
      throwsA(anything),
    );
  });

  test('both backends read the fake kill switch', () {
    final container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(FixedClock(testNow))],
    );
    addTearDown(container.dispose);

    expect(
      container.read(automationRepositoryProvider),
      isA<FakeAutomationRepository>(),
    );
    expect(container.read(setAutomationPausedProvider), isNotNull);
  });
}
