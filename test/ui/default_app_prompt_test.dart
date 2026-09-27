import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_app.dart';

// Harnesses are created inside each testWidgets body (not setUp).
void main() {
  const title = 'Open Markdown files with MDViewer?';

  Future<TestHarness> launch(
    WidgetTester tester, {
    bool supported = true,
    bool isDefault = false,
    bool resetPreferences = true,
  }) async {
    final h = await createHarness(resetPreferences: resetPreferences);
    h.defaultApp
      ..isSupported = supported
      ..isDefaultApp = isDefault;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MdViewerApp(services: h.services));
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> relaunch(WidgetTester tester, TestHarness previous) async {
    await tester.pumpWidget(const SizedBox());
    previous.services.dispose();
    SharedPreferences.resetStatic();
  }

  testWidgets('first run offers to become the default; "Not now" is remembered', (tester) async {
    final h = await launch(tester);
    expect(find.text(title), findsOneWidget);
    expect(
      find.text('Make MDViewer the default app for .md files? You can change this later in the MDViewer menu.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
    expect(h.defaultApp.makeDefaultCalls, 0);
    expect(h.services.settings.defaultAppPromptDone, isTrue);

    await relaunch(tester, h);
    await launch(tester, resetPreferences: false);
    expect(find.text(title), findsNothing, reason: 'asked only once');
  });

  testWidgets('"Make default" asks the handler and reports the result', (tester) async {
    final h = await launch(tester);
    await tester.tap(find.text('Make default'));
    await tester.pumpAndSettle();
    expect(h.defaultApp.makeDefaultCalls, 1);
    expect(h.services.settings.defaultAppPromptDone, isTrue);
    expect(find.text('MDViewer is now the default app for Markdown files.'), findsOneWidget);
  });

  testWidgets('a failed "Make default" is reported', (tester) async {
    final harness = await createHarness();
    harness.defaultApp
      ..isSupported = true
      ..makeDefaultResult = false;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MdViewerApp(services: harness.services));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make default'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not make MDViewer the default'), findsOneWidget);
  });

  testWidgets('dismissing the dialog also counts as asked', (tester) async {
    final h = await launch(tester);
    await tester.tapAt(const Offset(10, 790)); // the barrier
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
    expect(h.services.settings.defaultAppPromptDone, isTrue);
  });

  testWidgets('not shown when MDViewer already is the default', (tester) async {
    await launch(tester, isDefault: true);
    expect(find.text(title), findsNothing);
  });

  testWidgets('not shown when it was already asked', (tester) async {
    SharedPreferences.setMockInitialValues({'defaultAppPromptDone': true});
    await launch(tester, resetPreferences: false);
    expect(find.text(title), findsNothing);
  });

  testWidgets('not shown where the platform cannot set a default', (tester) async {
    final h = await launch(tester, supported: false);
    expect(find.text(title), findsNothing);
    expect(h.services.settings.defaultAppPromptDone, isFalse);
  });

  testWidgets('macOS app menu offers the same action while not default', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final menus = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, (call) async {
      menus.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, null));
    SharedPreferences.setMockInitialValues({'defaultAppPromptDone': true});
    await launch(tester, resetPreferences: false);
    final menu = menus.last.arguments.toString();
    expect(menu, contains('Make MDViewer the Default for Markdown…'));
    expect(RegExp(r'label: Make MDViewer the Default for Markdown…, enabled: true').hasMatch(menu), isTrue, reason: menu);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
