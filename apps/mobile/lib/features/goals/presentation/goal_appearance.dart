import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/presentation/goal_labels.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The icons a goal can wear, by the name the server stores.
const Map<String, IconData> goalIcons = {
  'savings': Symbols.savings_rounded,
  'shield': Symbols.shield_rounded,
  'flight': Symbols.flight_rounded,
  'beach': Symbols.beach_access_rounded,
  'home': Symbols.home_rounded,
  'car': Symbols.directions_car_rounded,
  'school': Symbols.school_rounded,
  'devices': Symbols.devices_rounded,
  'health': Symbols.favorite_rounded,
  'pets': Symbols.pets_rounded,
  'child': Symbols.child_care_rounded,
  'celebration': Symbols.celebration_rounded,
};

/// The colours a goal can wear, in the order of the chart series slots, so
/// each one has a light and a dark tone.
const List<String> goalColors = [
  'blue',
  'teal',
  'amber',
  'purple',
  'cyan',
  'red',
];

IconData goalIconOf(String? name) => goalIcons[name] ?? Symbols.flag_rounded;

/// The series slot behind a colour name, or null for an unknown one.
SeriesColors? goalTint(BuildContext context, String? name) {
  final index = goalColors.indexOf(name ?? '');
  if (index < 0) return null;
  return context.charts.at(index);
}

/// The ring colour: the goal's own colour while on track, the status colour
/// once it is done or behind.
Color goalRingColor(BuildContext context, Goal goal) {
  final tint = goalTint(context, goal.color);
  if (goal.status != GoalStatus.onTrack || tint == null) {
    return goalColor(context, goal.status);
  }
  return tint.fill;
}
