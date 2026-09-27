import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mdviewer/app.dart';
import 'package:mdviewer/app_services.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/platform/edit_commands.dart';
import 'package:mdviewer/platform/window_controls.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/renderer/webview_renderer.dart';
import 'package:mdviewer/settings/settings.dart';
import 'package:mdviewer/ui/title_bar.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// macOS only. Checks that real AppKit mouse events in the unified title bar
/// (which sits under the transparent native title bar and its NSToolbar)
/// reach Flutter, using debug-only hooks in MainFlutterWindow.swift:
/// `debugHitTest` runs AppKit's own hit-test from the window's frame view and
/// `debugClick` delivers a mouse-down/up pair through `NSWindow.sendEvent`.
const _window = MethodChannel('mdviewer/window');

Future<String?> _hitTest(Offset point) => _window.invokeMethod<String>(
  'debugHitTest',
  {'x': point.dx, 'y': point.dy},
);

/// Clicks at [point], then pumps until [until] holds (up to ~10 s, since a
/// busy machine can delay frames) or, without [until], for 500 ms.
Future<void> _click(
  WidgetTester tester,
  Offset point, {
  bool Function()? until,
}) async {
  await _window.invokeMethod<bool>('debugClick', {
    'x': point.dx,
    'y': point.dy,
  });
  for (var i = 0; i < (until == null ? 10 : 200); i++) {
    if (until != null && until()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
}) async {
  for (var i = 0; i < 300; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting: ${reason ?? 'condition'}');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native clicks in the title bar reach Flutter; Edit > Select All reaches the WebView',
    (tester) async {
      // Let real (native) pointer events through to the app under test. Must
      // be reset before the test body ends.
      binding.shouldPropagateDevicePointerEvents = true;
      try {
        await _run(tester);
      } finally {
        binding.shouldPropagateDevicePointerEvents = false;
      }
    },
    skip: !Platform.isMacOS,
  );
}

Future<void> _run(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'defaultAppPromptDone': true});
  final folder = await Directory.systemTemp.createTemp('mdv_titlebar');
  addTearDown(() => folder.delete(recursive: true));
  await File(p.join(folder.path, 'README.md'))
      .writeAsString('# Title bar\n\nSome text to select.\n');

  final services = await AppServices.create();
  final renderer = services.renderer as WebViewRendererController;
  var renders = 0;
  renderer.rendered.listen((_) => renders++);
  await tester.pumpWidget(MdViewerApp(services: services));
  await pumpUntil(
    tester,
    () => renderer.status.value == RendererStatus.ready,
    reason: 'renderer ready',
  );
  await services.actions.openIncoming(IncomingDocument(path: folder.path));
  await pumpUntil(tester, () => renders >= 1, reason: 'first render');
  await tester.pumpAndSettle();

  // The native side answered isFullScreen (not in full screen), so the
  // traffic-light inset is in place.
  expect(WindowControls.instance.fullScreen.value, isFalse);
  expect(
    tester.getTopLeft(find.byKey(const Key('title-bar-title'))).dx,
    greaterThanOrEqualTo(macTrafficLightInset),
  );

  // The traffic lights are vertically centred in the 52 px bar.
  final close = await _window.invokeMapMethod<String, Object?>(
    'debugCloseButtonFrame',
  );
  final closeCentre = (close!['y']! as num) + (close['height']! as num) / 2;
  // ignore: avoid_print
  print(
    'Close button frame (Flutter coordinates): $close, centre y = $closeCentre',
  );
  expect(closeCentre, closeTo(macTitleBarHeight / 2, 2));

  // AppKit routes a click on the theme button into the content view, not
  // to the title bar or toolbar.
  final theme = tester.getCenter(find.byKey(const Key('action-theme')));
  expect(theme.dy, lessThan(macTitleBarHeight));
  final hit = await _hitTest(theme);
  // ignore: avoid_print
  print('AppKit hit view at the theme button $theme: $hit');
  expect(
    hit,
    isNot(
      anyOf(
        'NSThemeFrame',
        'NSToolbarView',
        'NSTitlebarView',
        'NSTitlebarContainerView',
        'none',
      ),
    ),
  );

  final before = services.settings.themeMode;
  AppThemeMode next(AppThemeMode mode) =>
      AppThemeMode.values[(mode.index + 1) % AppThemeMode.values.length];
  var expected = before;
  for (var i = 0; i < 3; i++) {
    expected = next(expected);
    await _click(
      tester,
      theme,
      until: () => services.settings.themeMode == expected,
    );
    expect(
      services.settings.themeMode,
      expected,
      reason: 'a native click on the theme button cycles the theme',
    );
  }
  expect(services.settings.themeMode, before);

  // A second button, near the right edge of the bar.
  final larger = tester.getCenter(find.byKey(const Key('action-font-up')));
  final scale = services.settings.fontScale;
  await _click(
    tester,
    larger,
    until: () => services.settings.fontScale > scale,
  );
  expect(services.settings.fontScale, greaterThan(scale));
  await services.settings.resetFontScale();
  expect(services.settings.fontScale, 1.0);
  expect(services.settings.themeMode, isIn(AppThemeMode.values));

  // Clicking into the document makes the WebView first responder; Edit >
  // Select All then selects the document's text through the native side.
  final documentPoint =
      tester.getCenter(find.byType(MdTitleBar)) + const Offset(0, 200);
  await _click(tester, documentPoint);
  await const EditCommands().selectAll();
  await tester.pump(const Duration(milliseconds: 300));
  final selected = await renderer.debugEvaluate(
    'window.getSelection().toString()',
  );
  expect(selected, contains('Some text to select.'));

  // The default-app channel answers (read-only; makeDefault is never called
  // here because it changes the user's system settings).
  expect(services.defaultApp.isSupported, isTrue);
  final isDefault = await services.defaultApp.isDefault();
  // ignore: avoid_print
  print('MDViewer is the default Markdown app: $isDefault');
}
