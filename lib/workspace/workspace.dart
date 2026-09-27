import 'package:path/path.dart' as p;

import 'file_source.dart';

const Set<String> markdownExtensions = {'.md', '.markdown', '.mdown', '.mkd'};

bool isMarkdownPath(String path, [p.Context? context]) =>
    markdownExtensions.contains((context ?? p.context).extension(path).toLowerCase());

bool isExcludedDirectory(String name) => name.startsWith('.') || name == 'node_modules';

class TreeNode {
  const TreeNode({required this.path, required this.name, required this.isDirectory, this.children = const []});

  final String path;
  final String name;
  final bool isDirectory;
  final List<TreeNode> children;
}

/// What the user opened: a folder, or a single file (rooted at its directory).
/// All document and resource access is confined to [root].
class Workspace {
  Workspace.folder({required this.source, required String root, String? displayName})
      : root = source.pathContext.normalize(root),
        isFolder = true,
        displayName = displayName ?? source.pathContext.basename(source.pathContext.normalize(root));

  Workspace.singleFile({required this.source, required String file, String? displayName})
      : root = source.pathContext.dirname(source.pathContext.normalize(file)),
        isFolder = false,
        displayName = displayName ?? source.pathContext.basename(file);

  final FileSource source;
  final String root;
  final bool isFolder;
  final String displayName;

  p.Context get _ctx => source.pathContext;

  bool contains(String path) {
    final normalized = _ctx.normalize(path);
    return normalized == root || _ctx.isWithin(root, normalized);
  }

  String relativePath(String path) => _ctx.relative(path, from: root);

  /// Resolves a URL-style [reference] (from a link or image in [fromFile]) to
  /// a path inside the workspace, or null if it is empty or escapes [root].
  /// A leading `/` is relative to [root], as on GitHub.
  String? resolve(String fromFile, String reference) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(reference);
    } catch (_) {
      decoded = reference;
    }
    if (decoded.isEmpty) return null;
    final base = decoded.startsWith('/') ? root : _ctx.dirname(fromFile);
    final relative = decoded.startsWith('/') ? decoded.substring(1) : decoded;
    final resolved = _ctx.normalize(_ctx.join(base, relative));
    return contains(resolved) ? resolved : null;
  }

  Future<TreeNode> buildTree() async =>
      await _buildDirectory(root, displayName) ?? TreeNode(path: root, name: displayName, isDirectory: true);

  Future<TreeNode?> _buildDirectory(String directory, String name) async {
    List<FileEntry> entries;
    try {
      entries = await source.list(directory);
    } on FileSourceException {
      return null;
    }
    final directories = <TreeNode>[];
    final files = <TreeNode>[];
    for (final entry in entries) {
      if (entry.isDirectory) {
        if (isExcludedDirectory(entry.name)) continue;
        final child = await _buildDirectory(entry.path, entry.name);
        if (child != null && child.children.isNotEmpty) directories.add(child);
      } else if (isMarkdownPath(entry.name, _ctx)) {
        files.add(TreeNode(path: entry.path, name: entry.name, isDirectory: false));
      }
    }
    int byName(TreeNode a, TreeNode b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    directories.sort(byName);
    files.sort(byName);
    return TreeNode(path: directory, name: name, isDirectory: true, children: [...directories, ...files]);
  }

  Future<List<String>> markdownFiles() async {
    final files = <String>[];
    void walk(TreeNode node) {
      if (!node.isDirectory) files.add(node.path);
      node.children.forEach(walk);
    }

    walk(await buildTree());
    return files;
  }

  /// README.md, then index.md (case-insensitive) in the root, if present.
  Future<String?> defaultDocument() async {
    List<FileEntry> entries;
    try {
      entries = await source.list(root);
    } on FileSourceException {
      return null;
    }
    for (final wanted in const ['readme.md', 'index.md']) {
      for (final entry in entries) {
        if (!entry.isDirectory && entry.name.toLowerCase() == wanted) return entry.path;
      }
    }
    return null;
  }
}
