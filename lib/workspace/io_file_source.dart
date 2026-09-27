import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'file_source.dart';

/// [FileSource] backed by dart:io. Used on desktop, on iOS (inside
/// security-scoped folders) and for Android cache copies.
class IoFileSource implements FileSource {
  IoFileSource({bool? supportsWatch})
      : supportsWatch = supportsWatch ?? (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  final bool supportsWatch;

  @override
  p.Context get pathContext => p.context;

  @override
  Future<List<FileEntry>> list(String directory) async {
    try {
      final entries = <FileEntry>[];
      await for (final entity in Directory(directory).list(followLinks: false)) {
        var isDirectory = entity is Directory;
        if (entity is Link) {
          // Follow links to files only; linked directories could form cycles.
          if (await FileSystemEntity.type(entity.path) != FileSystemEntityType.file) continue;
          isDirectory = false;
        }
        entries.add(FileEntry(path: entity.path, name: p.basename(entity.path), isDirectory: isDirectory));
      }
      return entries;
    } on FileSystemException catch (e) {
      throw FileSourceException(directory, 'Could not list $directory: ${_reason(e)}');
    }
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      throw FileSourceException(path, 'Could not read $path: ${_reason(e)}');
    }
  }

  @override
  Future<FileStat?> stat(String path) async {
    final stat = await File(path).stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    return FileStat(size: stat.size, modified: stat.modified);
  }

  @override
  Stream<void> watch(String path) {
    if (!supportsWatch) return const Stream.empty();
    late final StreamController<void> controller;
    StreamSubscription<WatchEvent>? subscription;
    Timer? rearm;

    void arm() {
      subscription = FileWatcher(path).events.listen(
        (_) => controller.add(null),
        onError: (Object _) {},
        // Some platforms end the watch when the file is deleted or replaced
        // by an atomic save; re-arm and report a change so the caller re-stats.
        onDone: () {
          rearm = Timer(const Duration(milliseconds: 500), () {
            if (controller.isClosed) return;
            controller.add(null);
            arm();
          });
        },
      );
    }

    controller = StreamController<void>(
      onListen: arm,
      onCancel: () async {
        rearm?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  static String _reason(FileSystemException e) => e.osError?.message ?? e.message;
}
