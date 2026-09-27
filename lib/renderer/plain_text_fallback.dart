import 'package:flutter/material.dart';

/// Shows a document's raw Markdown when it cannot or should not be rendered.
class PlainTextFallback extends StatelessWidget {
  const PlainTextFallback({super.key, required this.text, this.message, this.maxCharacters = 200000});

  final String text;
  final String? message;
  final int maxCharacters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = text.length > maxCharacters
        ? '${text.substring(0, maxCharacters)}\n\n… (${text.length - maxCharacters} more characters not shown)'
        : text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Container(
            color: theme.colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(message!, style: TextStyle(color: theme.colorScheme.onSecondaryContainer)),
                ),
              ],
            ),
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                shown,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: ['Menlo', 'Consolas', 'DejaVu Sans Mono', 'Courier New'],
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
