import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';
import 'package:mdviewer/renderer/webview_renderer.dart';

void main() {
  test('starts loading and reports print support by platform', () {
    final mac = WebViewRendererController(platform: TargetPlatform.macOS);
    final linux = WebViewRendererController(platform: TargetPlatform.linux);
    expect(mac.status.value, RendererStatus.loading);
    expect(mac.canPrint, isTrue);
    expect(linux.canPrint, isFalse);
    mac.dispose();
    linux.dispose();
  });

  test('marks itself unavailable if the page never becomes ready', () async {
    final renderer = WebViewRendererController(
      platform: TargetPlatform.windows,
      readyTimeout: const Duration(milliseconds: 10),
    );
    renderer.startReadyTimer();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(renderer.status.value, RendererStatus.unavailable);
    expect(renderer.unavailableReason, contains('WebView2'));
    renderer.dispose();
  });

  test('calls before the page is ready are safe no-ops', () async {
    final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
    await renderer.render('# Hi', const RenderOptions(dark: false, fontScale: 1, heavyFeatures: true));
    await renderer.find('x');
    expect(await renderer.scrollPosition(), 0);
    renderer.dispose();
  });
}
