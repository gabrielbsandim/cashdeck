import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/rails/data/fake_rails_repository.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:cashdeck/features/rails/presentation/payment_rails_screen.dart';
import 'package:cashdeck/features/rails/presentation/rail_detail_screen.dart';
import 'package:cashdeck/features/rails/presentation/rail_labels.dart';
import 'package:cashdeck/features/rails/rails_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

final class _FlakyRails implements RailsRepository {
  new()
    : _inner = FakeRailsRepository(FixedClock(testNow), latency: Duration.zero);

  final FakeRailsRepository _inner;
  bool failRails = false;
  bool failAuthorize = false;
  bool failTest = false;
  bool failRemove = false;
  bool failCredentials = false;

  @override
  Future<Result<List<PaymentRail>>> rails(EntityKind owner) async {
    if (failRails) return const Err(NetworkFailure());
    return await _inner.rails(owner);
  }

  @override
  Future<Result<PaymentRail>> authorize(String id) async {
    if (failAuthorize) return const Err(NetworkFailure());
    return await _inner.authorize(id);
  }

  @override
  Future<Result<RailCredentials>> credentials(String id) async {
    if (failCredentials) return const Err(NetworkFailure());
    return await _inner.credentials(id);
  }

  @override
  Future<Result<List<RailCheck>>> test(String id) async {
    if (failTest) return const Err(NetworkFailure());
    return await _inner.test(id);
  }

  @override
  Future<Result<void>> remove(String id) async {
    if (failRemove) return const Err(NetworkFailure());
    return await _inner.remove(id);
  }
}

