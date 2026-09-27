import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/renderer/plain_text_fallback.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/settings/recents.dart';
import 'package:mdviewer/ui/document_pane.dart';
import 'package:mdviewer/ui/error_view.dart';
import 'package:mdviewer/workspace/workspace.dart';

import '../support/test_app.dart';

// Harnesses are created inside each testWidgets body (not setUp) so that
// controller stream subscriptions live in the test's fake-async zone.
void main() {
  Future<void> pumpPane(WidgetTester tester, TestHarness h) async {
    await tester.pumpWidget(harnessApp(h.services, const DocumentPane()));
    await tester.pump();
  }

  testWidgets('empty state offers open actions and recents', (tester) async {
    final h = await createHarness();
    await h.services.recents.add(const RecentEntry(kind: RecentKind.folder, location: '/ws', displayName: 'ws'));
    h.access.nextFolder = h.folderRequest();
    h.access.restorable['/ws'] = h.folderRequest();
    await pumpPane(tester, h);
    expect(find.byKey(const Key('empty-open-file')), findsOneWidget);
    expect(find.byKey(const Key('recent:/ws')), findsOneWidget);

    await tester.tap(find.byKey(const Key('empty-open-folder')));
    await tester.pumpAndSettle();
    expect(h.services.document.currentPath, '/ws/README.md');
    expect(find.byKey(const Key('empty-open-file')), findsNothing);
    expect(find.byKey(const ValueKey('fake-renderer')), findsOneWidget);
  });

  testWidgets('tapping an unreachable recent removes it and says so', (tester) async {
    final h = await createHarness();
    await h.services.recents.add(const RecentEntry(kind: RecentKind.file, location: '/gone.md', displayName: 'gone.md'));
    await pumpPane(tester, h);
    await tester.tap(find.byKey(const Key('recent:/gone.md')));
    await tester.pumpAndSettle();
    expect(find.textContaining('gone.md is no longer available'), findsOneWidget);
    expect(find.byKey(const Key('recent:/gone.md')), findsNothing);
  });

  testWidgets('errors show an error view with retry', (tester) async {
    final h = await createHarness();
    await h.services.document.openWorkspace(Workspace.folder(source: h.source, root: '/ws'), file: '/ws/missing.md');
    await pumpPane(tester, h);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    h.source.addText('/ws/missing.md', '# Back');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorView), findsNothing);
    expect(h.renderer.lastMarkdown, '# Back');
  });

  testWidgets('renderer errors offer a plain-text fallback', (tester) async {
    final h = await createHarness();
    await h.services.document.openWorkspace(Workspace.folder(source: h.source, root: '/ws'));
    await pumpPane(tester, h);
    h.renderer.emitError('boom');
    await tester.pump();
    await tester.tap(find.text('Show as plain text'));
    await tester.pump();
    expect(find.byType(PlainTextFallback), findsOneWidget);
    expect(find.textContaining('See [guide](guide.md).'), findsOneWidget);
  });

  testWidgets('an unavailable renderer falls back to plain text with the reason', (tester) async {
    final h = await createHarness();
    h.renderer.reason = 'Install WebView2';
    await h.services.document.openWorkspace(Workspace.folder(source: h.source, root: '/ws'));
    await pumpPane(tester, h);
    h.renderer.statusNotifier.value = RendererStatus.unavailable;
    await tester.pump();
    expect(find.byType(PlainTextFallback), findsOneWidget);
    expect(find.text('Install WebView2'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-renderer')), findsNothing);
  });

  testWidgets('shows a banner when the open file is deleted', (tester) async {
    final h = await createHarness();
    await h.services.document.openWorkspace(Workspace.folder(source: h.source, root: '/ws'));
    await pumpPane(tester, h);
    h.source
      ..remove('/ws/README.md')
      ..notifyChanged('/ws/README.md');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('banner-missing')), findsOneWidget);
  });

  testWidgets('shows a banner for large files rendered without heavy features', (tester) async {
    final h = await createHarness();
    h.source.addBytes('/ws/large.md', Uint8List(6 * 1024 * 1024));
    await h.services.document.openWorkspace(Workspace.folder(source: h.source, root: '/ws'), file: '/ws/large.md');
    await pumpPane(tester, h);
    expect(find.byKey(const Key('banner-large')), findsOneWidget);
  });
}
