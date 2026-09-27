import 'document/document_controller.dart';
import 'platform/document_access.dart';
import 'settings/recents.dart';

/// Turns picks, recents and OS hand-offs into an open workspace.
class OpenActions {
  OpenActions({required this.access, required this.recents, required this.document});

  final DocumentAccess access;
  final Recents recents;
  final DocumentController document;

  Future<bool> pickFile() => _open(access.pickFile);

  Future<bool> pickFolder() => _open(access.pickFolder);

  Future<bool> openIncoming(IncomingDocument incoming) => _open(() => access.openIncoming(incoming));

  Future<bool> openRecent(RecentEntry entry) async {
    final request = await access.restore(entry);
    if (request == null) {
      await recents.remove(entry);
      return false;
    }
    await _apply(request);
    return true;
  }

  Future<bool> _open(Future<OpenRequest?> Function() pick) async {
    final request = await pick();
    if (request == null) return false;
    await _apply(request);
    return true;
  }

  Future<void> _apply(OpenRequest request) async {
    await recents.add(request.recent);
    await document.openWorkspace(request.workspace, file: request.file);
  }
}
