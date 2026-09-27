import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../settings/recents.dart';
import '../workspace/file_source.dart';
import '../workspace/io_file_source.dart';
import '../workspace/workspace.dart';
import 'document_access.dart';

const XTypeGroup _markdownTypeGroup = XTypeGroup(
  label: 'Markdown',
  extensions: ['md', 'markdown', 'mdown', 'mkd'],
);

/// macOS, Windows and Linux: native dialogs via file_selector, plain paths.
class DesktopDocumentAccess implements DocumentAccess {
  DesktopDocumentAccess({FileSource? source}) : source = source ?? IoFileSource();

  final FileSource source;

  @override
  Future<OpenRequest?> pickFile() async {
    final file = await openFile(acceptedTypeGroups: const [_markdownTypeGroup]);
    return file == null ? null : fileRequest(file.path);
  }

  @override
  Future<OpenRequest?> pickFolder() async {
    final directory = await getDirectoryPath();
    return directory == null ? null : folderRequest(directory);
  }

  @override
  Future<OpenRequest?> restore(RecentEntry entry) async {
    switch (entry.kind) {
      case RecentKind.folder:
        return await Directory(entry.location).exists() ? folderRequest(entry.location) : null;
      case RecentKind.file:
        return await File(entry.location).exists() ? fileRequest(entry.location) : null;
    }
  }

  @override
  Future<OpenRequest?> openIncoming(IncomingDocument document) async {
    switch (await FileSystemEntity.type(document.path)) {
      case FileSystemEntityType.directory:
        return folderRequest(document.path);
      case FileSystemEntityType.file:
        return fileRequest(document.path);
      default:
        return null;
    }
  }

  OpenRequest fileRequest(String path) {
    final normalized = source.pathContext.normalize(source.pathContext.absolute(path));
    final workspace = Workspace.singleFile(source: source, file: normalized);
    return OpenRequest(
      workspace: workspace,
      file: normalized,
      recent: RecentEntry(kind: RecentKind.file, location: normalized, displayName: workspace.displayName),
    );
  }

  OpenRequest folderRequest(String path) {
    final normalized = source.pathContext.normalize(source.pathContext.absolute(path));
    final workspace = Workspace.folder(source: source, root: normalized);
    return OpenRequest(
      workspace: workspace,
      recent: RecentEntry(kind: RecentKind.folder, location: normalized, displayName: workspace.displayName),
    );
  }
}
