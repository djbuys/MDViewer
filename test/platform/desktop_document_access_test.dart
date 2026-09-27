import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/platform/desktop_document_access.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/settings/recents.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  final access = DesktopDocumentAccess();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mdv_access');
    await File(p.join(temp.path, 'a.md')).writeAsString('# A');
  });

  tearDown(() => temp.delete(recursive: true));

  test('file requests are single-file workspaces rooted at the file directory', () {
    final request = access.fileRequest(p.join(temp.path, 'a.md'));
    expect(request.workspace.isFolder, isFalse);
    expect(request.workspace.root, temp.path);
    expect(request.file, p.join(temp.path, 'a.md'));
    expect(request.recent.kind, RecentKind.file);
    expect(request.recent.displayName, 'a.md');
  });

  test('folder requests open the folder without a specific file', () {
    final request = access.folderRequest(temp.path);
    expect(request.workspace.isFolder, isTrue);
    expect(request.file, isNull);
    expect(request.recent.kind, RecentKind.folder);
  });

  test('incoming paths open as file or folder, missing paths are ignored', () async {
    expect((await access.openIncoming(IncomingDocument(path: temp.path)))!.workspace.isFolder, isTrue);
    expect((await access.openIncoming(IncomingDocument(path: p.join(temp.path, 'a.md'))))!.file, isNotNull);
    expect(await access.openIncoming(IncomingDocument(path: p.join(temp.path, 'nope.md'))), isNull);
  });

  test('restores recents only while they still exist', () async {
    final file = RecentEntry(kind: RecentKind.file, location: p.join(temp.path, 'a.md'), displayName: 'a.md');
    expect(await access.restore(file), isNotNull);
    final missing = RecentEntry(kind: RecentKind.folder, location: p.join(temp.path, 'gone'), displayName: 'gone');
    expect(await access.restore(missing), isNull);
  });
}
