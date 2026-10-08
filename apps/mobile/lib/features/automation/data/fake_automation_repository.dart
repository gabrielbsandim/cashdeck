import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';

final class FakeAutomationRepository implements AutomationRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 200)});

  final Clock _clock;
  final Duration latency;
  var _status = const AutomationStatus();

  Future<Result<AutomationStatus>> _settle(AutomationStatus next) async {
    await Future<void>.delayed(latency);
    _status = next;
    return Ok(next);
  }

  @override
  Future<Result<AutomationStatus>> status() => _settle(_status);

  @override
  Future<Result<AutomationStatus>> pause() =>
      _settle(AutomationStatus(pausedSince: _clock.now()));

  @override
  Future<Result<AutomationStatus>> resume() =>
      _settle(const AutomationStatus());
}
