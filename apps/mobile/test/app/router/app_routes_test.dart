import 'package:cashdeck/app/router/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a bill route encodes its id', () {
    expect(AppRoutes.bill('a b'), '/bills/a%20b');
    expect(AppRoutes.tabs, hasLength(5));
  });
}
