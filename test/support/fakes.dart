import 'dart:typed_data';
import 'dart:ui';

import 'package:mdviewer/document/external_launcher.dart';
import 'package:mdviewer/platform/document_access.dart';
import 'package:mdviewer/platform/document_sharer.dart';
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

class SharedDocument {
  const SharedDocument({required this.bytes, required this.name, required this.mimeType, this.origin});

  final Uint8List bytes;
  final String name;
  final String mimeType;
  final Rect? origin;
}

class FakeSharer implements DocumentSharer {
  FakeSharer({this.isSupported = false});

  @override
  bool isSupported;
  Object? error;
  final List<SharedDocument> shared = [];

  @override
  Future<void> share({required Uint8List bytes, required String name, required String mimeType, Rect? origin}) async {
    if (error != null) throw error!;
    shared.add(SharedDocument(bytes: bytes, name: name, mimeType: mimeType, origin: origin));
  }
}
