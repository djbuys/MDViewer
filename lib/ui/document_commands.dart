import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_services.dart';
import '../platform/file_saving.dart';

/// Exports the rendered document as a PDF where the user chooses.
Future<void> savePdfCommand(BuildContext context, AppServices services) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) => messenger?.showSnackBar(SnackBar(content: Text(text)));
  final document = services.document;
  final path = document.currentPath;
  final workspace = document.workspace;
  if (path == null || workspace == null || !services.renderer.canSavePdf) return;
  final name = workspace.source.pathContext.basenameWithoutExtension(path);
  try {
    final chosen = await services.pickSaveLocation('$name.pdf');
    if (chosen == null) return;
    final target = ensurePdfExtension(chosen);
    // Export with the light (print) appearance even in dark mode.
    final saved = await document.withLightAppearance(() => services.renderer.savePdf(target));
    say(saved ? 'Saved ${p.basename(target)}' : 'Could not save PDF: the document could not be exported');
  } catch (e) {
    say('Could not save PDF: $e');
  }
}

/// Shares the open Markdown file itself, read through the workspace's file
/// source (so Android SAF documents and iOS security-scoped files work).
Future<void> shareDocumentCommand(BuildContext context, AppServices services, {Rect? origin}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final document = services.document;
  final path = document.currentPath;
  final workspace = document.workspace;
  if (path == null || workspace == null) return;
  try {
    final bytes = await workspace.source.readBytes(path);
    await services.sharer.share(
      bytes: bytes,
      name: workspace.source.pathContext.basename(path),
      mimeType: 'text/markdown',
      origin: origin,
    );
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not share: $e')));
  }
}
