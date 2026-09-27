import 'dart:convert';

import 'package:flutter/foundation.dart';

const String rendererAssetPath = 'assets/renderer/index.html';

/// Decides what the renderer WebView may load and who may use its JS bridge.
///
/// The WebView's first load is always the app's own bundled renderer page
/// (`initialFile`), which every platform loads as a `file:` URL ending in
/// [rendererAssetPath]. That exact URL is captured on its first navigation or
/// load; afterwards only that URL (ignoring the fragment) is allowed, so a
/// remote page or a `file:` copy of the renderer inside an opened folder can
/// never be shown or reach the bridge.
class RendererNavigationPolicy {
  Uri? _rendererUrl;

  /// The captured renderer page URL, without its fragment.
  Uri? get rendererUrl => _rendererUrl;

  /// Whether a navigation to [url] may proceed. Captures the renderer URL
  /// from the first bundled renderer page seen.
  bool allowNavigation(Uri? url) {
    if (url == null) return false;
    if (_rendererUrl != null) return isRendererUrl(url);
    if (!_isBundledRendererPage(url)) return false;
    _rendererUrl = url.removeFragment();
    return true;
  }

  /// Whether [url] is the captured renderer page. Never captures.
  bool isRendererUrl(Uri? url) {
    final known = _rendererUrl;
    return url != null && known != null && _key(url) == _key(known);
  }

  /// Whether [url] is (or, before capture, could be) the renderer page load.
  /// Used for load errors that may arrive before the URL is captured.
  bool isRendererLoad(Uri? url) => _rendererUrl == null ? _isBundledRendererPage(url) : isRendererUrl(url);

  /// Whether a JavaScript handler call may be served.
  bool acceptsHandlerCall({required bool isMainFrame, required Uri? requestUrl}) =>
      isMainFrame && isRendererUrl(requestUrl);

  static bool _isBundledRendererPage(Uri? url) =>
      url != null && url.scheme == 'file' && url.path.endsWith(rendererAssetPath);

  static String _key(Uri url) {
    String path;
    try {
      path = Uri.decodeFull(url.path);
    } catch (_) {
      path = url.path;
    }
    return '${url.scheme.toLowerCase()}://${url.host.toLowerCase()}$path?${url.query}';
  }
}

/// Origins that may receive the `window.flutter_inappwebview` bridge
/// (`InAppWebViewSettings.javaScriptBridgeOriginAllowList`).
///
/// iOS, macOS and Windows (and Linux, which ignores the list) test each entry
/// as a JavaScript RegExp against `window.location.origin`; a `file:` page
/// reports `file://`, or `null` when file access from file URLs is disabled
/// (as here). Android matches entries with WebView origin rules, where
/// `file://` matches `file:` documents. Remote origins never match.
Set<String> bridgeOriginAllowList(TargetPlatform platform) => switch (platform) {
      TargetPlatform.android => const {'file://'},
      _ => const {r'^(file://|null)$'},
    };

/// A fire-and-forget call to `window.mdv.<method>`. Ends in `null` so the
/// WebView never has to marshal a Promise back to Dart.
String jsCall(String method, [List<Object?> args = const []]) =>
    'window.mdv.$method(${args.map(jsonEncode).join(', ')}); null';

enum PrintMode { native, javascript, unsupported }

PrintMode printModeFor(TargetPlatform platform) => switch (platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => PrintMode.native,
      TargetPlatform.windows => PrintMode.javascript,
      _ => PrintMode.unsupported,
    };

/// Save as PDF: macOS prints to a file (paginated, print styles); Windows
/// uses WebView2's PrintToPdf (`createPdf`), which also paginates. iOS already
/// offers "Save to Files" in its print sheet, so the app offers Save as PDF
/// on macOS and Windows only.
bool savePdfSupported(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.windows;

String unavailableReasonFor(TargetPlatform platform) => switch (platform) {
      TargetPlatform.windows =>
        'Documents are rendered with the Microsoft Edge WebView2 Runtime, which is not installed. '
            'Install it from https://developer.microsoft.com/microsoft-edge/webview2/ and restart MDViewer. '
            'Showing plain text for now.',
      TargetPlatform.linux =>
        'Documents are rendered with WPE WebKit, which could not be started. Install your '
            "distribution's WPE WebKit package and restart MDViewer. Showing plain text for now.",
      _ => 'The document renderer could not start. Showing plain text for now.',
    };
