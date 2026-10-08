import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/automation/application/automation_use_cases.dart';
import 'package:cashdeck/features/automation/data/api_automation_repository.dart';
import 'package:cashdeck/features/automation/data/fake_automation_repository.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final automationRepositoryProvider = Provider<AutomationRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeAutomationRepository(ref.watch(clockProvider)),
    Backend.api => ApiAutomationRepository(ref.watch(dioProvider)),
  };
});

final setAutomationPausedProvider = Provider<SetAutomationPaused>(
  (ref) => SetAutomationPaused(ref.watch(automationRepositoryProvider)),
);
