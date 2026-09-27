import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/platform/ios_document_access.dart';
import 'package:mdviewer/settings/recents.dart';

import '../support/memory_file_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mdviewer/ios_documents');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void mock(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  }

  final access = IosDocumentAccess(source: MemoryFileSource());

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('picked files keep their bookmark in the recent entry', () async {
    mock((_) => {'path': '/Docs/a.md', 'bookmark': 'Ym0='});
    final request = await access.pickFile();
    expect(request!.file, '/Docs/a.md');
    expect(request.workspace.isFolder, isFalse);
    expect(request.recent.kind, RecentKind.file);
    expect(request.recent.bookmark, 'Ym0=');
  });

  test('picked folders open as folder workspaces', () async {
    mock((_) => {'path': '/Docs', 'bookmark': 'Zm9s'});
    final request = await access.pickFolder();
    expect(request!.workspace.isFolder, isTrue);
    expect(request.workspace.root, '/Docs');
    expect(request.recent.location, '/Docs');
  });

  test('cancelled pickers return null', () async {
    mock((_) => null);
    expect(await access.pickFile(), isNull);
    expect(await access.pickFolder(), isNull);
  });

  test('recents are restored through their bookmark', () async {
    mock((call) => call.method == 'resolveBookmark' ? {'path': '/Moved/a.md', 'bookmark': 'bmV3'} : null);
    const entry = RecentEntry(kind: RecentKind.file, location: '/Docs/a.md', displayName: 'a.md', bookmark: 'Ym0=');
    final request = await access.restore(entry);
    expect(calls.single.arguments, {'bookmark': 'Ym0='});
    expect(request!.file, '/Moved/a.md');
    expect(request.recent.bookmark, 'bmV3');
  });

  test('recents without a bookmark cannot be restored', () async {
    const entry = RecentEntry(kind: RecentKind.file, location: '/a.md', displayName: 'a.md');
    expect(await access.restore(entry), isNull);
  });

  test('incoming documents keep the bookmark the OS provided', () async {
    final request = await access.openIncoming(const IncomingDocument(path: '/Inbox/n.md', bookmark: 'aW4='));
    expect(request!.file, '/Inbox/n.md');
    expect(request.recent.bookmark, 'aW4=');
  });
}
