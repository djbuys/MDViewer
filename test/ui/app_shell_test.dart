import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/app.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/search/find_bar.dart';
import 'package:mdviewer/settings/settings.dart';
import 'package:mdviewer/ui/file_sidebar.dart';
import 'package:mdviewer/ui/toc_panel.dart';

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

    await tester.tap(find.byKey(const Key('action-contents')));
    await tester.pumpAndSettle();
    expect(find.byType(TocPanel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toc:readme')));
    await tester.pumpAndSettle();
    expect(h.renderer.calls, contains('scrollToHeading:readme'));
    expect(find.byType(TocPanel), findsNothing);
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

  testWidgets('overflow menu cycles theme, changes font size and prints', (tester) async {
    final h = await pumpApp(tester, const Size(1280, 800));
    await openFolder(tester, h);

    await tester.tap(find.byKey(const Key('action-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-theme')));
    await tester.pumpAndSettle();
    expect(h.services.settings.themeMode, AppThemeMode.light);

    await tester.tap(find.byKey(const Key('action-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-font-up')));
    await tester.pumpAndSettle();
    expect(h.services.settings.fontScale, 1.1);
    expect(h.renderer.lastOptions!.fontScale, 1.1);

    await tester.tap(find.byKey(const Key('action-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-print')));
    await tester.pumpAndSettle();
    expect(h.renderer.calls, contains('print'));
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
}
