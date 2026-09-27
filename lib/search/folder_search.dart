import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../document/text_decoding.dart';
import '../workspace/file_source.dart';
import '../workspace/workspace.dart';

@immutable
class SearchHit {
  const SearchHit({required this.path, required this.line, required this.snippet});

  final String path;

  /// 1-based line number.
  final int line;
  final String snippet;

  @override
  bool operator ==(Object other) =>
      other is SearchHit && other.path == path && other.line == line && other.snippet == snippet;
  @override
  int get hashCode => Object.hash(path, line, snippet);
  @override
  String toString() => 'SearchHit($path:$line)';
}

List<SearchHit> searchInText(String path, String text, String query, {int limit = 1000}) {
  final needle = query.toLowerCase();
  if (needle.isEmpty) return const [];
  final hits = <SearchHit>[];
  final lines = const LineSplitter().convert(text);
  for (var i = 0; i < lines.length && hits.length < limit; i++) {
    final at = lines[i].toLowerCase().indexOf(needle);
    if (at == -1) continue;
    hits.add(SearchHit(path: path, line: i + 1, snippet: makeSnippet(lines[i], at, needle.length)));
  }
  return hits;
}

String makeSnippet(String line, int at, int length, {int radius = 60}) {
  final anchor = math.min(at, line.length);
  final start = math.max(0, anchor - radius);
  final end = math.min(line.length, math.max(start, anchor + length + radius));
  final prefix = start > 0 ? '…' : '';
  final suffix = end < line.length ? '…' : '';
  return '$prefix${line.substring(start, end).trim()}$suffix';
}

List<SearchHit> _searchBatch(List<(String, String)> batch, String query, int limit) {
  final hits = <SearchHit>[];
  for (final (path, text) in batch) {
    if (hits.length >= limit) break;
    hits.addAll(searchInText(path, text, query, limit: limit - hits.length));
  }
  return hits;
}

/// Plain-text, case-insensitive search across a workspace's Markdown files.
/// Files are read on the calling isolate (FileSource may use platform
/// channels); matching runs in a background isolate per batch.
class FolderSearch {
  FolderSearch(this.workspace, {this.maxFileBytes = 5 * 1024 * 1024, this.maxResults = 1000, this.batchSize = 32});

  final Workspace workspace;
  final int maxFileBytes;
  final int maxResults;
  final int batchSize;

  Future<List<SearchHit>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final files = await workspace.markdownFiles();
    final hits = <SearchHit>[];
    for (var i = 0; i < files.length && hits.length < maxResults; i += batchSize) {
      final batch = <(String, String)>[];
      for (final path in files.skip(i).take(batchSize)) {
        final stat = await workspace.source.stat(path);
        if (stat == null || stat.size > maxFileBytes) continue;
        if (!await workspace.containsRealPath(path)) continue;
        try {
          batch.add((path, decodeText(await workspace.source.readBytes(path))));
        } on FileSourceException {
          continue;
        }
      }
      if (batch.isEmpty) continue;
      final limit = maxResults - hits.length;
      hits.addAll(await Isolate.run(() => _searchBatch(batch, query, limit)));
    }
    return hits;
  }
}
