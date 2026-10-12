import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

enum GoalStatus { done, onTrack, behind }

/// Where the saved amount comes from: contributions typed in the app, or the
/// balance of the account or investment the goal follows.
enum GoalSource { manual, account, investment }

final class GoalContribution extends Equatable {
  const new({
    required this.id,
    required this.amount,
    required this.on,
    this.note,
  });

  final String id;

  /// Negative when money left the goal.
  final Money amount;
  final CalendarDate on;
  final String? note;

  @override
  List<Object?> get props => [id, amount, on, note];
}

/// A saving goal as the server computed it: progress, pace and projection.
final class Goal extends Equatable {
  const new({
    required this.id,
    required this.name,
    required this.target,
    required this.saved,
    required this.remaining,
    required this.percent,
    required this.status,
    required this.source,
    this.deadline,
    this.requiredMonthly,
    this.monthlyPace,
    this.projectedOn,
    this.accountId,
    this.investmentId,
    this.linkedName,
    this.icon,
    this.color,
    this.archived = false,
    this.contributions = const [],
  });

  final String id;
  final String name;
  final Money target;
  final Money saved;
  final Money remaining;

  /// 0 to 100.
  final int percent;
  final GoalStatus status;
  final GoalSource source;
  final CalendarDate? deadline;

  /// What a month must put in to reach the target by the deadline.
  final Money? requiredMonthly;

  /// What went in per month lately; null while the goal is too new to tell.
  final Money? monthlyPace;

  /// When the target is reached at [monthlyPace].
  final CalendarDate? projectedOn;
  final String? accountId;
  final String? investmentId;

  /// The account or investment the goal follows.
  final String? linkedName;

  /// Names from the app's own icon and colour sets; null keeps the default.
  final String? icon;
  final String? color;
  final bool archived;

  /// Newest first; empty in a list.
  final List<GoalContribution> contributions;

  bool get isDone => status == GoalStatus.done;

  bool get takesContributions => source == GoalSource.manual;

  double get fraction => (percent / 100).clamp(0, 1);

  @override
  List<Object?> get props => [
    id,
    name,
    target,
    saved,
    remaining,
    percent,
    status,
    source,
    deadline,
    requiredMonthly,
    monthlyPace,
    projectedOn,
    accountId,
    investmentId,
    linkedName,
    icon,
    color,
    archived,
    contributions,
  ];
}

/// True when [after] is the change that took the goal to its target, which
/// is when the app celebrates.
bool justReached(Goal? before, Goal after) =>
    after.isDone && before != null && !before.isDone;

enum GoalProblem { nameMissing, targetMissing, deadlinePast }

const goalNameMax = 60;

/// What the goal form holds before it is saved.
final class GoalDraft extends Equatable {
  const new({
    required this.name,
    required this.target,
    this.deadline,
    this.accountId,
    this.investmentId,
    this.icon,
    this.color,
    this.initial = const Money(0),
  });

  final String name;
  final Money target;
  final CalendarDate? deadline;

  /// The account or the investment the goal follows, never both; neither
  /// for a goal that adds up contributions.
  final String? accountId;
  final String? investmentId;
  final String? icon;
  final String? color;

  bool get isManual => accountId == null && investmentId == null;

  /// Already saved, the first contribution of a new manual goal.
  final Money initial;

  /// The first rule the draft breaks on [today], or null when it can be saved.
  GoalProblem? problemOn(CalendarDate today) {
    if (name.trim().isEmpty) return GoalProblem.nameMissing;
    if (target.cents <= 0) return GoalProblem.targetMissing;
    final ends = deadline;
    if (ends != null && ends.isBefore(today)) return GoalProblem.deadlinePast;
    return null;
  }

  @override
  List<Object?> get props => [
    name,
    target,
    deadline,
    accountId,
    investmentId,
    icon,
    color,
    initial,
  ];
}

abstract interface class GoalsRepository {
  /// Active goals, oldest first.
  Future<Result<List<Goal>>> list();

  /// With its contributions.
  Future<Result<Goal>> get(String id);

  Future<Result<Goal>> create(GoalDraft draft);

  Future<Result<Goal>> update(String id, GoalDraft draft);

  Future<Result<Goal>> archive(String id);

  Future<Result<void>> delete(String id);

  /// A negative [amount] takes money out.
  Future<Result<Goal>> contribute(String id, Money amount, {String? note});

  Future<Result<Goal>> removeContribution(String id, String contributionId);
}
