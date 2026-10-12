import 'package:cashdeck/features/home_widget/application/home_widget_use_cases.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../home_widget_support.dart';

void main() {
  test('PublishHomeWidget hands the snapshot to the widget', () async {
    final publisher = FakeHomeWidgetPublisher();
    final snapshot = WidgetSnapshot.from(now: testNow, hide: false);

    await PublishHomeWidget(publisher)(snapshot);

    expect(publisher.published, [snapshot]);
  });

  test('ClearHomeWidget empties the widget', () async {
    final publisher = FakeHomeWidgetPublisher();

    await ClearHomeWidget(publisher)();

    expect(publisher.cleared, 1);
    expect(publisher.published, isEmpty);
  });
}
