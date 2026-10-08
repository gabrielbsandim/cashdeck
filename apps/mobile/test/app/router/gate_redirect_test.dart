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
}
