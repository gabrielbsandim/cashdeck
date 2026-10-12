import 'dart:async';

import 'package:cashdeck/core/error/app_failure.dart';
import 'package:flutter/services.dart';

/// The vibrations the app speaks with, so one kind of moment always feels
/// the same. Fire and forget: a device without a motor just stays still.
abstract final class CdHaptics {
  /// A choice changed: a chip, a segment, a scrubbed chart point.
  static void selection() => unawaited(HapticFeedback.selectionClick());

  /// The user committed to moving money or approving something.
  static void confirm() => unawaited(HapticFeedback.mediumImpact());

  /// Something irreversible is about to happen, such as a delete.
  static void warning() => unawaited(HapticFeedback.heavyImpact());

  /// A milestone, such as a goal reaching its target.
  static void celebrate() => unawaited(HapticFeedback.heavyImpact());

  /// The server answered yes.
  static void success() => unawaited(HapticFeedback.lightImpact());

  /// The server answered no, or the device check failed.
  static void error() => unawaited(HapticFeedback.vibrate());

  /// [success] without a failure, [error] with one.
  static void outcome(AppFailure? failure) =>
      failure == null ? success() : error();
}
