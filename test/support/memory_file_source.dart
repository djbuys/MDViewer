import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mdviewer/workspace/file_source.dart';
import 'package:path/path.dart' as p;

/// In-memory POSIX [FileSource] for tests. Directories exist implicitly
/// wherever a file lives beneath them.
class MemoryFileSource implements FileSource {
  MemoryFileSource({this.supportsWatch = true});

  @override
  final bool supportsWatch;

  final Map<String, ({Uint8List bytes, DateTime modified})> _files = {};
  final Map<String, StreamController<void>> _watchers = {};

  /// Every path passed to [readBytes], in order.
  final List<String> reads = [];

  @override
  p.Context get pathContext => p.posix;

  void addText(String path, String text, {DateTime? modified}) =>
      addBytes(path, Uint8List.fromList(utf8.encode(text)), modified: modified);

  void addBytes(String path, Uint8List bytes, {DateTime? modified}) {
    _files[p.posix.normalize(path)] = (bytes: bytes, modified: modified ?? DateTime(2026, 1, 1));
  }

  void remove(String path) => _files.remove(p.posix.normalize(path));

  /// Replaces a file's content and modified time, then fires its watchers.
  void touch(String path, String text, DateTime modified) {
    addText(path, text, modified: modified);
    notifyChanged(path);
  }

  void notifyChanged(String path) => _watchers[p.posix.normalize(path)]?.add(null);

  bool hasWatcher(String path) => _watchers[p.posix.normalize(path)]?.hasListener ?? false;

  @override
  Future<List<FileEntry>> list(String directory) async {
    final dir = p.posix.normalize(directory);
    final children = <String, bool>{};
    for (final path in _files.keys) {
      if (!p.posix.isWithin(dir, path)) continue;
      final parts = p.posix.split(p.posix.relative(path, from: dir));
      children[parts.first] = (children[parts.first] ?? false) || parts.length > 1;
    }
    if (children.isEmpty) throw FileSourceException(directory, 'Could not list $directory');
    return [
      for (final entry in children.entries)
        FileEntry(path: p.posix.join(dir, entry.key), name: entry.key, isDirectory: entry.value),
    ];
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    reads.add(path);
    final file = _files[p.posix.normalize(path)];
    if (file == null) throw FileSourceException(path, 'File not found: $path');
    return file.bytes;
  }

  @override
  Future<FileStat?> stat(String path) async {
    final file = _files[p.posix.normalize(path)];
    return file == null ? null : FileStat(size: file.bytes.length, modified: file.modified);
  }

  @override
  Future<String> realPath(String path) async => path;

  @override
  Stream<void> watch(String path) {
    if (!supportsWatch) return const Stream.empty();
    return _watchers.putIfAbsent(p.posix.normalize(path), () => StreamController<void>.broadcast()).stream;
  }
}
