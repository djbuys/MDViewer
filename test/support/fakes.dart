import 'package:mdviewer/document/external_launcher.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/settings/recents.dart';

class FakeLauncher implements ExternalLauncher {
  FakeLauncher({this.canOpenFiles = true, this.result = true});

  @override
  bool canOpenFiles;
  bool result;
  final List<Uri> launched = [];
  final List<String> opened = [];

  @override
  Future<bool> launchUri(Uri uri) async {
    launched.add(uri);
    return result;
  }

  @override
  Future<bool> openFile(String path) async {
    opened.add(path);
    return result;
  }
}

/// Lets pending microtasks and zero-duration timers run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

class FakeDocumentAccess implements DocumentAccess {
  OpenRequest? nextFile;
  OpenRequest? nextFolder;
  final Map<String, OpenRequest> restorable = {};
  final Map<String, OpenRequest> incoming = {};

  @override
  Future<OpenRequest?> pickFile() async => nextFile;
  @override
  Future<OpenRequest?> pickFolder() async => nextFolder;
  @override
  Future<OpenRequest?> restore(RecentEntry entry) async => restorable[entry.location];
  @override
  Future<OpenRequest?> openIncoming(IncomingDocument document) async => incoming[document.path];
}
