import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/links/link_opener.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/data/fake_capture_repository.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/capture/domain/scanned_code.dart';
import 'package:cashdeck/features/capture/presentation/capture_sources_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

final class _FlakyCapture implements CaptureRepository {
  final _inner = FakeCaptureRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  );
  bool failSources = true;

  @override
  Future<Result<CaptureSources>> sources() async {
    if (failSources) return const Err(NetworkFailure());
    return await _inner.sources();
  }

  @override
  Future<Result<CaptureSources>> readNow(String mailboxId) async =>
      const Err(NetworkFailure());

  @override
  Future<Result<CaptureSources>> disconnect(String mailboxId) async =>
      const Err(NetworkFailure());

  @override
  Future<Result<CaptureSources>> setDda(EntityKind owner, {required bool on}) =>
      _inner.setDda(owner, on: on);

  @override
  Future<Result<Uri>> mailboxAuthorizationUrl(EntityKind owner) async =>
      const Err(NetworkFailure());

  @override
  Future<Result<void>> submitFile(LocalFile file, EntityKind owner) async =>
      const Err(NetworkFailure());

  @override
  Future<Result<void>> submitCode(ScannedCode code, EntityKind owner) async =>
      const Err(NetworkFailure());
}

void main() {
  const personal = 'mailbox-personal';

  test('the fake reads, disconnects and toggles the DDA', () async {
    final clock = FixedClock(testNow);
    final repository = FakeCaptureRepository(clock, latency: Duration.zero);
    CaptureSources valueOf(Result<CaptureSources> result) =>
        (result as Ok<CaptureSources>).value;

    final start = valueOf(await repository.sources());
    expect(start.mailboxes.single.emailsScanned, 214);
    expect(start.props, hasLength(2));
    expect(start.mailboxes.single.props, hasLength(6));
    expect(start.dda.single.props, hasLength(5));

    expect(
      valueOf(await repository.readNow(personal)).mailboxes.single.lastReadAt,
      testNow,
    );
    expect(
      await repository.readNow('none'),
      const Err<CaptureSources>(NotFoundFailure()),
    );
    expect(
      valueOf(await repository.setDda(EntityKind.company, on: false))
          .dda
          .single
          .enabled,
      isFalse,
    );
    expect(
      valueOf(await repository.setDda(EntityKind.personal, on: true))
          .dda
          .single
          .enabled,
      isFalse,
    );
    expect(valueOf(await repository.disconnect(personal)).mailboxes, isEmpty);
  });

  test('the provider reads the fake', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(captureRepositoryProvider),
      isA<FakeCaptureRepository>(),
    );
  });

  testWidgets('reads a mailbox now, toggles the DDA and disconnects', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.captureSources);
    expect(find.text('marina.souza@exemplo.com'), findsOneWidget);
    expect(find.text(l10n.todayAt('09:00')), findsOneWidget);
    expect(find.text(l10n.captureBillsOf(3, 214)), findsOneWidget);
    expect(find.text(l10n.captureChatTitle), findsOneWidget);

    await tester.tap(find.byKey(CaptureSourcesScreen.readKey(personal)));
    await settle(tester);
    expect(find.text(l10n.captureReadToast), findsOneWidget);
    expect(find.text(l10n.todayAt('12:00')), findsOneWidget);
    await waitForToast(tester);

    final dda = find.descendant(
      of: find.byKey(const Key('capture-dda-company')),
      matching: find.byType(Switch),
    );
    await tester.tap(dda);
    await settle(tester);
    expect(tester.widget<Switch>(dda).value, isFalse);

    await tester.tap(find.byKey(CaptureSourcesScreen.connectKey));
    await settle(tester);
    expect(
      (app.read(linkOpenerProvider) as FakeLinkOpener).opened.single.host,
      'accounts.example.com',
    );

    await tester.tap(find.byKey(CaptureSourcesScreen.disconnectKey(personal)));
    await settle(tester);
    expect(find.text(l10n.captureDisconnectedToast), findsOneWidget);
    expect(find.text('marina.souza@exemplo.com'), findsNothing);
  });

  testWidgets('an older read shows its day', (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.captureSources,
      overrides: [
        captureRepositoryProvider.overrideWithValue(
          FakeCaptureRepository(
            FixedClock(testNow.subtract(const Duration(days: 2))),
            latency: Duration.zero,
          ),
        ),
      ],
    );

    expect(find.text('06/10'), findsOneWidget);
  });

  testWidgets('failures keep the sources and say why', (tester) async {
    final repository = _FlakyCapture();
    await pumpRoute(
      tester,
      AppRoutes.captureSources,
      overrides: [captureRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    repository.failSources = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    await tester.tap(find.byKey(CaptureSourcesScreen.readKey(personal)));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    await waitForToast(tester);

    await tester.tap(find.byKey(CaptureSourcesScreen.disconnectKey(personal)));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.text('marina.souza@exemplo.com'), findsOneWidget);
  });
}
