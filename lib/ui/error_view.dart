import 'package:flutter/material.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.onShowPlainText});

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onShowPlainText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('Could not display this document', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (onRetry != null) FilledButton(onPressed: onRetry, child: const Text('Retry')),
                  if (onShowPlainText != null)
                    OutlinedButton(onPressed: onShowPlainText, child: const Text('Show as plain text')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
