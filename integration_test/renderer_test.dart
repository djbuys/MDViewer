import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mdviewer/app.dart';
import 'package:mdviewer/app_services.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/renderer/webview_renderer.dart';
import 'package:mdviewer/settings/settings.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const readme = '''---
title: Sample
---
# Sample Document

Inline maths \$E = mc^2\$ and a table:

| a | b |
|---|---|
| 1 | 2 |

```mermaid
graph TD; A-->B
```

![dot](img/dot.png)

Go to the [other page](other.md).
''';

const other = '# Other Page\n\nBack to [the sample](README.md).\n';

/// Several printed pages of text, a table and code.
final longDocument = [
  '# Long Document',
  for (var i = 1; i <= 40; i++) ...[
    '## Section $i',
    'Paragraph $i. ' * 30,
    '```dart\nvoid section$i() => print($i);\n```',
  ],
].join('\n\n');

// A 1x1 PNG.
const dotPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 300; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting: ${reason ?? 'condition'}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('mdv_integration');
    await File(p.join(folder.path, 'README.md')).writeAsString(readme);
    await File(p.join(folder.path, 'other.md')).writeAsString(other);
    await File(p.join(folder.path, 'long.md')).writeAsString(longDocument);
    await Directory(p.join(folder.path, 'img')).create();
    await File(p.join(folder.path, 'img', 'dot.png')).writeAsBytes(base64Decode(dotPng));
    // A decoy copy of the renderer page inside the opened folder.
    await Directory(p.join(folder.path, 'assets', 'renderer')).create(recursive: true);
    await File(p.join(folder.path, 'assets', 'renderer', 'index.html'))
        .writeAsString('<html><body>decoy</body></html>');
  });

  tearDown(() => folder.delete(recursive: true));

  testWidgets('opens a folder and renders it in the real WebView', (tester) async {
    SharedPreferences.setMockInitialValues({'defaultAppPromptDone': true});
    final services = await AppServices.create();
    final renderer = services.renderer as WebViewRendererController;
    var renders = 0;
    renderer.rendered.listen((_) => renders++);

    await tester.pumpWidget(MdViewerApp(services: services));
    await pumpUntil(tester, () => renderer.status.value != RendererStatus.loading, reason: 'renderer ready');
    expect(renderer.status.value, RendererStatus.ready);

    await services.actions.openIncoming(IncomingDocument(path: folder.path));
    await pumpUntil(tester, () => renders >= 1, reason: 'first render');

    expect(services.document.currentPath, p.join(folder.path, 'README.md'));
    expect(services.document.headings.first.id, 'sample-document');
    expect(await renderer.debugEvaluate("document.querySelectorAll('.mermaid-diagram svg').length"), 1);
    expect(await renderer.debugEvaluate("document.querySelectorAll('.katex').length"), 1);
    expect(await renderer.debugEvaluate("document.querySelectorAll('table').length"), 1);
    expect(await renderer.debugEvaluate("document.body.innerText.includes('title: Sample')"), false);
    final src = await renderer.debugEvaluate("document.querySelector('img').getAttribute('src')");
    expect(src, startsWith('data:image/png;base64,'));

    // Navigation lock: neither a remote page nor a file: copy of the renderer
    // page may replace the bundled renderer.
    final rendererHref = await renderer.debugEvaluate('window.location.href');
    final decoy = Uri.file(p.join(folder.path, 'assets', 'renderer', 'index.html')).toString();
    await renderer.debugEvaluate('window.location.href = ${jsonEncode(decoy)}; null');
    await tester.pump(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await renderer.debugEvaluate('window.location.href'), rendererHref);
    expect(await renderer.debugEvaluate('typeof window.mdv'), 'object');
    expect(renderer.status.value, RendererStatus.ready);

    // A page reload (e.g. a restarted web process) re-renders the document.
    final rendersBeforeReload = renders;
    await renderer.debugEvaluate('window.location.reload(); null');
    await pumpUntil(tester, () => renders > rendersBeforeReload, reason: 're-rendered after reload');
    expect(await renderer.debugEvaluate("document.querySelectorAll('table').length"), 1);

    await renderer.debugEvaluate("document.querySelector('a[href=\"other.md\"]').click(); null");
    await pumpUntil(
      tester,
      () => services.document.headings.isNotEmpty && services.document.headings.first.id == 'other-page',
      reason: 'navigated to other.md',
    );
    expect(services.document.currentPath, p.join(folder.path, 'other.md'));
    expect(services.document.canGoBack, isTrue);

    // Save as PDF (macOS/Windows), headless: a long document in dark mode is
    // exported light, paginated, and the page is dark again afterwards.
    if (renderer.canSavePdf) {
      final rendersBefore = renders;
      await services.document.open(p.join(folder.path, 'long.md'));
      await pumpUntil(tester, () => renders > rendersBefore, reason: 'long document rendered');
      final darkRenders = renders;
      await services.settings.setThemeMode(AppThemeMode.dark);
      await pumpUntil(tester, () => renders > darkRenders, reason: 'dark render');
      Future<Object?> theme() => renderer.debugEvaluate('document.documentElement.dataset.theme');
      expect(await theme(), 'dark');

      final pdfPath = p.join(folder.path, 'export', 'Long.pdf');
      await Directory(p.dirname(pdfPath)).create();
      Object? themeDuringExport;
      final saved = await services.document.withLightAppearance(() async {
        themeDuringExport = await theme();
        return renderer.savePdf(pdfPath);
      });
      expect(saved, isTrue);
      expect(themeDuringExport, 'light');
      expect(await theme(), 'dark');

      final pdf = await File(pdfPath).readAsBytes();
      final text = latin1.decode(pdf);
      expect(text.substring(0, 5), '%PDF-');
      final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
      final mdls = await Process.run('mdls', ['-name', 'kMDItemNumberOfPages', '-raw', pdfPath]);
      // ignore: avoid_print
      print('savePdf: ${pdf.length} bytes, $pages page object(s); mdls kMDItemNumberOfPages = ${mdls.stdout}');
      expect(pages, greaterThan(1));
      await services.settings.setThemeMode(AppThemeMode.system);
    }
  });
}
