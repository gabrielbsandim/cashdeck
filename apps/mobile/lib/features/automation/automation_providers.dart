import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/automation/application/automation_use_cases.dart';
import 'package:cashdeck/features/automation/data/fake_automation_repository.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No kill switch endpoint yet, so both backends read the fake.
final automationRepositoryProvider = Provider<AutomationRepository>(
  (ref) => FakeAutomationRepository(ref.watch(clockProvider)),
);

final setAutomationPausedProvider = Provider<SetAutomationPaused>(
  (ref) => SetAutomationPaused(ref.watch(automationRepositoryProvider)),
);
