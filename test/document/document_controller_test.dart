import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/document/document_controller.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/workspace/workspace.dart';

import '../support/fake_renderer.dart';
import '../support/fakes.dart';
import '../support/memory_file_source.dart';

void main() {
  late MemoryFileSource source;
  late FakeRendererController renderer;
  late FakeLauncher launcher;
  late DocumentController controller;
  late Workspace workspace;

  setUp(() {
    source = MemoryFileSource()
      ..addText('/ws/README.md', '# Readme\n[b](docs/b.md)')
      ..addText('/ws/docs/b.md', '# B')
      ..addText('/ws/docs/pic.png', 'PNGDATA')
      ..addText('/ws/docs/notes.txt', 'text');
    renderer = FakeRendererController();
    launcher = FakeLauncher();
    controller = DocumentController(
      renderer: renderer,
      launcher: launcher,
      reloadDebounce: Duration.zero,
      largeFileBytes: 100,
      hugeFileBytes: 1000,
    );
    workspace = Workspace.folder(source: source, root: '/ws');
  });

  tearDown(() => controller.dispose());

  test('starts empty', () {
    expect(controller.status, DocumentStatus.empty);
    expect(controller.currentPath, isNull);
    expect(controller.title, 'MDViewer');
  });

  test('opening a folder shows its README and renders it', () async {
    await controller.openWorkspace(workspace);
    expect(controller.status, DocumentStatus.ready);
    expect(controller.currentPath, '/ws/README.md');
    expect(controller.title, 'README.md');
    expect(renderer.lastMarkdown, '# Readme\n[b](docs/b.md)');
    expect(renderer.lastOptions!.heavyFeatures, isTrue);
    expect(renderer.lastOptions!.dark, isFalse);
  });

  test('opening a folder without a default document stays empty', () async {
    final bare = MemoryFileSource()..addText('/w/z.md', '# Z');
    await controller.openWorkspace(Workspace.folder(source: bare, root: '/w'));
    expect(controller.status, DocumentStatus.empty);
    expect(controller.workspace!.root, '/w');
    expect(renderer.renderCount, 0);
  });

  test('opening an explicit file in a workspace', () async {
    await controller.openWorkspace(workspace, file: '/ws/docs/b.md');
    expect(controller.currentPath, '/ws/docs/b.md');
    expect(renderer.lastMarkdown, '# B');
  });

  test('a missing file produces an error state', () async {
    await controller.openWorkspace(workspace, file: '/ws/missing.md');
    expect(controller.status, DocumentStatus.error);
    expect(controller.errorMessage, contains('/ws/missing.md'));
    expect(renderer.renderCount, 0);
  });

  test('large files render without heavy features; huge files are not rendered', () async {
    source
      ..addBytes('/ws/large.md', Uint8List(101))
      ..addBytes('/ws/huge.md', Uint8List(1001));
    await controller.openWorkspace(workspace, file: '/ws/large.md');
    expect(renderer.lastOptions!.heavyFeatures, isFalse);
    expect(controller.heavyFeatures, isFalse);

    final before = renderer.renderCount;
    await controller.open('/ws/huge.md');
    expect(controller.tooLarge, isTrue);
    expect(controller.status, DocumentStatus.ready);
    expect(controller.text, isNotNull);
    expect(renderer.renderCount, before);
  });

  test('headings from the renderer are exposed and notify listeners', () async {
    await controller.openWorkspace(workspace);
    var notified = 0;
    controller.addListener(() => notified++);
    renderer.emitHeadings(const [Heading(id: 'readme', text: 'Readme', level: 1)]);
    expect(controller.headings.single.id, 'readme');
    expect(notified, 1);
  });

  test('relative markdown links navigate with back/forward history', () async {
    await controller.openWorkspace(workspace);
    renderer.emitLink('docs/b.md');
    await settle();
    expect(controller.currentPath, '/ws/docs/b.md');
    expect(controller.canGoBack, isTrue);
    expect(controller.canGoForward, isFalse);

    await controller.goBack();
    expect(controller.currentPath, '/ws/README.md');
    expect(controller.canGoForward, isTrue);

    await controller.goForward();
    expect(controller.currentPath, '/ws/docs/b.md');
    expect(controller.canGoForward, isFalse);
  });

  test('opening a new document clears forward history', () async {
    await controller.openWorkspace(workspace);
    await controller.open('/ws/docs/b.md');
    await controller.goBack();
    await controller.open('/ws/docs/b.md');
    expect(controller.canGoForward, isFalse);
  });

  test('link fragments scroll after the target document has rendered', () async {
    await controller.openWorkspace(workspace);
    await controller.handleLink('docs/b.md#part');
    expect(renderer.calls, isNot(contains('scrollToHeading:part')));
    renderer.emitRendered();
    await settle();
    expect(renderer.calls, contains('scrollToHeading:part'));
  });

  test('anchor links and same-document links scroll without reloading', () async {
    await controller.openWorkspace(workspace);
    final renders = renderer.renderCount;
    await controller.handleLink('#intro');
    await controller.handleLink('README.md#usage');
    expect(renderer.calls, containsAll(['scrollToHeading:intro', 'scrollToHeading:usage']));
    expect(renderer.renderCount, renders);
    expect(controller.canGoBack, isFalse);
  });

  test('external links go to the launcher', () async {
    await controller.openWorkspace(workspace);
    await controller.handleLink('https://example.com');
    expect(launcher.launched, [Uri.parse('https://example.com')]);
  });

  test('non-markdown workspace files open with the OS when supported', () async {
    await controller.openWorkspace(workspace);
    await controller.handleLink('docs/notes.txt');
    expect(launcher.opened, ['/ws/docs/notes.txt']);
  });

  test('non-markdown files report a message when the OS cannot open them', () async {
    launcher.canOpenFiles = false;
    await controller.openWorkspace(workspace);
    final messages = <String>[];
    controller.messages.listen(messages.add);
    await controller.handleLink('docs/notes.txt');
    await settle();
    expect(launcher.opened, isEmpty);
    expect(messages.single, contains('notes.txt'));
  });

  test('unsupported links report a message', () async {
    await controller.openWorkspace(workspace);
    final messages = <String>[];
    controller.messages.listen(messages.add);
    await controller.handleLink('javascript:alert(1)');
    await controller.handleLink('../../etc/passwd.md');
    await settle();
    expect(messages, hasLength(2));
  });

  test('resolves relative images to data URIs inside the workspace only', () async {
    await controller.openWorkspace(workspace, file: '/ws/docs/b.md');
    expect(renderer.resolver, isNotNull);
    expect(
      await controller.resolveResource('pic.png'),
      'data:image/png;base64,${base64Encode(utf8.encode('PNGDATA'))}',
    );
    expect(await controller.resolveResource('missing.png'), isNull);
    expect(await controller.resolveResource('notes.txt'), isNull);
    expect(await controller.resolveResource('../../outside.png'), isNull);
  });

  test('image mime types', () {
    expect(imageMimeType('a.PNG'), 'image/png');
    expect(imageMimeType('a.jpeg'), 'image/jpeg');
    expect(imageMimeType('a.svg'), 'image/svg+xml');
    expect(imageMimeType('a.txt'), isNull);
  });

  test('appearance changes re-render the current document preserving scroll', () async {
    await controller.openWorkspace(workspace);
    renderer.scrollY = 120;
    final renders = renderer.renderCount;
    controller.setAppearance(dark: true, fontScale: 1.2);
    await settle();
    expect(renderer.renderCount, renders + 1);
    expect(renderer.lastOptions!.dark, isTrue);
    expect(renderer.lastOptions!.fontScale, 1.2);
    expect(renderer.lastOptions!.restoreScrollY, 120);

    controller.setAppearance(dark: true, fontScale: 1.2);
    await settle();
    expect(renderer.renderCount, renders + 1);
  });

  test('appearance set before opening is used for the first render', () async {
    controller.setAppearance(dark: true, fontScale: 1.4);
    await controller.openWorkspace(workspace);
    expect(renderer.lastOptions!.dark, isTrue);
    expect(renderer.lastOptions!.fontScale, 1.4);
  });

  test('renderer errors become an error state that can fall back to plain text', () async {
    await controller.openWorkspace(workspace);
    renderer.emitError('boom');
    expect(controller.status, DocumentStatus.error);
    expect(controller.errorMessage, contains('boom'));
    controller.showAsPlainText();
    expect(controller.status, DocumentStatus.ready);
    expect(controller.showPlainText, isTrue);
    await controller.open('/ws/docs/b.md');
    expect(controller.showPlainText, isFalse);
  });
}
