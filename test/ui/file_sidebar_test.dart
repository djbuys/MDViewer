import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/ui/file_sidebar.dart';
import 'package:mdviewer/workspace/workspace.dart';

import '../support/test_app.dart';

void main() {
  Future<TestHarness> pumpSidebar(WidgetTester tester, {VoidCallback? onOpened}) async {
    final h = await createHarness();
    await h.services.document.openWorkspace(Workspace.folder(source: h.source, root: '/ws'));
    await tester.pumpWidget(harnessApp(h.services, FileSidebar(onOpened: onOpened)));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('shows the folder tree with the current file selected', (tester) async {
    await pumpSidebar(tester);
    expect(find.text('ws'), findsOneWidget);
    expect(find.text('docs'), findsOneWidget);
    expect(find.byKey(const ValueKey('file:/ws/README.md')), findsOneWidget);
    final tile = tester.widget<ListTile>(find.byKey(const ValueKey('file:/ws/README.md')));
    expect(tile.selected, isTrue);
  });

  testWidgets('tapping a file opens it and notifies the caller', (tester) async {
    var opened = 0;
    final h = await pumpSidebar(tester, onOpened: () => opened++);
    await tester.tap(find.byKey(const ValueKey('file:/ws/guide.md')));
    await tester.pumpAndSettle();
    expect(h.services.document.currentPath, '/ws/guide.md');
    expect(opened, 1);
  });

  testWidgets('folders expand to reveal nested files', (tester) async {
    await pumpSidebar(tester);
    expect(find.byKey(const ValueKey('file:/ws/docs/b.md')), findsNothing);
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('file:/ws/docs/b.md')), findsOneWidget);
  });

  testWidgets('refresh picks up new files', (tester) async {
    final h = await pumpSidebar(tester);
    h.source.addText('/ws/new.md', '# New');
    await tester.tap(find.byKey(const Key('sidebar-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('file:/ws/new.md')), findsOneWidget);
  });
}
