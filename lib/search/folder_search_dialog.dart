import 'package:flutter/material.dart';

import '../workspace/workspace.dart';
import 'folder_search.dart';

class FolderSearchDialog extends StatefulWidget {
  const FolderSearchDialog({super.key, required this.workspace, this.searcher});

  final Workspace workspace;

  /// Overrides the search implementation (tests); defaults to [FolderSearch].
  final Future<List<SearchHit>> Function(String query)? searcher;

  /// Shows the dialog; resolves to the chosen hit and the query, or null.
  static Future<(SearchHit, String)?> show(BuildContext context, Workspace workspace) =>
      showDialog<(SearchHit, String)>(
        context: context,
        builder: (_) => FolderSearchDialog(workspace: workspace),
      );

  @override
  State<FolderSearchDialog> createState() => _FolderSearchDialogState();
}

class _FolderSearchDialogState extends State<FolderSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<SearchHit> _results = const [];
  String _query = '';
  bool _searching = false;
  bool _searched = false;
  int _generation = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    setState(() => _searching = true);
    final searcher = widget.searcher ?? FolderSearch(widget.workspace).search;
    final results = await searcher(query);
    if (!mounted || generation != _generation) return;
    setState(() {
      _results = results;
      _query = query;
      _searching = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const Key('folder-search-field'),
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search all files in ${widget.workspace.displayName}',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: _search,
              ),
            ),
            if (_searching) const LinearProgressIndicator(),
            Flexible(
              child: _results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_searched ? 'No results' : 'Press Enter to search'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final hit = _results[index];
                        return ListTile(
                          key: ValueKey('hit:${hit.path}:${hit.line}'),
                          dense: true,
                          title: Text('${widget.workspace.relativePath(hit.path)}:${hit.line}'),
                          subtitle: Text(hit.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop((hit, _query)),
                        );
                      },
                    ),
            ),
            if (_results.length >= 1000)
              const Padding(padding: EdgeInsets.all(8), child: Text('Showing the first 1000 results.')),
          ],
        ),
      ),
    );
  }
}
