import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_services.dart';

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
    var target = await services.pickSaveLocation('$name.pdf');
    if (target == null) return;
    if (p.extension(target).isEmpty) target = '$target.pdf';
    final bytes = await services.renderer.createPdf();
    if (bytes == null || bytes.isEmpty) throw const FormatException('the document could not be converted');
    await services.writeFile(target, bytes);
    say('Saved ${p.basename(target)}');
  } on FormatException catch (e) {
    say('Could not save PDF: ${e.message}');
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
