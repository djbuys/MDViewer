import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_services.dart';

class TocPanel extends StatelessWidget {
  const TocPanel({super.key, this.onSelected});

  /// Called after a heading was tapped (used to close the drawer on phones).
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: services.document,
      builder: (context, _) {
        final headings = services.document.headings.where((h) => h.level <= 4).toList();
        if (headings.isEmpty) return const Center(child: Text('No headings'));
        final topLevel = headings.map((h) => h.level).reduce(math.min);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(dense: true, title: Text('Contents', style: theme.textTheme.titleSmall)),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: headings.length,
                itemBuilder: (context, index) {
                  final heading = headings[index];
                  return ListTile(
                    key: ValueKey('toc:${heading.id}'),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.only(left: 16.0 + (heading.level - topLevel) * 14, right: 8),
                    title: Text(
                      heading.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: heading.level == topLevel ? const TextStyle(fontWeight: FontWeight.w600) : null,
                    ),
                    onTap: () {
                      services.renderer.scrollToHeading(heading.id);
                      onSelected?.call();
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
