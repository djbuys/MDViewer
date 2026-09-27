import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/search/find_bar.dart';

import '../support/fake_renderer.dart';

void main() {
  late FakeRendererController renderer;
  late int closed;

  Future<void> pumpBar(WidgetTester tester, {String initialQuery = ''}) async {
    renderer = FakeRendererController();
    closed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FindBar(renderer: renderer, onClose: () => closed++, initialQuery: initialQuery)),
    ));
  }

  testWidgets('typing searches and shows the match count', (tester) async {
    await pumpBar(tester);
    await tester.enterText(find.byKey(const Key('find-field')), 'foo');
    expect(renderer.calls.last, 'find:foo');
    renderer.emitFind(const FindResult(total: 3, current: 1));
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);
  });

  testWidgets('no matches is reported and navigation disabled', (tester) async {
    await pumpBar(tester);
    await tester.enterText(find.byKey(const Key('find-field')), 'zzz');
    renderer.emitFind(FindResult.none);
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('find-next'))).onPressed, isNull);
  });

  testWidgets('next, previous, enter and escape', (tester) async {
    await pumpBar(tester);
    await tester.enterText(find.byKey(const Key('find-field')), 'foo');
    renderer.emitFind(const FindResult(total: 3, current: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('find-next')));
    await tester.tap(find.byKey(const Key('find-prev')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(renderer.calls, containsAllInOrder(['findNext', 'findPrevious', 'findNext']));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(renderer.calls.last, 'clearFind');
    expect(closed, 1);
  });

  testWidgets('clearing the field clears highlights', (tester) async {
    await pumpBar(tester);
    await tester.enterText(find.byKey(const Key('find-field')), 'foo');
    await tester.enterText(find.byKey(const Key('find-field')), '');
    expect(renderer.calls.last, 'clearFind');
  });

  testWidgets('an initial query searches immediately', (tester) async {
    await pumpBar(tester, initialQuery: 'needle');
    await tester.pump();
    expect(renderer.calls, contains('find:needle'));
    expect(find.text('needle'), findsOneWidget);
  });
}
