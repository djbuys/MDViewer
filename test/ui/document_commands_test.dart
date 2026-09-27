import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/app.dart';
import 'package:mdviewer/settings/settings.dart';

import '../support/test_app.dart';

// Harnesses are created inside each testWidgets body (not setUp).
void main() {
  Future<TestHarness> pumpWithDocument(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    TestHarness? harness,
  }) async {
    final h = harness ?? await createHarness();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MdViewerApp(services: h.services));
    h.access.nextFolder = h.folderRequest();
    await h.services.actions.pickFolder();
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('Save as PDF asks for a location and has the renderer save the PDF there', (tester) async {
    final h = await pumpWithDocument(tester);
    h.saveLocation = '/out/README.pdf';

    await tester.tap(find.byKey(const Key('action-save-pdf')));
    await tester.pumpAndSettle();

    expect(h.saveSuggestions, ['README.pdf']);
    expect(h.renderer.savedPdfPaths, ['/out/README.pdf']);
    expect(find.text('Saved README.pdf'), findsOneWidget);
  });

  testWidgets('Save as PDF always saves with a .pdf extension', (tester) async {
    final h = await pumpWithDocument(tester);
    for (final (chosen, saved) in [('/out/report', '/out/report.pdf'), ('/out/report.txt', '/out/report.txt.pdf')]) {
      h.saveLocation = chosen;
      await tester.tap(find.byKey(const Key('action-save-pdf')));
      await tester.pumpAndSettle();
      expect(h.renderer.savedPdfPaths.last, saved);
    }
  });

  testWidgets('Save as PDF does nothing when the user cancels', (tester) async {
    final h = await pumpWithDocument(tester);
    await tester.tap(find.byKey(const Key('action-save-pdf')));
    await tester.pumpAndSettle();
    expect(h.saveSuggestions, hasLength(1));
    expect(h.renderer.savedPdfPaths, isEmpty);
  });

  testWidgets('Save as PDF reports a failed export', (tester) async {
    final h = await pumpWithDocument(tester);
    h.saveLocation = '/out/README.pdf';
    h.renderer.savePdfResult = false;
    await tester.tap(find.byKey(const Key('action-save-pdf')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save PDF'), findsOneWidget);
  });

  testWidgets('Save as PDF and Print use the light appearance in dark mode, then restore it', (tester) async {
    final harness = await createHarness();
    harness.renderer.emitRenderedOnRender = true;
    await harness.services.settings.setThemeMode(AppThemeMode.dark);
    final h = await pumpWithDocument(tester, harness: harness);
    h.renderer.scrollY = 250;
    expect(h.renderer.lastOptions!.dark, isTrue);
    h.saveLocation = '/out/README.pdf';

    await tester.tap(find.byKey(const Key('action-save-pdf')));
    await tester.pumpAndSettle();
    expect(h.renderer.optionsAtSave.single!.dark, isFalse);
    expect(h.renderer.lastOptions!.dark, isTrue);
    expect(h.renderer.lastOptions!.restoreScrollY, 250);

    await tester.tap(find.byKey(const Key('action-print')));
    await tester.pumpAndSettle();
    expect(h.renderer.optionsAtPrint.single!.dark, isFalse);
    expect(h.renderer.lastOptions!.dark, isTrue);
  });

  testWidgets('Save as PDF is hidden where the renderer cannot create PDFs', (tester) async {
    final harness = await createHarness();
    harness.renderer.savePdfSupported = false;
    await pumpWithDocument(tester, harness: harness);
    expect(find.byKey(const Key('action-save-pdf')), findsNothing);
    await tester.tap(find.byKey(const Key('action-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-save-pdf')), findsNothing);
  });

  testWidgets('Share hands the Markdown file to the sharer, anchored at the button', (tester) async {
    final harness = await createHarness();
    harness.sharer.isSupported = true;
    final h = await pumpWithDocument(tester, size: const Size(390, 844), harness: harness);

    final button = find.byKey(const Key('action-share'));
    expect(button, findsOneWidget, reason: 'share stays in the title bar on phones');
    await tester.tap(button);
    await tester.pumpAndSettle();

    final shared = h.sharer.shared.single;
    expect(utf8.decode(shared.bytes), '# Readme\n\nSee [guide](guide.md).');
    expect(shared.name, 'README.md');
    expect(shared.mimeType, 'text/markdown');
    expect(shared.origin, tester.getRect(button));
  });

  testWidgets('Share is hidden where sharing is not supported (desktop)', (tester) async {
    await pumpWithDocument(tester);
    expect(find.byKey(const Key('action-share')), findsNothing);
  });

  testWidgets('Share errors are reported', (tester) async {
    final harness = await createHarness();
    harness.sharer
      ..isSupported = true
      ..error = Exception('boom');
    await pumpWithDocument(tester, size: const Size(390, 844), harness: harness);
    await tester.tap(find.byKey(const Key('action-share')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not share'), findsOneWidget);
  });
}
