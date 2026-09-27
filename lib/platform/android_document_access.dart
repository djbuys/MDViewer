import 'dart:io';

import 'package:flutter/services.dart';

import '../settings/recents.dart';
import '../workspace/file_source.dart';
import '../workspace/io_file_source.dart';
import '../workspace/saf_file_source.dart';
import '../workspace/workspace.dart';
import 'document_access.dart';

/// Android: single files are copied into the app cache by the native side
/// and read as plain paths; folders are read in place through SAF.
class AndroidDocumentAccess implements DocumentAccess {
  AndroidDocumentAccess({MethodChannel? channel, FileSource? cacheSource})
      : _channel = channel ?? const MethodChannel('mdviewer/android_documents'),
        _cache = cacheSource ?? IoFileSource(supportsWatch: false);

  final MethodChannel _channel;
  final FileSource _cache;

  @override
  Future<OpenRequest?> pickFile() async {
    final result = await _channel.invokeMapMethod<String, Object?>('pickFile');
    final path = result?['path'];
    final uri = result?['uri'];
    if (path is! String || uri is! String) return null;
    final name = result?['name'];
    return _file(path, location: uri, name: name is String ? name : null);
  }

  @override
  Future<OpenRequest?> pickFolder() async {
    final result = await _channel.invokeMapMethod<String, Object?>('pickFolder');
    final treeUri = result?['treeUri'];
    if (treeUri is! String) return null;
    final name = result?['name'];
    return _folder(treeUri, name is String ? name : 'Folder');
  }

  @override
  Future<OpenRequest?> restore(RecentEntry entry) async {
    switch (entry.kind) {
      case RecentKind.folder:
        if (!entry.location.startsWith('content:')) {
          return await Directory(entry.location).exists() ? _localFolder(entry.location) : null;
        }
        final ok = await _channel.invokeMethod<bool>('hasTreeAccess', {'treeUri': entry.location});
        return ok == true ? _folder(entry.location, entry.displayName) : null;
      case RecentKind.file:
        if (!entry.location.startsWith('content:')) {
          return await File(entry.location).exists() ? _file(entry.location, location: entry.location) : null;
        }
        final result = await _channel.invokeMapMethod<String, Object?>('restoreFile', {'uri': entry.location});
        final path = result?['path'];
        return path is String ? _file(path, location: entry.location, name: entry.displayName) : null;
    }
  }

  /// VIEW intents arrive as cache-copied files; local folder paths are also
  /// accepted so every platform treats incoming paths the same way.
  @override
  Future<OpenRequest?> openIncoming(IncomingDocument document) async {
    if (await FileSystemEntity.isDirectory(document.path)) return _localFolder(document.path);
    return _file(document.path, location: document.path);
  }

  OpenRequest _localFolder(String path) {
    final workspace = Workspace.folder(source: _cache, root: path);
    return OpenRequest(
      workspace: workspace,
      recent: RecentEntry(kind: RecentKind.folder, location: path, displayName: workspace.displayName),
    );
  }

  OpenRequest _file(String path, {required String location, String? name}) {
    final workspace = Workspace.singleFile(source: _cache, file: path, displayName: name);
    return OpenRequest(
      workspace: workspace,
      file: path,
      recent: RecentEntry(kind: RecentKind.file, location: location, displayName: workspace.displayName),
    );
  }

  OpenRequest _folder(String treeUri, String name) {
    final workspace = Workspace.folder(
      source: SafFileSource(treeUri: treeUri, channel: _channel),
      root: '/',
      displayName: name,
    );
    return OpenRequest(
      workspace: workspace,
      recent: RecentEntry(kind: RecentKind.folder, location: treeUri, displayName: name),
    );
  }
}
