import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';

/// A small inbox for the fake backend, dated from its clock.
final class FakeAlertsRepository implements AlertsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 200)})
    : _alerts = _seed(_clock.now());

  final Clock _clock;
  final Duration latency;
  final List<AppAlert> _alerts;
  final Set<AlertKind> _muted = {};
  final List<String> devices = [];
  final Map<String, String> locales = {};

  static List<AppAlert> _seed(DateTime now) => [
    AppAlert(
      id: 'alert-due',
      kind: AlertKind.billDueSoon,
      title: 'Conta vence amanhã',
      body: r'Energia · R$ 184,90 ainda não foi paga.',
      createdAt: now.subtract(const Duration(hours: 1)),
      billId: 'bill-energy',
    ),
    AppAlert(
      id: 'alert-assisted',
      kind: AlertKind.paymentAssisted,
      title: 'Pague manualmente',
      body: r'Internet · R$ 99,90: use o Pix copia e cola no app do banco.',
      createdAt: now.subtract(const Duration(hours: 5)),
      billId: 'bill-internet',
      data: const {'hasPixCode': 'true', 'method': 'PIX'},
    ),
    AppAlert(
      id: 'alert-paid',
      kind: AlertKind.paymentPaid,
      title: 'Conta paga',
      body: r'Aluguel · R$ 2.400,00 foi paga.',
      createdAt: now.subtract(const Duration(days: 1)),
      billId: 'bill-rent',
      readAt: now.subtract(const Duration(hours: 20)),
    ),
  ];

  Future<Result<T>> _settle<T>(T value) async {
    await Future<void>.delayed(latency);
    return Ok(value);
  }

  Map<AlertKind, bool> get _settings => {
    for (final kind in AlertKind.mutable) kind: _muted.contains(kind),
  };

  @override
  Future<Result<AlertPage>> list({String? cursor}) =>
      _settle(AlertPage(items: List.unmodifiable(_alerts)));

  @override
  Future<Result<int>> unreadCount() =>
      _settle(_alerts.where((alert) => alert.unread).length);

  @override
  Future<Result<AppAlert>> markRead(String id) async {
    final index = _alerts.indexWhere((alert) => alert.id == id);
    if (index < 0) {
      await Future<void>.delayed(latency);
      return const Err(NotFoundFailure());
    }
    _alerts[index] = _alerts[index].read(_clock.now());
    return await _settle(_alerts[index]);
  }

  @override
  Future<Result<int>> markAllRead() {
    final unread = _alerts.where((alert) => alert.unread).length;
    for (final (index, alert) in _alerts.indexed) {
      _alerts[index] = alert.read(_clock.now());
    }
    return _settle(unread);
  }

  @override
  Future<Result<Map<AlertKind, bool>>> settings() => _settle(_settings);

  @override
  Future<Result<Map<AlertKind, bool>>> setMuted(
    AlertKind kind, {
    required bool muted,
  }) {
    if (muted) {
      _muted.add(kind);
    } else {
      _muted.remove(kind);
    }
    return _settle(_settings);
  }

  @override
  Future<Result<void>> registerDevice(
    String token,
    String platform, {
    required String locale,
  }) {
    devices.add('$platform:$token');
    locales[token] = locale;
    return _settle(null);
  }

  @override
  Future<Result<void>> removeDevice(String token) {
    devices.removeWhere((device) => device.endsWith(':$token'));
    return _settle(null);
  }
}
