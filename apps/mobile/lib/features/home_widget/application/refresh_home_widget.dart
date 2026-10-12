import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/credential_store.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/bills/application/bills_use_cases.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home_widget/domain/home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/domain/widget_settings.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:cashdeck/features/home_widget/domain/widget_sources.dart';
import 'package:cashdeck/features/insights/application/insights_use_cases.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:cashdeck/features/outlook/application/outlook_use_cases.dart';

enum WidgetRefresh {
  /// At least one part loaded and the widget shows it.
  refreshed,

  /// The user keeps amounts off the widget, so nothing was fetched.
  masked,

  /// No session on the device: the widget was emptied.
  signedOut,

  /// The server revoked the session: the widget was emptied.
  unauthorized,

  /// Nothing loaded; the widget keeps its last numbers and their time.
  unreachable,
}

/// Fetches what the widget shows while the app is closed. The session token
/// is read only here and leaves with [WidgetSources.close].
final class RefreshHomeWidget {
  const new({
    required this._credentials,
    required this._open,
    required this._publisher,
    required this._clock,
  });

  final CredentialStore _credentials;
  final WidgetSources Function(ServerCredentials session) _open;
  final HomeWidgetPublisher _publisher;
  final Clock _clock;

  Future<WidgetRefresh> call(WidgetSettings settings) async {
    if (!settings.showsAmounts) {
      await _publisher.publish(
        WidgetSnapshot.from(now: _clock.now(), hide: true),
      );
      return WidgetRefresh.masked;
    }
    final session = await _credentials.read();
    if (session == null) {
      await _publisher.clear();
      return WidgetRefresh.signedOut;
    }
    final sources = _open(session);
    try {
      return await _refresh(sources, settings);
    } finally {
      sources.close();
    }
  }

  Future<WidgetRefresh> _refresh(
    WidgetSources sources,
    WidgetSettings settings,
  ) async {
    final (free, bills, overview) = await (
      LoadSafeToSpend(sources.outlook)(EntityKind.personal),
      ListBills(sources.bills)(settings.scope),
      LoadInsightsOverview(sources.insights)(
        settings.scope,
        InsightPeriod.month,
      ),
    ).wait;
    final results = <Result<Object?>>[free, bills, overview];
    if (results.any(_unauthorized)) {
      await _publisher.clear();
      return WidgetRefresh.unauthorized;
    }
    if (results.every((result) => result is Err)) {
      return WidgetRefresh.unreachable;
    }
    await _publisher.publish(
      WidgetSnapshot.from(
        now: _clock.now(),
        hide: false,
        safeToSpend: _valueOf(free),
        bills: _valueOf(bills)?.bills,
        overview: _valueOf(overview),
      ),
    );
    return WidgetRefresh.refreshed;
  }
}

bool _unauthorized(Result<Object?> result) => switch (result) {
  Err(failure: UnauthorizedFailure()) => true,
  _ => false,
};

T? _valueOf<T>(Result<T> result) => switch (result) {
  Ok(:final value) => value,
  Err() => null,
};
