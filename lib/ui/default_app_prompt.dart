import 'package:flutter/material.dart';

import '../app_services.dart';

/// On first launch, offers once to make MDViewer the default app for
/// Markdown (where the platform supports it and it is not already).
/// Returns whether MDViewer is the default afterwards (null if unsupported).
Future<bool?> offerDefaultAppOnFirstRun(BuildContext context, AppServices services) async {
  final handler = services.defaultApp;
  if (!handler.isSupported) return null;
  final isDefault = await handler.isDefault();
  if (isDefault || services.settings.defaultAppPromptDone || !context.mounted) return isDefault;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Open Markdown files with MDViewer?'),
      content: const Text('Make MDViewer the default app for .md files? You can change this later in the MDViewer menu.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Make default')),
      ],
    ),
  );
  // Asked once, whatever the answer (including dismissing the dialog).
  await services.settings.markDefaultAppPromptDone();
  if (accepted != true || !context.mounted) return false;
  return makeDefaultAppCommand(context, services);
}

/// Makes MDViewer the default app for Markdown and reports the result.
Future<bool> makeDefaultAppCommand(BuildContext context, AppServices services) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await services.defaultApp.makeDefault();
  messenger?.showSnackBar(SnackBar(
    content: Text(ok
        ? 'MDViewer is now the default app for Markdown files.'
        : 'Could not make MDViewer the default app for Markdown files.'),
  ));
  return ok;
}
