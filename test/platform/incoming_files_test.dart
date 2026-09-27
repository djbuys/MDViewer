import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/platform/incoming_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mdviewer/incoming');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('launch arguments are initial documents; flags are ignored', () async {
    final incoming = IncomingFiles(args: ['/a.md', '--verbose', '/docs'], useChannel: false);
    final initial = await incoming.takeInitial();
    expect(initial.map((d) => d.path), ['/a.md', '/docs']);
  });

  test('pending documents are fetched from the native side', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takePending');
      return [
        {'path': '/x.md', 'bookmark': 'Ym0='},
        {'nopath': true},
      ];
    });
    final initial = await IncomingFiles(useChannel: true).takeInitial();
    expect(initial.single.path, '/x.md');
    expect(initial.single.bookmark, 'Ym0=');
  });

  test('a missing native implementation is not an error', () async {
    expect(await IncomingFiles(useChannel: true).takeInitial(), isEmpty);
  });

  test('documents opened later are streamed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => <Object?>[]);
    final incoming = IncomingFiles(useChannel: true);
    await incoming.takeInitial();
    final received = <IncomingDocument>[];
    incoming.documents.listen(received.add);
    await messenger.handlePlatformMessage(
      'mdviewer/incoming',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('open', [
        {'path': '/later.md'},
      ])),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(received.single.path, '/later.md');
  });
}
