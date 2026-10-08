import 'package:cashdeck/core/result/result.dart';
import 'package:equatable/equatable.dart';

/// The kill switch: while paused, no rail pays anything on its own.
final class AutomationStatus extends Equatable {
  const new({this.pausedSince});

  final DateTime? pausedSince;

  bool get paused => pausedSince != null;

  @override
  List<Object?> get props => [pausedSince];
}

abstract interface class AutomationRepository {
  Future<Result<AutomationStatus>> status();

  Future<Result<AutomationStatus>> pause();

  Future<Result<AutomationStatus>> resume();
}
