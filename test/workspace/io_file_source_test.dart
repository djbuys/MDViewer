import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/workspace/file_source.dart';
import 'package:mdviewer/workspace/io_file_source.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  final source = IoFileSource();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mdv_io_test');
    await File(p.join(temp.path, 'a.md')).writeAsString('# A');
    await Directory(p.join(temp.path, 'sub')).create();
    await File(p.join(temp.path, 'sub', 'b.md')).writeAsString('# B');
  });

  tearDown(() => temp.delete(recursive: true));

  test('lists files and directories', () async {
    final entries = await source.list(temp.path);
    final byName = {for (final e in entries) e.name: e};
    expect(byName.keys, containsAll(['a.md', 'sub']));
    expect(byName['sub']!.isDirectory, isTrue);
    expect(byName['a.md']!.isDirectory, isFalse);
    expect(byName['a.md']!.path, p.join(temp.path, 'a.md'));
  });

  test('reads bytes and stats files', () async {
    final path = p.join(temp.path, 'a.md');
    expect(String.fromCharCodes(await source.readBytes(path)), '# A');
    final stat = await source.stat(path);
    expect(stat!.size, 3);
  });

  test('stat returns null for a missing file', () async {
    expect(await source.stat(p.join(temp.path, 'nope.md')), isNull);
  });

  test('reading a missing file throws FileSourceException', () async {
    final path = p.join(temp.path, 'nope.md');
    await expectLater(
      source.readBytes(path),
      throwsA(isA<FileSourceException>().having((e) => e.path, 'path', path)),
    );
  });

  test('listing a missing directory throws FileSourceException', () async {
    await expectLater(source.list(p.join(temp.path, 'nope')), throwsA(isA<FileSourceException>()));
  });

  test('realPath resolves symbolic links and keeps missing paths unchanged', () async {
    final outside = await Directory.systemTemp.createTemp('mdv_outside');
    addTearDown(() => outside.delete(recursive: true));
    final target = File(p.join(outside.path, 'secret.md'))..writeAsStringSync('secret');
    final link = Link(p.join(temp.path, 'link.md'))..createSync(target.path);
    expect(await source.realPath(link.path), await target.resolveSymbolicLinks());
    final plain = p.join(temp.path, 'a.md');
    expect(await source.realPath(plain), await File(plain).resolveSymbolicLinks());
    final missing = p.join(temp.path, 'nope.md');
    expect(await source.realPath(missing), missing);
  });

  test('uses the platform path context', () {
    expect(source.pathContext.style, p.context.style);
  });
}
