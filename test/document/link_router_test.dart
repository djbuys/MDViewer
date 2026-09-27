import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/document/link_router.dart';
import 'package:mdviewer/workspace/workspace.dart';

import '../support/memory_file_source.dart';

void main() {
  final workspace = Workspace.folder(source: MemoryFileSource(), root: '/ws');
  final router = LinkRouter(workspace);
  LinkTarget classify(String href) => router.classify(href, currentFile: '/ws/docs/a.md');

  test('fragment-only links scroll within the document', () {
    expect(classify('#install'), const InDocumentAnchor('install'));
    expect(classify('#caf%C3%A9'), const InDocumentAnchor('café'));
  });

  test('relative markdown links open inside the app, keeping the fragment', () {
    expect(classify('b.md'), const WorkspaceDocument('/ws/docs/b.md', null));
    expect(classify('../README.md#usage'), const WorkspaceDocument('/ws/README.md', 'usage'));
    expect(classify('/guide.markdown'), const WorkspaceDocument('/ws/guide.markdown', null));
    expect(classify('b.md?plain=1'), const WorkspaceDocument('/ws/docs/b.md', null));
  });

  test('web and mail links are external', () {
    expect(classify('https://example.com/x'), ExternalLink(Uri.parse('https://example.com/x')));
    expect(classify('HTTP://example.com'), ExternalLink(Uri.parse('HTTP://example.com')));
    expect(classify('mailto:a@b.c'), ExternalLink(Uri.parse('mailto:a@b.c')));
  });

  test('relative non-markdown files are workspace files', () {
    expect(classify('diagram.pdf'), const WorkspaceFile('/ws/docs/diagram.pdf'));
  });

  test('other schemes, escapes and empty links are unsupported', () {
    expect(classify('javascript:alert(1)'), const UnsupportedLink('javascript:alert(1)'));
    expect(classify('file:///etc/passwd'), const UnsupportedLink('file:///etc/passwd'));
    expect(classify('../../outside.md'), const UnsupportedLink('../../outside.md'));
    expect(classify('   '), const UnsupportedLink('   '));
  });

  test('a link to the current file with a fragment is an in-document anchor target', () {
    expect(classify('a.md#top'), const WorkspaceDocument('/ws/docs/a.md', 'top'));
  });
}
