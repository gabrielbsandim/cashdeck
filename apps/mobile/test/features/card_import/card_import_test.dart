import 'dart:typed_data';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/card_import/card_import_providers.dart';
import 'package:cashdeck/features/card_import/data/fake_card_import_repository.dart';
import 'package:cashdeck/features/card_import/domain/card_statement.dart';
import 'package:cashdeck/features/card_import/presentation/manual_card_bill_import_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

final class _Flaky implements CardImportRepository {
  final _inner = FakeCardImportRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  );
  bool failStatement = true;
  AppFailure failure = const NetworkFailure();

  @override
  Future<Result<CardStatement>> statement() async {
    if (failStatement) return Err(failure);
    return await _inner.statement();
  }

  @override
  Future<Result<CardStatement>> upload(LocalFile file, EntityKind owner) async {
    failStatement = false;
    return await _inner.upload(file, owner);
  }

  @override
  Future<Result<String>> createBill(
    CardStatement statement,
    Set<String> lineIds,
  ) async => const Err(NetworkFailure());
}

void main() {
  final repository = FakeCardImportRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  );

  Future<CardStatement> statement() async =>
      (await repository.statement() as Ok<CardStatement>).value;

  test('the totals convert, add the IOF and follow the selection', () async {
    final card = await statement();
    final all = StatementTotals.of(card, {for (final l in card.lines) l.id});
    final some = StatementTotals.of(card, const {'line-hotel', 'line-metro'});

    expect(card.rate, 54_900);
    expect(card.iofBps, 350);
    expect(card.closing, const CalendarDate(2026, 10, 5));
    expect(all.foreign, const Money(46_340, currency: 'USD'));
    expect(all.subtotal, const Money(254_407));
    expect(all.iof, const Money(8_904));
    expect(all.total, const Money(263_311));
    expect(some.total, const Money(252_856));
    expect(all.props, hasLength(3));
    expect(card.props, hasLength(8));
    expect(card.lines.last.props, hasLength(5));
  });

  test('an empty statement totals zero in reais', () {
    const empty = CardStatement(
      card: 'Cartão',
      issuer: 'Banco',
      closing: testToday,
      due: testToday,
      rate: 10_000,
      iofBps: 0,
      lines: [],
    );

    expect(StatementTotals.of(empty, const {}).total, const Money(0));
  });

  test('the fake creates a bill only for a positive total', () async {
    final card = await statement();

    expect(
      await repository.createBill(card, const {}),
      const Err<String>(ValidationFailure('total')),
    );
    expect(
      await repository.createBill(card, {card.lines.first.id}),
      const Ok('bill-card-viagem'),
    );
  });

  test('the provider reads the fake', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(cardImportRepositoryProvider),
      isA<FakeCardImportRepository>(),
    );
  });

  testWidgets('reviews the lines and creates the bill', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.settings);
    app.router.push(AppRoutes.cardImport).ignore();
    await settle(tester);

    expect(find.text(l10n.cardImportTitle('Cartão Viagem')), findsOneWidget);
    expect(find.text('5,4900'), findsOneWidget);
    expect(find.text('3,5%'), findsOneWidget);
    expect(find.text(l10n.cardLineReview), findsOneWidget);
    expect(find.text(MoneyFormat.format(const Money(263_311))), findsOneWidget);
    expect(
      find.text(
        l10n.cardSubtotal(
          MoneyFormat.format(const Money(46_340, currency: 'USD')),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ManualCardBillImportScreen.lineKey('line-cafe')),
    );
    await settle(tester);
    expect(find.text(MoneyFormat.format(const Money(252_856))), findsOneWidget);
    await tester.tap(
      find.byKey(ManualCardBillImportScreen.lineKey('line-cafe')),
    );
    await settle(tester);
    expect(find.text(MoneyFormat.format(const Money(263_311))), findsOneWidget);

    await tester.tap(find.byKey(ManualCardBillImportScreen.createKey));
    await settle(tester);
    expect(find.text(l10n.cardBillCreatedToast), findsOneWidget);
    expect(app.location, AppRoutes.settings);
  });

  testWidgets('a failed load or creation says why', (tester) async {
    final flaky = _Flaky();
    await pumpRoute(
      tester,
      AppRoutes.cardImport,
      overrides: [cardImportRepositoryProvider.overrideWithValue(flaky)],
    );
    expect(find.text(l10n.cardImportShortTitle), findsOneWidget);
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    flaky.failStatement = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    await tester.tap(find.byKey(ManualCardBillImportScreen.createKey));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.byType(ManualCardBillImportScreen), findsOneWidget);
  });

  testWidgets('no statement waiting reads as empty, not as an error', (
    tester,
  ) async {
    final flaky = _Flaky()..failure = const NotFoundFailure();
    await pumpRoute(
      tester,
      AppRoutes.cardImport,
      overrides: [cardImportRepositoryProvider.overrideWithValue(flaky)],
    );

    expect(find.text(l10n.cardImportEmptyTitle), findsOneWidget);
    expect(find.byKey(CdErrorState.retryKey), findsNothing);
  });

  testWidgets('uploads a statement and reviews what was read', (tester) async {
    final flaky = _Flaky()..failure = const NotFoundFailure();
    final chooser = FakeFileChooser(
      LocalFile(name: 'fatura.pdf', bytes: Uint8List(4)),
    );
    await pumpRoute(
      tester,
      AppRoutes.cardImport,
      overrides: [
        cardImportRepositoryProvider.overrideWithValue(flaky),
        fileChooserProvider.overrideWithValue(chooser),
      ],
    );

    await tester.tap(find.text(l10n.cardImportUpload));
    await settle(tester);

    expect(chooser.requests.single, contains('pdf'));
    expect(find.text(l10n.cardImportTitle('Cartão Viagem')), findsOneWidget);
    expect(find.text(l10n.cardImportUploadedToast), findsOneWidget);
    await waitForToast(tester);
  });

  testWidgets('a cancelled pick sends nothing', (tester) async {
    final chooser = FakeFileChooser();
    await pumpRoute(
      tester,
      AppRoutes.cardImport,
      overrides: [fileChooserProvider.overrideWithValue(chooser)],
    );

    await tester.tap(find.byKey(ManualCardBillImportScreen.uploadKey));
    await settle(tester);

    expect(chooser.requests, hasLength(1));
    expect(find.text(l10n.cardImportUploadedToast), findsNothing);
  });

  testWidgets('the close button leaves', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.settings);
    app.router.push(AppRoutes.cardImport).ignore();
    await settle(tester);

    await tester.tap(find.byTooltip('Fechar'));
    await settle(tester);

    expect(app.location, AppRoutes.settings);
  });
}
