import 'package:flutter/material.dart';

import '../app_services.dart';
import '../document/document_controller.dart';
import '../renderer/plain_text_fallback.dart';
import '../renderer/renderer_controller.dart';
import 'empty_state.dart';
import 'error_view.dart';

/// Hosts the renderer and layers status views (empty, error, plain text)
/// over it. The renderer view stays mounted so the WebView is created once.
class DocumentPane extends StatelessWidget {
  const DocumentPane({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final document = services.document;
    final renderer = services.renderer;
    return ListenableBuilder(
      listenable: Listenable.merge([document, renderer.status]),
      builder: (context, _) {
        final rendererStatus = renderer.status.value;
        final unavailable = rendererStatus == RendererStatus.unavailable;
        final ready = document.status == DocumentStatus.ready && document.text != null;
        final plainTextMessage = document.tooLarge
            ? 'This file is too large to render, so it is shown as plain text.'
            : unavailable
                ? (renderer.unavailableReason ?? 'The document renderer is unavailable.')
                : null;
        final Widget? overlay = switch (document.status) {
          DocumentStatus.empty => const EmptyState(),
          DocumentStatus.error => ErrorView(
              message: document.errorMessage ?? 'Unknown error',
              onRetry: document.reload,
              onShowPlainText: document.text == null ? null : document.showAsPlainText,
            ),
          _ when ready && (document.tooLarge || document.showPlainText || unavailable) =>
            PlainTextFallback(text: document.text!, message: plainTextMessage),
          _ => null,
        };
        return Column(
          children: [
            if (document.fileMissing)
              const _Banner(
                key: Key('banner-missing'),
                icon: Icons.warning_amber_outlined,
                text: 'This file no longer exists on disk. Showing the last version.',
              ),
            if (ready && !document.heavyFeatures && !document.tooLarge)
              const _Banner(
                key: Key('banner-large'),
                icon: Icons.speed_outlined,
                text: 'Large file: syntax highlighting, maths and diagrams are turned off.',
              ),
            Expanded(
              child: Stack(
                children: [
                  if (!unavailable) Positioned.fill(child: renderer.buildView(context)),
                  if (document.status == DocumentStatus.loading)
                    const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
                  if (overlay != null)
                    Positioned.fill(
                      // Opaque so taps never reach the WebView underneath.
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        child: Material(color: Theme.of(context).colorScheme.surface, child: overlay),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(color: scheme.onTertiaryContainer))),
          ],
        ),
      ),
    );
  }
}
