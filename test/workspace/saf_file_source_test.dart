import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/workspace/file_source.dart';
import 'package:mdviewer/workspace/saf_file_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mdviewer/android_documents');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final source = SafFileSource(treeUri: 'content://tree/1');

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('lists entries with POSIX paths', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'list');
      expect(call.arguments, {'treeUri': 'content://tree/1', 'path': '/docs'});
      return [
        {'name': 'a.md', 'isDirectory': false},
        {'name': 'img', 'isDirectory': true},
      ];
    });
    final entries = await source.list('/docs');
    expect(entries.map((e) => e.path), ['/docs/a.md', '/docs/img']);
    expect(entries.last.isDirectory, isTrue);
  });

  test('reads bytes and maps failures to FileSourceException', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') {
        if ((call.arguments as Map)['path'] == '/a.md') return Uint8List.fromList([35, 32, 65]);
        throw PlatformException(code: 'read_failed', message: 'File not found: /b.md');
      }
      return null;
    });
    expect(await source.readBytes('/a.md'), [35, 32, 65]);
    await expectLater(source.readBytes('/b.md'), throwsA(isA<FileSourceException>()));
  });

  test('stats files and returns null when missing', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final path = (call.arguments as Map)['path'];
      return path == '/a.md' ? {'size': 3, 'modified': 1767225600000} : null;
    });
    final stat = await source.stat('/a.md');
    expect(stat!.size, 3);
    expect(stat.modified, DateTime.fromMillisecondsSinceEpoch(1767225600000));
    expect(await source.stat('/nope.md'), isNull);
  });

  test('does not watch', () {
    expect(source.supportsWatch, isFalse);
  });
}
