import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/document/document_controller.dart';
import 'package:mdviewer/workspace/workspace.dart';

import '../support/fake_renderer.dart';
import '../support/fakes.dart';
import '../support/memory_file_source.dart';

void main() {
  late MemoryFileSource source;
  late FakeRendererController renderer;
  late DocumentController controller;

  Future<void> open({bool watch = true}) async {
    source = MemoryFileSource(supportsWatch: watch)..addText('/ws/a.md', 'v1', modified: DateTime(2026, 1, 1));
    await controller.openWorkspace(Workspace.folder(source: source, root: '/ws'), file: '/ws/a.md');
  }

  setUp(() {
    renderer = FakeRendererController();
    controller = DocumentController(renderer: renderer, launcher: FakeLauncher(), reloadDebounce: Duration.zero);
  });

  tearDown(() => controller.dispose());

  test('a change on disk re-renders and restores the scroll position', () async {
    await open();
    expect(source.hasWatcher('/ws/a.md'), isTrue);
    renderer.scrollY = 300;
    source.touch('/ws/a.md', 'v2', DateTime(2026, 1, 2));
    await settle();
    expect(renderer.lastMarkdown, 'v2');
    expect(renderer.lastOptions!.restoreScrollY, 300);
  });

  test('a change event without a newer modified time does not re-render', () async {
    await open();
    final renders = renderer.renderCount;
    source.notifyChanged('/ws/a.md');
    await settle();
    expect(renderer.renderCount, renders);
  });

  test('deleting the file keeps the last render and flags it missing', () async {
    await open();
    final renders = renderer.renderCount;
    source
      ..remove('/ws/a.md')
      ..notifyChanged('/ws/a.md');
    await settle();
    expect(controller.fileMissing, isTrue);
    expect(controller.status, DocumentStatus.ready);
    expect(renderer.renderCount, renders);

    source.touch('/ws/a.md', 'back', DateTime(2026, 1, 3));
    await settle();
    expect(controller.fileMissing, isFalse);
    expect(renderer.lastMarkdown, 'back');
  });

  test('sources without watch support are re-checked on demand (app resume)', () async {
    await open(watch: false);
    expect(source.hasWatcher('/ws/a.md'), isFalse);
    source.addText('/ws/a.md', 'v2', modified: DateTime(2026, 1, 2));
    await controller.checkForChanges();
    expect(renderer.lastMarkdown, 'v2');
  });

  test('navigating away stops watching the previous file', () async {
    await open();
    source.addText('/ws/b.md', 'b');
    await controller.open('/ws/b.md');
    expect(source.hasWatcher('/ws/a.md'), isFalse);
    expect(source.hasWatcher('/ws/b.md'), isTrue);
  });
}
