import 'package:cashdeck/app/router/app_router.dart';
import 'package:cashdeck/app/router/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sends each path through sign-in and the lock', () {
    String? gate(String path, {bool signedIn = true, bool locked = false}) =>
        gateRedirect(path, signedIn: signedIn, locked: locked);

    expect(gate(AppRoutes.bills, signedIn: false), AppRoutes.signIn);
    expect(gate(AppRoutes.signIn, signedIn: false), isNull);
    expect(gate(AppRoutes.bills, locked: true), AppRoutes.unlock);
    expect(gate(AppRoutes.unlock, locked: true), isNull);
    expect(gate(AppRoutes.signIn), AppRoutes.home);
    expect(gate(AppRoutes.unlock), AppRoutes.home);
    expect(gate(AppRoutes.bills), isNull);
  });

  test('away from a safe zone closes what the mask cannot cover', () {
    String? gate(String path) =>
        gateRedirect(path, signedIn: true, locked: false, limited: true);

    for (final path in [
      AppRoutes.chat,
      AppRoutes.chatThread('t1'),
      AppRoutes.chatNew,
      AppRoutes.rails,
      AppRoutes.settingsPayments,
      AppRoutes.settingsConnections,
      AppRoutes.billReceipt('b1'),
      AppRoutes.sharedFile,
      AppRoutes.pasteCode,
    ]) {
      expect(gate(path), AppRoutes.home, reason: path);
    }
    for (final path in [
      AppRoutes.home,
      AppRoutes.bill('b1'),
      AppRoutes.settings,
      AppRoutes.settingsSecurity,
      AppRoutes.safeZone,
    ]) {
      expect(gate(path), isNull, reason: path);
    }
    expect(gateRedirect(AppRoutes.chat, signedIn: true, locked: false), isNull);
  });

  test('opens capture sources from the mailbox OAuth return link', () {
    expect(
      deepLinkTarget(Uri.parse('cashdeck://capture/?connected=1')),
      AppRoutes.captureSources,
    );
    expect(
      deepLinkTarget(Uri.parse('cashdeck://capture?error=INVALID_STATE')),
      AppRoutes.captureSources,
    );
    expect(deepLinkTarget(Uri.parse('cashdeck://widget/refresh')), isNull);
    expect(deepLinkTarget(Uri.parse('/home')), isNull);
  });
}
