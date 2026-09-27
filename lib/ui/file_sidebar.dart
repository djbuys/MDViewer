import 'package:flutter/material.dart';

import '../app_services.dart';
import '../workspace/workspace.dart';

class FileSidebar extends StatefulWidget {
  const FileSidebar({super.key, this.onOpened});

  /// Called after a file was tapped (used to close the drawer on phones).
  final VoidCallback? onOpened;

  @override
  State<FileSidebar> createState() => _FileSidebarState();
}

class _FileSidebarState extends State<FileSidebar> {
  Workspace? _workspace;
  Future<TreeNode>? _tree;

  @override
  Widget build(BuildContext context) {
    final document = AppScope.of(context).document;
    return ListenableBuilder(
      listenable: document,
      builder: (context, _) {
        final workspace = document.workspace;
        if (workspace == null) return const SizedBox.shrink();
        if (!identical(workspace, _workspace)) {
          _workspace = workspace;
          _tree = workspace.buildTree();
        }
        return Column(
          children: [
            ListTile(
              dense: true,
              title: Text(
                workspace.displayName,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                key: const Key('sidebar-refresh'),
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() {
                  _tree = workspace.buildTree();
                }),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<TreeNode>(
                future: _tree,
                builder: (context, snapshot) {
                  final root = snapshot.data;
                  if (root == null) return const Center(child: CircularProgressIndicator());
                  if (root.children.isEmpty) {
                    return const Center(
                      child: Padding(padding: EdgeInsets.all(16), child: Text('No Markdown files in this folder.')),
                    );
                  }
                  return ListView(
                    children: [
                      for (final node in root.children) _buildNode(context, workspace, node, document.currentPath, 0),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNode(BuildContext context, Workspace workspace, TreeNode node, String? currentPath, int depth) {
    final indent = 8.0 + depth * 16;
    if (node.isDirectory) {
      final containsCurrent =
          currentPath != null && workspace.source.pathContext.isWithin(node.path, currentPath);
      return ExpansionTile(
        key: PageStorageKey<String>(node.path),
        initiallyExpanded: containsCurrent,
        visualDensity: VisualDensity.compact,
        tilePadding: EdgeInsets.only(left: indent, right: 8),
        leading: const Icon(Icons.folder_outlined, size: 20),
        title: Text(node.name, overflow: TextOverflow.ellipsis),
        children: [for (final child in node.children) _buildNode(context, workspace, child, currentPath, depth + 1)],
      );
    }
    return ListTile(
      key: ValueKey('file:${node.path}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.only(left: indent, right: 8),
      leading: const Icon(Icons.description_outlined, size: 18),
      title: Text(node.name, overflow: TextOverflow.ellipsis),
      selected: node.path == currentPath,
      onTap: () {
        AppScope.of(context).document.open(node.path);
        widget.onOpened?.call();
      },
    );
  }
}
