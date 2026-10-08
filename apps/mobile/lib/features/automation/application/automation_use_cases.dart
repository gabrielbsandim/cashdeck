import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';

final class SetAutomationPaused {
  const new(this._repository);

  final AutomationRepository _repository;

  Future<Result<AutomationStatus>> call({required bool paused}) =>
      paused ? _repository.pause() : _repository.resume();
}
