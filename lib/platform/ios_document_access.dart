import 'dart:io';

import 'package:flutter/services.dart';

import '../settings/recents.dart';
import '../workspace/file_source.dart';
import '../workspace/io_file_source.dart';
import '../workspace/workspace.dart';
import 'document_access.dart';

/// iOS: UIDocumentPicker in place, with security-scoped bookmarks so
/// recents survive restarts. Paths are readable with dart:io while the
/// native side holds their security scope.
class IosDocumentAccess implements DocumentAccess {
  IosDocumentAccess({MethodChannel? channel, FileSource? source})
      : _channel = channel ?? const MethodChannel('mdviewer/ios_documents'),
        source = source ?? IoFileSource(supportsWatch: false);

  final MethodChannel _channel;
  final FileSource source;

  @override
  Future<OpenRequest?> pickFile() async =>
      _fromNative(await _channel.invokeMapMethod<String, Object?>('pickFile'), folder: false);

  @override
  Future<OpenRequest?> pickFolder() async =>
      _fromNative(await _channel.invokeMapMethod<String, Object?>('pickFolder'), folder: true);

  @override
  Future<OpenRequest?> restore(RecentEntry entry) async {
    final bookmark = entry.bookmark;
    if (bookmark == null) return null;
    final result = await _channel.invokeMapMethod<String, Object?>('resolveBookmark', {'bookmark': bookmark});
    return _fromNative(result, folder: entry.kind == RecentKind.folder);
  }

  @override
  Future<OpenRequest?> openIncoming(IncomingDocument document) async => _request(
        document.path,
        document.bookmark,
        folder: await FileSystemEntity.isDirectory(document.path),
      );

  OpenRequest? _fromNative(Map<String, Object?>? result, {required bool folder}) {
    final path = result?['path'];
    if (path is! String) return null;
    final bookmark = result?['bookmark'];
    return _request(path, bookmark is String ? bookmark : null, folder: folder);
  }

  OpenRequest _request(String path, String? bookmark, {required bool folder}) {
    if (folder) {
      final workspace = Workspace.folder(source: source, root: path);
      return OpenRequest(
        workspace: workspace,
        recent: RecentEntry(
          kind: RecentKind.folder,
          location: path,
          displayName: workspace.displayName,
          bookmark: bookmark,
        ),
      );
    }
    final workspace = Workspace.singleFile(source: source, file: path);
    return OpenRequest(
      workspace: workspace,
      file: path,
      recent: RecentEntry(kind: RecentKind.file, location: path, displayName: workspace.displayName, bookmark: bookmark),
    );
  }
}
