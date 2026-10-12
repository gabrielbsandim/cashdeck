import 'package:cashdeck/features/home_widget/domain/widget_sources.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/mocks.dart';

void main() {
  test('sources with nothing to release close quietly', () {
    final sources = WidgetSources(
      outlook: MockOutlookRepository(),
      bills: MockBillsRepository(),
      insights: MockInsightsRepository(),
    );

    expect(sources.close, returnsNormally);
  });
}
