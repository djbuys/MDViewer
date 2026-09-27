import 'package:flutter/widgets.dart';

import 'document/document_controller.dart';
import 'document/external_launcher.dart';
import 'open_actions.dart';
import 'platform/document_access.dart';
import 'platform/document_sharer.dart';
import 'platform/file_saving.dart';
import 'platform/incoming_files.dart';
import 'renderer/renderer_controller.dart';
import 'renderer/webview_renderer.dart';
import 'settings/recents.dart';
import 'settings/settings.dart';

/// The app's long-lived objects, created once in main().
class AppServices {
  AppServices({
    required this.settings,
    required this.recents,
    required this.renderer,
    required this.document,
    required this.actions,
    IncomingFiles? incoming,
    this.sharer = const SharePlusDocumentSharer(),
    this.pickSaveLocation = pickPdfSaveLocation,
    this.writeFile = writeFileBytes,
  }) : incoming = incoming ?? IncomingFiles(useChannel: false);

  static Future<AppServices> create({List<String> args = const []}) async {
    final settings = await Settings.load();
    final recents = await Recents.load();
    final renderer = WebViewRendererController();
    final document = DocumentController(renderer: renderer, launcher: const UrlLauncherExternalLauncher());
    final actions = OpenActions(access: createDocumentAccess(), recents: recents, document: document);
    return AppServices(
      settings: settings,
      recents: recents,
      renderer: renderer,
      document: document,
      actions: actions,
      incoming: IncomingFiles(args: args),
    );
  }

  final Settings settings;
  final Recents recents;
  final RendererController renderer;
  final DocumentController document;
  final OpenActions actions;
  final IncomingFiles incoming;
  final DocumentSharer sharer;
  final SaveLocationPicker pickSaveLocation;
  final FileWriter writeFile;

  void dispose() {
    incoming.dispose();
    document.dispose();
    renderer.dispose();
    settings.dispose();
    recents.dispose();
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => !identical(services, oldWidget.services);
}
