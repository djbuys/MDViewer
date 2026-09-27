import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('placeholder app shows its name', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('MDViewer'))),
    ));
    expect(find.text('MDViewer'), findsOneWidget);
  });
}
