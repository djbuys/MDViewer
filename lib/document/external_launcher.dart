import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Opens things outside the app: web links and non-Markdown files.
abstract interface class ExternalLauncher {
  bool get canOpenFiles;
  Future<bool> launchUri(Uri uri);
  Future<bool> openFile(String path);
}

class UrlLauncherExternalLauncher implements ExternalLauncher {
  const UrlLauncherExternalLauncher();

  @override
  bool get canOpenFiles => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Future<bool> launchUri(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openFile(String path) async {
    try {
      return await launchUrl(Uri.file(path));
    } catch (_) {
      return false;
    }
  }
}
