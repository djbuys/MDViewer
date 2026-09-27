import 'package:flutter/material.dart';

import '../app_services.dart';
import '../open_actions.dart';
import '../settings/recents.dart';

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

Future<void> _run(BuildContext context, Future<bool> Function(OpenActions actions) action) async {
  final actions = AppScope.of(context).actions;
  try {
    await action(actions);
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not open: $e');
  }
}

Future<void> openFileCommand(BuildContext context) => _run(context, (a) => a.pickFile());

Future<void> openFolderCommand(BuildContext context) => _run(context, (a) => a.pickFolder());

Future<void> openRecentCommand(BuildContext context, RecentEntry entry) => _run(context, (a) async {
      final opened = await a.openRecent(entry);
      if (!opened && context.mounted) {
        showMessage(context, '${entry.displayName} is no longer available and was removed from recents.');
      }
      return opened;
    });
