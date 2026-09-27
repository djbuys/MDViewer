import 'dart:convert';

import 'package:flutter/foundation.dart';

const String rendererAssetPath = 'assets/renderer/index.html';

/// The WebView may only ever show the bundled renderer page.
bool isRendererPage(Uri? uri) => uri != null && uri.path.endsWith(rendererAssetPath);

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
