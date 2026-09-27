import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mdviewer/app.dart';
import 'package:mdviewer/app_services.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/renderer/webview_renderer.dart';
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
    await Directory(p.join(folder.path, 'img')).create();
    await File(p.join(folder.path, 'img', 'dot.png')).writeAsBytes(base64Decode(dotPng));
    // A decoy copy of the renderer page inside the opened folder.
    await Directory(p.join(folder.path, 'assets', 'renderer')).create(recursive: true);
    await File(p.join(folder.path, 'assets', 'renderer', 'index.html'))
        .writeAsString('<html><body>decoy</body></html>');
  });

  tearDown(() => folder.delete(recursive: true));

  testWidgets('opens a folder and renders it in the real WebView', (tester) async {
    SharedPreferences.setMockInitialValues({});
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

    // Save as PDF (macOS/Windows): the WebView produces a real PDF.
    if (renderer.canSavePdf) {
      final pdf = await renderer.createPdf();
      expect(pdf, isNotNull);
      expect(latin1.decode(pdf!.sublist(0, 5)), '%PDF-');
      final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(pdf)).length;
      // ignore: avoid_print
      print('createPdf: ${pdf.length} bytes, $pages page object(s)');
    }

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
  });
}
