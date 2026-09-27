import 'package:flutter/material.dart';

import '../app_services.dart';
import '../settings/recents.dart';
import 'open_commands.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recents = AppScope.of(context).recents;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListenableBuilder(
          listenable: recents,
          builder: (context, _) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.description_outlined, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('MDViewer', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Open a Markdown file or a folder to start reading.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    key: const Key('empty-open-file'),
                    onPressed: () => openFileCommand(context),
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Open file'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('empty-open-folder'),
                    onPressed: () => openFolderCommand(context),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open folder'),
                  ),
                ],
              ),
              if (recents.entries.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text('Recent', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final entry in recents.entries)
                  ListTile(
                    key: Key('recent:${entry.location}'),
                    leading: Icon(
                      entry.kind == RecentKind.folder ? Icons.folder_outlined : Icons.description_outlined,
                    ),
                    title: Text(entry.displayName),
                    subtitle: Text(entry.location, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => openRecentCommand(context, entry),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
