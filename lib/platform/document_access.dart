import 'package:flutter/foundation.dart';

import '../settings/recents.dart';
import '../workspace/workspace.dart';
import 'desktop_document_access.dart';

/// What to show after the user picked or restored something.
@immutable
class OpenRequest {
  const OpenRequest({required this.workspace, required this.recent, this.file});

  final Workspace workspace;

  /// The document to show; null opens the workspace's default document.
  final String? file;
  final RecentEntry recent;
}

/// A file or folder handed to the app by the OS (launch arguments,
/// "Open with", share sheet, drag-and-drop).
@immutable
class IncomingDocument {
  const IncomingDocument({required this.path, this.bookmark});

  final String path;

  /// iOS security-scoped bookmark (base64), when the OS provided one.
  final String? bookmark;
}

/// Platform-specific file and folder picking and re-opening.
abstract interface class DocumentAccess {
  Future<OpenRequest?> pickFile();
  Future<OpenRequest?> pickFolder();

  /// Re-opens a recent entry, or returns null if it is no longer reachable.
  Future<OpenRequest?> restore(RecentEntry entry);

  Future<OpenRequest?> openIncoming(IncomingDocument document);
}

DocumentAccess createDocumentAccess() => DesktopDocumentAccess();
