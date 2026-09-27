import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/renderer/plain_text_fallback.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('shows the raw text and an optional message', (tester) async {
    await pump(tester, const PlainTextFallback(text: '# Title\nbody', message: 'Renderer unavailable'));
    expect(find.text('# Title\nbody'), findsOneWidget);
    expect(find.text('Renderer unavailable'), findsOneWidget);
  });

  testWidgets('truncates very long text', (tester) async {
    await pump(tester, PlainTextFallback(text: 'x' * 30, maxCharacters: 10));
    expect(find.textContaining('20 more characters not shown'), findsOneWidget);
  });
}
