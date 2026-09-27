import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// A directory entry returned by [FileSource.list].
class FileEntry {
  const FileEntry({required this.path, required this.name, required this.isDirectory});

  final String path;
  final String name;
  final bool isDirectory;
}

class FileStat {
  const FileStat({required this.size, required this.modified});

  final int size;
  final DateTime modified;
}

class FileSourceException implements Exception {
  const FileSourceException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => message;
}

/// Read-only access to a tree of files. Paths are absolute within the
/// source and use [pathContext] for joining and normalizing.
abstract interface class FileSource {
  p.Context get pathContext;

  /// Whether [watch] reports changes. Sources that cannot watch return an
  /// empty stream from [watch].
  bool get supportsWatch;

  Future<List<FileEntry>> list(String directory);

  Future<Uint8List> readBytes(String path);

  /// Returns null when [path] does not exist.
  Future<FileStat?> stat(String path);

  /// [path] with symbolic links resolved, or [path] itself when it does not
  /// exist or the source has no links. Used to keep workspace access inside
  /// the workspace root even through links.
  Future<String> realPath(String path);

  /// Emits whenever [path] may have changed, including deletion and
  /// re-creation. Never emits errors.
  Stream<void> watch(String path);
}
