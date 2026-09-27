import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/document/document_controller.dart';
import 'package:mdviewer/open_actions.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/settings/recents.dart';
import 'package:mdviewer/workspace/workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_renderer.dart';
import 'support/fakes.dart';
import 'support/memory_file_source.dart';

void main() {
  late MemoryFileSource source;
  late FakeDocumentAccess access;
  late Recents recents;
  late DocumentController document;
  late OpenActions actions;

  OpenRequest folderRequest() => OpenRequest(
        workspace: Workspace.folder(source: source, root: '/ws'),
        recent: const RecentEntry(kind: RecentKind.folder, location: '/ws', displayName: 'ws'),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    source = MemoryFileSource()
      ..addText('/ws/README.md', '# Readme')
      ..addText('/ws/b.md', '# B');
    access = FakeDocumentAccess();
    recents = await Recents.load();
    document = DocumentController(renderer: FakeRendererController(), launcher: FakeLauncher());
    actions = OpenActions(access: access, recents: recents, document: document);
  });

  tearDown(() => document.dispose());

  test('picking a folder opens it and records it in recents', () async {
    access.nextFolder = folderRequest();
    expect(await actions.pickFolder(), isTrue);
    expect(document.currentPath, '/ws/README.md');
    expect(recents.entries.single.location, '/ws');
  });

  test('picking a file opens that file', () async {
    access.nextFile = OpenRequest(
      workspace: Workspace.singleFile(source: source, file: '/ws/b.md'),
      file: '/ws/b.md',
      recent: const RecentEntry(kind: RecentKind.file, location: '/ws/b.md', displayName: 'b.md'),
    );
    expect(await actions.pickFile(), isTrue);
    expect(document.currentPath, '/ws/b.md');
  });

  test('cancelled pickers change nothing', () async {
    expect(await actions.pickFile(), isFalse);
    expect(await actions.pickFolder(), isFalse);
    expect(document.status, DocumentStatus.empty);
    expect(recents.entries, isEmpty);
  });

  test('restoring a recent entry re-opens it and moves it to the top', () async {
    const other = RecentEntry(kind: RecentKind.file, location: '/other.md', displayName: 'other.md');
    const ws = RecentEntry(kind: RecentKind.folder, location: '/ws', displayName: 'ws');
    await recents.add(ws);
    await recents.add(other);
    access.restorable['/ws'] = folderRequest();
    expect(await actions.openRecent(ws), isTrue);
    expect(recents.entries.first.location, '/ws');
    expect(document.currentPath, '/ws/README.md');
  });

  test('unreachable recent entries are removed', () async {
    const gone = RecentEntry(kind: RecentKind.file, location: '/gone.md', displayName: 'gone.md');
    await recents.add(gone);
    expect(await actions.openRecent(gone), isFalse);
    expect(recents.entries, isEmpty);
  });

  test('incoming documents open through the platform access', () async {
    access.incoming['/ws'] = folderRequest();
    expect(await actions.openIncoming(const IncomingDocument(path: '/ws')), isTrue);
    expect(await actions.openIncoming(const IncomingDocument(path: '/nope')), isFalse);
    expect(document.workspace!.root, '/ws');
  });
}
