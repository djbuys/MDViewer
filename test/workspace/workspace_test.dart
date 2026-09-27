import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/workspace/io_file_source.dart';
import 'package:mdviewer/workspace/workspace.dart';

import 'package:path/path.dart' as p;

import '../support/memory_file_source.dart';

void main() {
  late MemoryFileSource source;
  late Workspace folder;

  setUp(() {
    source = MemoryFileSource()
      ..addText('/ws/README.md', '# Readme')
      ..addText('/ws/guide.markdown', '# Guide')
      ..addText('/ws/notes.txt', 'not markdown')
      ..addText('/ws/docs/b.md', '# B')
      ..addText('/ws/docs/A.MD', '# A')
      ..addText('/ws/docs/img/pic.png', 'png')
      ..addText('/ws/empty/readme.txt', 'no markdown here')
      ..addText('/ws/.git/HEAD.md', 'hidden')
      ..addText('/ws/node_modules/pkg/README.md', 'excluded')
      ..addText('/outside/secret.md', 'secret');
    folder = Workspace.folder(source: source, root: '/ws');
  });

  test('recognizes markdown extensions case-insensitively', () {
    for (final name in ['a.md', 'a.MD', 'a.markdown', 'a.mdown', 'a.mkd']) {
      expect(isMarkdownPath(name), isTrue, reason: name);
    }
    expect(isMarkdownPath('a.txt'), isFalse);
    expect(isMarkdownPath('md'), isFalse);
  });

  test('excludes hidden and node_modules directories', () {
    expect(isExcludedDirectory('.git'), isTrue);
    expect(isExcludedDirectory('node_modules'), isTrue);
    expect(isExcludedDirectory('docs'), isFalse);
  });

  test('folder workspace defaults its display name to the folder name', () {
    expect(folder.displayName, 'ws');
    expect(folder.isFolder, isTrue);
  });

  test('single-file workspace is rooted at the file directory', () {
    final single = Workspace.singleFile(source: source, file: '/ws/docs/b.md');
    expect(single.root, '/ws/docs');
    expect(single.displayName, 'b.md');
    expect(single.isFolder, isFalse);
  });

  test('contains paths inside the root only', () {
    expect(folder.contains('/ws'), isTrue);
    expect(folder.contains('/ws/docs/b.md'), isTrue);
    expect(folder.contains('/wsx/a.md'), isFalse);
    expect(folder.contains('/outside/secret.md'), isFalse);
  });

  test('resolves relative, parent, root-relative and percent-encoded references', () {
    expect(folder.resolve('/ws/docs/b.md', 'img/pic.png'), '/ws/docs/img/pic.png');
    expect(folder.resolve('/ws/docs/b.md', '../README.md'), '/ws/README.md');
    expect(folder.resolve('/ws/docs/b.md', './A.MD'), '/ws/docs/A.MD');
    expect(folder.resolve('/ws/docs/b.md', '/guide.markdown'), '/ws/guide.markdown');
    expect(folder.resolve('/ws/docs/b.md', 'my%20file.md'), '/ws/docs/my file.md');
  });

  test('refuses references that escape the root', () {
    expect(folder.resolve('/ws/docs/b.md', '../../outside/secret.md'), isNull);
    expect(folder.resolve('/ws/README.md', '../outside/secret.md'), isNull);
    expect(folder.resolve('/ws/README.md', ''), isNull);
  });

  test('single-file workspace cannot reach sibling directories above it', () {
    final single = Workspace.singleFile(source: source, file: '/ws/docs/b.md');
    expect(single.resolve('/ws/docs/b.md', '../README.md'), isNull);
    expect(single.resolve('/ws/docs/b.md', 'img/pic.png'), '/ws/docs/img/pic.png');
  });

  test('builds a sorted tree of markdown files, pruning empty and excluded directories', () async {
    final tree = await folder.buildTree();
    expect(tree.name, 'ws');
    expect(tree.children.map((n) => n.name).toList(), ['docs', 'guide.markdown', 'README.md']);
    final docs = tree.children.first;
    expect(docs.isDirectory, isTrue);
    expect(docs.children.map((n) => n.name).toList(), ['A.MD', 'b.md']);
  });

  test('lists markdown files depth-first in tree order', () async {
    expect(await folder.markdownFiles(), ['/ws/docs/A.MD', '/ws/docs/b.md', '/ws/guide.markdown', '/ws/README.md']);
  });

  test('default document prefers README then index', () async {
    expect(await folder.defaultDocument(), '/ws/README.md');
    final other = MemoryFileSource()
      ..addText('/w/index.md', '# Index')
      ..addText('/w/z.md', '# Z');
    expect(await Workspace.folder(source: other, root: '/w').defaultDocument(), '/w/index.md');
    final none = MemoryFileSource()..addText('/w/z.md', '# Z');
    expect(await Workspace.folder(source: none, root: '/w').defaultDocument(), isNull);
  });

  test('relative path is shown relative to the root', () {
    expect(folder.relativePath('/ws/docs/b.md'), 'docs/b.md');
  });

  test('real-path containment uses the source as-is for virtual sources', () async {
    expect(await folder.containsRealPath('/ws/docs/b.md'), isTrue);
    expect(await folder.containsRealPath('/elsewhere/x.md'), isFalse);
  });

  test('real-path containment rejects symbolic links that escape the root', () async {
    final temp = await Directory.systemTemp.createTemp('mdv_ws_links');
    addTearDown(() => temp.delete(recursive: true));
    final ws = await Directory(p.join(temp.path, 'ws')).create();
    final outside = await Directory(p.join(temp.path, 'outside')).create();
    File(p.join(outside.path, 'secret.md')).writeAsStringSync('secret');
    File(p.join(ws.path, 'a.md')).writeAsStringSync('# A');
    Link(p.join(ws.path, 'leak.md')).createSync(p.join(outside.path, 'secret.md'));
    Link(p.join(ws.path, 'alias.md')).createSync(p.join(ws.path, 'a.md'));
    Link(p.join(ws.path, 'linked-dir')).createSync(outside.path);

    final workspace = Workspace.folder(source: IoFileSource(), root: ws.path);
    expect(await workspace.containsRealPath(p.join(ws.path, 'a.md')), isTrue);
    expect(await workspace.containsRealPath(p.join(ws.path, 'alias.md')), isTrue);
    expect(await workspace.containsRealPath(p.join(ws.path, 'leak.md')), isFalse);
    expect(await workspace.containsRealPath(p.join(ws.path, 'linked-dir', 'secret.md')), isFalse);
    expect(workspace.contains(p.join(ws.path, 'leak.md')), isTrue, reason: 'lexical check alone is not enough');
  });
}