void main() {
  const pix = PaymentRail(
    id: 'rail',
    kind: RailKind.pixApi,
    owner: EntityKind.personal,
    step: 1,
    institution: 'Banco Exemplo',
    status: RailStatus.needsAuthorization,
  );

  test('only API rails are configurable', () {
    expect(
      {for (final kind in RailKind.values) kind: _rail(kind).configurable},
      {
        RailKind.pixApi: true,
        RailKind.boletoApi: true,
        RailKind.taxApi: true,
        RailKind.reserveFunding: false,
        RailKind.bankApproval: false,
        RailKind.assisted: false,
      },
    );
    expect(pix.withStatus(RailStatus.active).status, RailStatus.active);
    expect(pix.withStatus(RailStatus.active).props, hasLength(6));
  });

  test('credentials and checks compare by value', () {
    const credentials = RailCredentials(
      certificateName: 'cert.pfx',
      certificateValidUntil: CalendarDate(2027, 1, 1),
      apiKeyHint: 'abcd',
      lastTestAt: null,
    );
    const check = RailCheck(kind: RailCheckKind.scope, passed: true);

    expect(credentials.props, hasLength(4));
    expect(check.props, [RailCheckKind.scope, true, null]);
  });

  test('every rail, status and check has a label', () {
    for (final kind in RailKind.values) {
      expect(railName(l10n, kind), isNotEmpty);
      expect(railDetail(l10n, _rail(kind)), isNotEmpty);
    }
    expect(
      railDetail(l10n, _rail(RailKind.bankApproval, RailStatus.unavailable)),
      l10n.railApprovalUnavailable,
    );
    expect(
      [for (final status in RailStatus.values) railStatusOf(l10n, status).$1],
      [
        MoneyTone.paid,
        MoneyTone.pending,
        MoneyTone.neutral,
        MoneyTone.assisted,
      ],
    );
    for (final kind in RailCheckKind.values) {
      expect(railCheckLabel(l10n, kind), isNotEmpty);
    }
  });

  test('the fake keeps rails per entity and refuses unknown ones', () async {
    final repository = FakeRailsRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    T valueOf<T>(Result<T> result) => (result as Ok<T>).value;

    expect(valueOf(await repository.rails(EntityKind.personal)), hasLength(4));
    expect(valueOf(await repository.rails(EntityKind.company)), hasLength(5));
    expect(
      valueOf(await repository.authorize('rail-pj-approval')).status,
      RailStatus.active,
    );
    expect(
      valueOf(await repository.credentials('rail-pf-pix')).certificateName,
      'aurora-pf.pfx',
    );
    expect(
      valueOf(await repository.credentials('rail-pj-pix')).lastTestAt,
      DateTime.utc(2026, 10, 8, 11, 12),
    );
    expect(valueOf(await repository.test('rail-pj-pix')), hasLength(4));
    expect(
      valueOf(await repository.credentials('rail-pj-pix')).lastTestAt,
      testNow,
    );
    expect(await repository.remove('rail-pj-tax'), const Ok<void>(null));
    expect(valueOf(await repository.rails(EntityKind.company)), hasLength(4));

    for (final call in [
      () => repository.authorize('none'),
      () => repository.credentials('none'),
      () => repository.credentials('rail-pf-assisted'),
      () => repository.test('none'),
      () => repository.remove('none'),
    ]) {
      expect(await call(), isA<Err<Object?>>());
    }
  });

  group('the rails screen', () {
    testWidgets('lists each entity and authorizes the pending bank', (
      tester,
    ) async {
      await pumpRoute(tester, AppRoutes.rails);
      expect(find.text(l10n.railsPersonalNote), findsOneWidget);
      expect(find.byKey(PaymentRailsScreen.authorizeKey), findsNothing);

      await tester.tap(
        find.byKey(PaymentRailsScreen.ownerKey(EntityKind.company)),
      );
      await settle(tester);
      expect(find.text(l10n.railsCompanyNote), findsOneWidget);
      expect(
        find.text(l10n.railsAuthorizeBanner('Atlântico PJ')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(PaymentRailsScreen.authorizeKey));
      await settle(tester);
      expect(
        find.text(l10n.railAuthorizedToast('Atlântico PJ')),
        findsOneWidget,
      );
      expect(find.byKey(PaymentRailsScreen.authorizeKey), findsNothing);
    });

    testWidgets('opens on the company when that is the scope', (tester) async {
      final app = await pumpRoute(tester, AppRoutes.more);
      app.read(entityScopeProvider.notifier).select(EntityScope.company);
      app.router.go(AppRoutes.rails);
      await settle(tester);

      expect(find.text(l10n.railsCompanyNote), findsOneWidget);
    });

    testWidgets('a failed authorization or load says why', (tester) async {
      final repository = _FlakyRails()..failAuthorize = true;
      await pumpRoute(
        tester,
        AppRoutes.rails,
        overrides: [railsRepositoryProvider.overrideWithValue(repository)],
      );
      await tester.tap(
        find.byKey(PaymentRailsScreen.ownerKey(EntityKind.company)),
      );
      await settle(tester);
      await tester.tap(find.byKey(PaymentRailsScreen.authorizeKey));
      await settle(tester);
      expect(find.text(l10n.errorNetwork), findsOneWidget);

      repository.failRails = true;
      await tester.tap(
        find.byKey(PaymentRailsScreen.ownerKey(EntityKind.personal)),
      );
      await settle(tester);
      expect(find.byKey(CdErrorState.retryKey), findsOneWidget);

      repository.failRails = false;
      await tester.tap(find.byKey(CdErrorState.retryKey));
      await settle(tester);
      expect(find.text(l10n.railsPersonalNote), findsOneWidget);
    });

    testWidgets('continue leaves the screen', (tester) async {
      final app = await pumpRoute(tester, AppRoutes.more);
      app.router.push(AppRoutes.rails).ignore();
      await settle(tester);

      await tester.tap(find.byKey(PaymentRailsScreen.continueKey));
      await settle(tester);

      expect(app.location, AppRoutes.more);
    });
  });

  group('the rail detail', () {
    testWidgets('tests, explains uploads and removes the rail', (tester) async {
      final app = await pumpRoute(tester, AppRoutes.more);
      app.router.push(AppRoutes.rails).ignore();
      await settle(tester);
      await tester.tap(find.byKey(PaymentRailsScreen.railKey('rail-pf-pix')));
      await settle(tester);
      expect(app.location, AppRoutes.rail('rail-pf-pix'));
      expect(find.text('aurora-pf.pfx'), findsOneWidget);

      await tester.tap(find.byKey(RailDetailScreen.testKey));
      await settle(tester);
      expect(find.text(l10n.railCheckPayer), findsOneWidget);
      expect(find.text(l10n.millis(210)), findsOneWidget);
      expect(find.text('-'), findsOneWidget);

      await tester.tap(find.byKey(RailDetailScreen.replaceKey));
      await settle(tester);
      expect(find.text(l10n.filePickerSoon), findsOneWidget);
      await waitForToast(tester);
      await tester.tap(find.text('.crt'));
      await settle(tester);
      await waitForToast(tester);
      await tester.tap(find.text('.key'));
      await settle(tester);
      await waitForToast(tester);

      await tester.tap(find.byKey(RailDetailScreen.removeKey));
      await settle(tester);
      expect(find.text(l10n.railRemovedToast), findsOneWidget);
      expect(app.location, AppRoutes.rails);
      expect(
        find.byKey(PaymentRailsScreen.railKey('rail-pf-pix')),
        findsNothing,
      );
    });

    testWidgets('a deep link without the rail still loads', (tester) async {
      await pumpRoute(tester, AppRoutes.rail('rail-pj-boleto'));

      expect(find.text(l10n.railDetailTitle), findsOneWidget);
      expect(find.text('aurora-pj.pfx'), findsOneWidget);
    });

    testWidgets('failures keep the rail and say why', (tester) async {
      final repository = _FlakyRails()
        ..failCredentials = true
        ..failTest = true
        ..failRemove = true;
      await pumpRoute(
        tester,
        AppRoutes.rail('rail-pf-pix'),
        overrides: [railsRepositoryProvider.overrideWithValue(repository)],
      );
      expect(find.text(l10n.errorNetwork), findsOneWidget);

      repository.failCredentials = false;
      await tester.tap(find.byKey(CdErrorState.retryKey));
      await settle(tester);
      await tester.tap(find.byKey(RailDetailScreen.testKey));
      await settle(tester);
      expect(find.text(l10n.railCheckPayer), findsNothing);

      await tester.tap(find.byKey(RailDetailScreen.removeKey));
      await settle(tester);
      expect(find.text(l10n.errorNetwork), findsOneWidget);
      expect(find.byType(RailDetailScreen), findsOneWidget);
    });
  });
}

PaymentRail _rail(RailKind kind, [RailStatus status = RailStatus.active]) =>
    PaymentRail(
      id: kind.name,
      kind: kind,
      owner: EntityKind.company,
      step: 1,
      institution: 'Banco Exemplo',
      status: status,
    );
