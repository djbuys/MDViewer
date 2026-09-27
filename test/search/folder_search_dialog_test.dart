import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/search/folder_search.dart';
import 'package:mdviewer/search/folder_search_dialog.dart';
import 'package:mdviewer/workspace/workspace.dart';

import '../support/memory_file_source.dart';

void main() {
  final workspace = Workspace.folder(source: MemoryFileSource(), root: '/ws');

  testWidgets('submitting shows results and selecting one pops with the query', (tester) async {
    (SearchHit, String)? popped;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            popped = await showDialog<(SearchHit, String)>(
              context: context,
              builder: (_) => FolderSearchDialog(
                workspace: workspace,
                searcher: (query) async => [
                  SearchHit(path: '/ws/docs/b.md', line: 3, snippet: 'the $query here'),
                ],
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Press Enter to search'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('folder-search-field')), 'needle');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('docs/b.md:3'), findsOneWidget);
    expect(find.text('the needle here'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hit:/ws/docs/b.md:3')));
    await tester.pumpAndSettle();
    expect(popped!.$1.path, '/ws/docs/b.md');
    expect(popped!.$2, 'needle');
  });

  testWidgets('reports no results', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FolderSearchDialog(workspace: workspace, searcher: (_) async => const [])),
    ));
    await tester.enterText(find.byKey(const Key('folder-search-field')), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);
  });
}
