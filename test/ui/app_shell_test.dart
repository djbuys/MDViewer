import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/app.dart';
import 'package:mdviewer/platform/incoming_files.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/search/find_bar.dart';
import 'package:mdviewer/settings/recents.dart';
import 'package:mdviewer/settings/settings.dart';
import 'package:mdviewer/ui/file_sidebar.dart';
import 'package:mdviewer/ui/title_bar.dart';
import 'package:mdviewer/ui/toc_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_app.dart';

// Harnesses are created inside each testWidgets body (not setUp) so that
// controller stream subscriptions live in the test's fake-async zone.
void main() {
  Future<TestHarness> pumpApp(WidgetTester tester, Size size, {TestHarness? harness}) async {
    final h = harness ?? await createHarness();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MdViewerApp(services: h.services));
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> openFolder(WidgetTester tester, TestHarness h) async {
    h.access.nextFolder = h.folderRequest();
    await h.services.actions.pickFolder();
    h.renderer.emitHeadings(const [Heading(id: 'readme', text: 'Readme', level: 1)]);
    await tester.pumpAndSettle();
  }

  Icon iconOf(WidgetTester tester, String key) => tester.widget<IconButton>(find.byKey(Key(key))).icon as Icon;

  testWidgets('wide layout shows sidebar, document and contents side by side', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);
    expect(find.byType(FileSidebar), findsOneWidget);
    expect(find.byType(TocPanel), findsOneWidget);
    expect(find.text('README.md'), findsWidgets);

    await tester.tap(find.byKey(const Key('action-toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(find.byType(FileSidebar), findsNothing);
  });

  testWidgets('narrow layout puts files and contents in drawers', (tester) async {
    final h = await pumpApp(tester, const Size(390, 844));
    await openFolder(tester, h);
    expect(find.byType(FileSidebar), findsNothing);
    expect(find.byType(TocPanel), findsNothing);

    // On a phone the contents button is among the first to move into the
    // overflow menu.
    await tester.tap(find.byKey(const Key('action-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-contents')));
    await tester.pumpAndSettle();
    expect(find.byType(TocPanel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toc:readme')));
    await tester.pumpAndSettle();
    expect(h.renderer.calls, contains('scrollToHeading:readme'));
    expect(find.byType(TocPanel), findsNothing);

    await tester.tap(find.byKey(const Key('action-files')));
    await tester.pumpAndSettle();
    expect(find.byType(FileSidebar), findsOneWidget);
  });

  testWidgets('the renderer view (the WebView) survives layout changes', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    final view = tester.element(find.byKey(const ValueKey('fake-renderer')));
    await openFolder(tester, h);
    expect(tester.element(find.byKey(const ValueKey('fake-renderer'))), same(view));
    await tester.tap(find.byKey(const Key('action-toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(tester.element(find.byKey(const ValueKey('fake-renderer'))), same(view));
    tester.view.physicalSize = const Size(600, 800);
    await tester.pumpAndSettle();
    expect(tester.element(find.byKey(const ValueKey('fake-renderer'))), same(view));
  });

  testWidgets('back and forward follow document history', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);
    IconButton button(String key) => tester.widget<IconButton>(find.byKey(Key(key)));
    expect(button('action-back').onPressed, isNull);

    h.renderer.emitLink('guide.md');
    await tester.pumpAndSettle();
    expect(h.services.document.currentPath, '/ws/guide.md');
    expect(button('action-back').onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('action-back')));
    await tester.pumpAndSettle();
    expect(h.services.document.currentPath, '/ws/README.md');
  });

  testWidgets('find action shows the find bar', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);
    await tester.tap(find.byKey(const Key('action-find')));
    await tester.pumpAndSettle();
    expect(find.byType(FindBar), findsOneWidget);
    await tester.tap(find.byKey(const Key('find-close')));
    await tester.pumpAndSettle();
    expect(find.byType(FindBar), findsNothing);
  });

  testWidgets('title bar buttons cycle theme, change font size and print', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);

    await tester.tap(find.byKey(const Key('action-theme')));
    await tester.pumpAndSettle();
    expect(h.services.settings.themeMode, AppThemeMode.light);

    await tester.tap(find.byKey(const Key('action-font-up')));
    await tester.pumpAndSettle();
    expect(h.services.settings.fontScale, 1.1);
    expect(h.renderer.lastOptions!.fontScale, 1.1);

    await tester.tap(find.byKey(const Key('action-print')));
    await tester.pumpAndSettle();
    expect(h.renderer.calls, contains('print'));

    await tester.tap(find.byKey(const Key('action-more')));
    await tester.pumpAndSettle();
    expect(find.text('Reset text size (110%)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu-font-reset')));
    await tester.pumpAndSettle();
    expect(h.services.settings.fontScale, 1.0);
  });

  testWidgets('wide title bar shows every icon group with dividers', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await h.services.recents.add(const RecentEntry(kind: RecentKind.folder, location: '/ws', displayName: 'ws'));
    await openFolder(tester, h);
    for (final id in [
      'back', 'forward', 'open-file', 'open-folder', 'recents', 'find', 'search-folder', //
      'font-down', 'font-up', 'theme', 'toggle-sidebar', 'toggle-toc', 'print', 'more',
    ]) {
      expect(find.byKey(Key('action-$id')), findsOneWidget, reason: id);
    }
    // navigation | file | search | view | output
    expect(find.descendant(of: find.byType(MdTitleBar), matching: find.byType(VerticalDivider)), findsNWidgets(4));

    await tester.tap(find.byKey(const Key('action-more')));
    await tester.pumpAndSettle();
    // Only the overflow-only items are left in the menu.
    expect(find.byKey(const Key('menu-reload')), findsOneWidget);
    expect(find.byKey(const Key('menu-font-reset')), findsOneWidget);
    expect(find.byKey(const Key('menu-theme')), findsNothing);
  });

  testWidgets('narrow title bar moves actions into the overflow menu, each with an icon', (tester) async {
    final h = await pumpApp(tester, const Size(390, 844));
    await openFolder(tester, h);
    expect(find.byKey(const Key('action-find')), findsOneWidget);
    expect(find.byKey(const Key('action-more')), findsOneWidget);
    expect(find.byKey(const Key('action-files')), findsOneWidget);
    for (final id in ['font-up', 'theme', 'print', 'search-folder', 'open-file', 'contents']) {
      expect(find.byKey(Key('action-$id')), findsNothing, reason: id);
    }

    await tester.tap(find.byKey(const Key('action-more')));
    await tester.pumpAndSettle();
    for (final id in [
      'open-file', 'open-folder', 'search-folder', 'font-down', 'font-up', 'theme', 'contents', 'print', //
      'reload', 'font-reset',
    ]) {
      final item = find.byKey(Key('menu-$id'));
      expect(item, findsOneWidget, reason: id);
      expect(find.descendant(of: item, matching: find.byType(Icon)), findsOneWidget, reason: '$id has an icon');
    }
    // Every item in the menu has a leading icon.
    final items = find.byWidgetPredicate((w) => w is PopupMenuItem);
    expect(items, findsWidgets);
    for (var i = 0; i < items.evaluate().length; i++) {
      expect(find.descendant(of: items.at(i), matching: find.byType(Icon)), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('menu-theme')));
    await tester.pumpAndSettle();
    expect(h.services.settings.themeMode, AppThemeMode.light);
  });

  testWidgets('priorities: toggles leave first; find and more always stay', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);
    final actions = tester.widget<MdTitleBar>(find.byType(MdTitleBar)).actions;

    // Room for more, find, back and forward only.
    final tight = splitTitleBarActions(actions, available: 4 * 48, extent: 48);
    expect(tight.bar.map((a) => a.id), ['back', 'forward', 'find']);
    expect(tight.overflow.map((a) => a.id).take(4), ['open-file', 'open-folder', 'recents', 'search-folder']);
    expect(tight.overflow.map((a) => a.id).skip(tight.overflow.length - 2), ['reload', 'font-reset']);

    // Even with no room at all, find and more stay.
    expect(splitTitleBarActions(actions, available: 0, extent: 48).bar.map((a) => a.id), ['find']);

    final candidates = actions.where((a) => a.group != null && !a.menuOnly).length;
    // One button short of everything: the two toggles go first.
    final almost = splitTitleBarActions(actions, available: 48.0 * candidates, extent: 48);
    expect(almost.bar.map((a) => a.id), isNot(contains('toggle-sidebar')));
    expect(almost.bar.map((a) => a.id), isNot(contains('toggle-toc')));
    expect(almost.bar.map((a) => a.id), contains('print'));
    final all = splitTitleBarActions(actions, available: 48.0 * (candidates + 1), extent: 48);
    expect(all.bar, hasLength(candidates));
  });

  testWidgets('theme icon and tooltip reflect the current mode', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    expect(iconOf(tester, 'action-theme').icon, Icons.brightness_auto);
    expect(tester.widget<IconButton>(find.byKey(const Key('action-theme'))).tooltip, 'Theme: follow system');
    await tester.tap(find.byKey(const Key('action-theme')));
    await tester.pumpAndSettle();
    expect(iconOf(tester, 'action-theme').icon, Icons.light_mode);
    expect(tester.widget<IconButton>(find.byKey(const Key('action-theme'))).tooltip, 'Theme: light');
    await tester.tap(find.byKey(const Key('action-theme')));
    await tester.pumpAndSettle();
    expect(iconOf(tester, 'action-theme').icon, Icons.dark_mode);
    expect(h.services.settings.themeMode, AppThemeMode.dark);
  });

  testWidgets('keyboard shortcuts come from the same action list', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(h.services.settings.fontScale, 1.1);
  });

  testWidgets('sidebar and contents visibility are kept in settings', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);
    await tester.tap(find.byKey(const Key('action-toggle-toc')));
    await tester.pumpAndSettle();
    expect(find.byType(TocPanel), findsNothing);
    expect(h.services.settings.tocVisible, isFalse);
    expect(tester.widget<IconButton>(find.byKey(const Key('action-toggle-toc'))).tooltip, 'Show contents');
    await tester.tap(find.byKey(const Key('action-toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(h.services.settings.sidebarVisible, isFalse);
    expect(find.byType(FileSidebar), findsNothing);
  });

  testWidgets('view selections survive a relaunch', (tester) async {
    final first = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, first);
    for (final key in ['action-theme', 'action-theme', 'action-font-up', 'action-font-up']) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('action-toggle-sidebar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-toggle-toc')));
    await tester.pumpAndSettle();

    // "Quit": tear the app down and forget the loaded preferences, keeping
    // only what was written to the (mock) preferences store.
    await tester.pumpWidget(const SizedBox());
    first.services.dispose();
    SharedPreferences.resetStatic();

    final second = await createHarness(resetPreferences: false);
    await pumpApp(tester, const Size(1280, 800), harness: second);
    expect(second.services.settings.themeMode, AppThemeMode.dark);
    expect(second.services.settings.fontScale, 1.2);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(iconOf(tester, 'action-theme').icon, Icons.dark_mode);

    await openFolder(tester, second);
    expect(second.renderer.lastOptions!.dark, isTrue);
    expect(second.renderer.lastOptions!.fontScale, 1.2);
    expect(find.byType(FileSidebar), findsNothing);
    expect(find.byType(TocPanel), findsNothing);
  });

  testWidgets('macOS: unified 52 px title bar with room for the traffic lights', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final menus = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, (call) async {
      menus.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, null));
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);

    expect(tester.getSize(find.byType(MdTitleBar)).height, macTitleBarHeight);
    expect(find.byType(AppBar), findsNothing);
    expect(tester.getTopLeft(find.byKey(const Key('title-bar-title'))).dx, greaterThanOrEqualTo(macTrafficLightInset));
    expect(tester.getBottomLeft(find.byKey(const Key('action-theme'))).dy, lessThanOrEqualTo(macTitleBarHeight));
    await tester.tap(find.byKey(const Key('action-theme')));
    await tester.pumpAndSettle();
    expect(h.services.settings.themeMode, AppThemeMode.light);

    // The menu bar is built from the same actions.
    expect(menus, isNotEmpty);
    final labels = menus.last.arguments.toString();
    for (final label in ['Open File…', 'Copy', 'Select All', 'Hide Files', 'Theme: light', 'Actual Size']) {
      expect(labels, contains(label));
    }
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dark theme setting renders documents dark', (tester) async {
    final harness = await createHarness();
    await harness.services.settings.setThemeMode(AppThemeMode.dark);
    final h = await pumpApp(tester, const Size(1280, 800), harness: harness);
    await openFolder(tester, h);
    expect(h.renderer.lastOptions!.dark, isTrue);
  });

  testWidgets('document messages appear as snackbars', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);
    h.renderer.emitLink('javascript:alert(1)');
    await tester.pumpAndSettle();
    expect(find.textContaining('Unsupported link'), findsOneWidget);
  });

  testWidgets('launch arguments open on startup', (tester) async {
    final harness = await createHarness(incoming: IncomingFiles(args: ['/ws'], useChannel: false));
    harness.access.incoming['/ws'] = harness.folderRequest();
    await pumpApp(tester, const Size(1280, 800), harness: harness);
    expect(harness.services.document.currentPath, '/ws/README.md');
  });
}
