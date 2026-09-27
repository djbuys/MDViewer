import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/platform/android_document_access.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/settings/recents.dart';
import 'package:mdviewer/workspace/saf_file_source.dart';

import '../support/memory_file_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mdviewer/android_documents');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final cache = MemoryFileSource()..addText('/cache/opened/1/a.md', '# A');
  final access = AndroidDocumentAccess(cacheSource: cache);

  void mock(Object? Function(MethodCall call) reply) =>
      messenger.setMockMethodCallHandler(channel, (call) async => reply(call));

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('picked files open from their cache copy; recents remember the content URI', () async {
    mock((_) => {'path': '/cache/opened/1/a.md', 'uri': 'content://doc/1', 'name': 'a.md'});
    final request = await access.pickFile();
    expect(request!.file, '/cache/opened/1/a.md');
    expect(request.recent.location, 'content://doc/1');
    expect(request.recent.displayName, 'a.md');
  });

  test('picked folders use the SAF source rooted at /', () async {
    mock((_) => {'treeUri': 'content://tree/9', 'name': 'Notes'});
    final request = await access.pickFolder();
    expect(request!.workspace.source, isA<SafFileSource>());
    expect(request.workspace.root, '/');
    expect(request.workspace.displayName, 'Notes');
    expect(request.recent.location, 'content://tree/9');
  });

  test('folder recents need a persisted permission', () async {
    const entry = RecentEntry(kind: RecentKind.folder, location: 'content://tree/9', displayName: 'Notes');
    mock((call) => call.method == 'hasTreeAccess');
    expect(await access.restore(entry), isNotNull);
    mock((call) => false);
    expect(await access.restore(entry), isNull);
  });

  test('file recents are re-copied from their content URI', () async {
    const entry = RecentEntry(kind: RecentKind.file, location: 'content://doc/1', displayName: 'a.md');
    mock((call) => call.method == 'restoreFile' ? {'path': '/cache/opened/1/a.md'} : null);
    final request = await access.restore(entry);
    expect(request!.file, '/cache/opened/1/a.md');
    expect(request.recent.location, 'content://doc/1');
  });

  test('incoming VIEW intents arrive as cache paths', () async {
    final request = await access.openIncoming(const IncomingDocument(path: '/cache/opened/1/a.md'));
    expect(request!.file, '/cache/opened/1/a.md');
    expect(request.workspace.isFolder, isFalse);
  });
}
