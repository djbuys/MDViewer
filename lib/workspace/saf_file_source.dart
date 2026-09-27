import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'file_source.dart';

/// Android folder access through the Storage Access Framework. Paths are
/// POSIX paths relative to the picked tree, rooted at `/`.
class SafFileSource implements FileSource {
  SafFileSource({required this.treeUri, MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('mdviewer/android_documents');

  final String treeUri;
  final MethodChannel _channel;

  @override
  p.Context get pathContext => p.posix;

  @override
  bool get supportsWatch => false;

  @override
  Stream<void> watch(String path) => const Stream.empty();

  Map<String, Object?> _args(String path) => {'treeUri': treeUri, 'path': path};

  @override
  Future<List<FileEntry>> list(String directory) async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('list', _args(directory)) ?? const [];
      return [
        for (final item in raw.whereType<Map<Object?, Object?>>())
          if (item['name'] is String)
            FileEntry(
              path: p.posix.join(directory, item['name']! as String),
              name: item['name']! as String,
              isDirectory: item['isDirectory'] == true,
            ),
      ];
    } on PlatformException catch (e) {
      throw FileSourceException(directory, 'Could not list $directory: ${e.message}');
    }
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('read', _args(path));
      if (bytes == null) throw FileSourceException(path, 'File not found: $path');
      return bytes;
    } on PlatformException catch (e) {
      throw FileSourceException(path, 'Could not read $path: ${e.message}');
    }
  }

  @override
  Future<FileStat?> stat(String path) async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('stat', _args(path));
      if (map == null) return null;
      return FileStat(
        size: (map['size']! as num).toInt(),
        modified: DateTime.fromMillisecondsSinceEpoch((map['modified']! as num).toInt()),
      );
    } on PlatformException {
      return null;
    }
  }
}
