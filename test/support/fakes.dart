import 'package:mdviewer/document/external_launcher.dart';

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
