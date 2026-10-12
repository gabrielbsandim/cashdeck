import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:equatable/equatable.dart';

/// Whether the home screen widget may show amounts. Privacy mode always masks
/// them; otherwise the user's [choice] decides, and until there is one a
/// saved safe zone masks them, since the home screen cannot tell where the
/// phone is.
bool widgetShowsAmounts({
  required bool privacyMode,
  required bool hasSafeZone,
  bool? choice,
}) {
  if (privacyMode) return false;
  return choice ?? !hasSafeZone;
}

/// What a background refresh reads from the app's saved settings.
final class WidgetSettings extends Equatable {
  const new({
    this.privacyMode = false,
    this.hasSafeZone = false,
    this.choice,
    this.scope = EntityScope.personal,
  });

  final bool privacyMode;
  final bool hasSafeZone;

  /// "Mostrar valores no widget" as the user set it; null until they do.
  final bool? choice;

  /// The entity the app was left on, which Início also feeds the widget.
  final EntityScope scope;

  bool get showsAmounts => widgetShowsAmounts(
    privacyMode: privacyMode,
    hasSafeZone: hasSafeZone,
    choice: choice,
  );

  @override
  List<Object?> get props => [privacyMode, hasSafeZone, choice, scope];
}
