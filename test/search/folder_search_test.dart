import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/search/folder_search.dart';
import 'package:mdviewer/workspace/io_file_source.dart';
import 'package:mdviewer/workspace/workspace.dart';

import 'package:path/path.dart' as p;

import '../support/memory_file_source.dart';

void main() {
  test('searchInText finds case-insensitive matches with 1-based lines', () {
    final hits = searchInText('/a.md', 'first line\nHello World\nhello again', 'HELLO');
    expect(hits.map((h) => h.line), [2, 3]);
    expect(hits.first.snippet, 'Hello World');
    expect(hits.first.path, '/a.md');
  });

  test('searchInText respects the limit and ignores empty queries', () {
    expect(searchInText('/a.md', 'x\nx\nx', 'x', limit: 2), hasLength(2));
    expect(searchInText('/a.md', 'x', ''), isEmpty);
  });

  test('snippets are trimmed around long lines with ellipses', () {
    final line = '${'a' * 100}NEEDLE${'b' * 100}';
    final snippet = makeSnippet(line, 100, 6, radius: 10);
    expect(snippet, '…aaaaaaaaaaNEEDLEbbbbbbbbbb…');
  });

  test('snippets never throw when lower-casing changes the line length', () {
    expect(() => makeSnippet('İ', 5, 1), returnsNormally);
  });

  test('FolderSearch searches markdown files, skipping large and excluded files', () async {
    final source = MemoryFileSource()
      ..addText('/ws/a.md', 'alpha\nneedle one')
      ..addText('/ws/sub/b.md', 'needle two')
      ..addText('/ws/c.txt', 'needle in text file')
      ..addText('/ws/node_modules/x.md', 'needle excluded')
      ..addBytes('/ws/big.md', Uint8List.fromList(List.filled(50, 0x6E)));
    final search = FolderSearch(Workspace.folder(source: source, root: '/ws'), maxFileBytes: 40, batchSize: 1);
    final hits = await search.search('needle');
    expect(hits.map((h) => '${h.path}:${h.line}'), ['/ws/sub/b.md:1', '/ws/a.md:2']);
  });

  test('FolderSearch caps the number of results', () async {
    final source = MemoryFileSource()
      ..addText('/ws/a.md', List.filled(10, 'hit').join('\n'))
      ..addText('/ws/b.md', 'hit');
    final search = FolderSearch(Workspace.folder(source: source, root: '/ws'), maxResults: 4);
    expect(await search.search('hit'), hasLength(4));
  });

  test('blank queries return nothing without reading files', () async {
    final source = MemoryFileSource()..addText('/ws/a.md', 'x');
    expect(await FolderSearch(Workspace.folder(source: source, root: '/ws')).search('  '), isEmpty);
    expect(source.reads, isEmpty);
  });

  test('FolderSearch skips files whose symbolic links escape the folder', () async {
    final temp = await Directory.systemTemp.createTemp('mdv_search_links');
    addTearDown(() => temp.delete(recursive: true));
    final ws = await Directory(p.join(temp.path, 'ws')).create();
    final outside = await Directory(p.join(temp.path, 'outside')).create();
    File(p.join(outside.path, 'secret.md')).writeAsStringSync('needle secret');
    File(p.join(ws.path, 'a.md')).writeAsStringSync('needle inside');
    Link(p.join(ws.path, 'leak.md')).createSync(p.join(outside.path, 'secret.md'));

    final hits = await FolderSearch(Workspace.folder(source: IoFileSource(), root: ws.path)).search('needle');
    expect(hits.map((h) => p.basename(h.path)), ['a.md']);
  });
}
