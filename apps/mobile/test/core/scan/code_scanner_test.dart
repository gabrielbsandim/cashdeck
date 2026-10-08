import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the fake scanner reads its sample when tapped', (tester) async {
    final read = <String>[];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final builder = container.read(codeScannerProvider);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => builder(context, read.add)),
      ),
    );
    await tester.tap(find.byKey(fakeScannerKey));

    expect(read, [sampleScannedCode]);
  });
}
