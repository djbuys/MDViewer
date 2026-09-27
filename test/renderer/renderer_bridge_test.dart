import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/renderer/renderer_bridge.dart';

void main() {
  group('RendererNavigationPolicy', () {
    const bundled = 'file:///app/flutter_assets/assets/renderer/index.html';

    test('before the renderer loads, only a bundled file: renderer page is accepted', () {
      final policy = RendererNavigationPolicy();
      expect(policy.allowNavigation(Uri.parse('https://evil.example/assets/renderer/index.html')), isFalse);
      expect(policy.allowNavigation(Uri.parse('https://localhost/assets/renderer/index.html')), isFalse);
      expect(policy.allowNavigation(Uri.parse('https://example.com/')), isFalse);
      expect(policy.allowNavigation(Uri.parse('file:///etc/passwd')), isFalse);
      expect(policy.allowNavigation(null), isFalse);
      expect(policy.rendererUrl, isNull);

      expect(policy.allowNavigation(Uri.parse(bundled)), isTrue);
      expect(policy.rendererUrl, Uri.parse(bundled));
    });

    test('once known, only the exact renderer URL is allowed (fragment ignored)', () {
      final policy = RendererNavigationPolicy()..allowNavigation(Uri.parse(bundled));
      expect(policy.allowNavigation(Uri.parse(bundled)), isTrue);
      expect(policy.allowNavigation(Uri.parse('$bundled#section')), isTrue);
      expect(policy.allowNavigation(Uri.parse('file:///Users/me/notes/assets/renderer/index.html')), isFalse);
      expect(policy.allowNavigation(Uri.parse('https://evil.example/assets/renderer/index.html')), isFalse);
      expect(policy.allowNavigation(Uri.parse('$bundled?x=1')), isFalse);
      expect(policy.allowNavigation(Uri.parse('file:///app/flutter_assets/assets/renderer/other.html')), isFalse);
      expect(policy.rendererUrl, Uri.parse(bundled));
    });

    test('percent-encoding differences do not matter', () {
      final policy = RendererNavigationPolicy()
        ..allowNavigation(Uri.parse('file:///C:/Program%20Files/MDViewer/data/flutter_assets/assets/renderer/index.html'));
      expect(
        policy.isRendererUrl(Uri.parse('file:///C:/Program Files/MDViewer/data/flutter_assets/assets/renderer/index.html')),
        isTrue,
      );
    });

    test('isRendererUrl never captures and requires a known renderer URL', () {
      final policy = RendererNavigationPolicy();
      expect(policy.isRendererUrl(Uri.parse(bundled)), isFalse);
      expect(policy.rendererUrl, isNull);
      policy.allowNavigation(Uri.parse(bundled));
      expect(policy.isRendererUrl(Uri.parse('$bundled#a')), isTrue);
      expect(policy.isRendererUrl(null), isFalse);
    });

    test('isRendererLoad matches the bundled page before and after capture', () {
      final policy = RendererNavigationPolicy();
      expect(policy.isRendererLoad(Uri.parse(bundled)), isTrue);
      expect(policy.isRendererLoad(Uri.parse('https://evil.example/assets/renderer/index.html')), isFalse);
      policy.allowNavigation(Uri.parse(bundled));
      expect(policy.isRendererLoad(Uri.parse('file:///elsewhere/assets/renderer/index.html')), isFalse);
      expect(policy.isRendererLoad(Uri.parse(bundled)), isTrue);
    });

    test('JS handler calls are accepted only from the renderer main frame', () {
      final policy = RendererNavigationPolicy();
      expect(policy.acceptsHandlerCall(isMainFrame: true, requestUrl: Uri.parse(bundled)), isFalse);
      policy.allowNavigation(Uri.parse(bundled));
      expect(policy.acceptsHandlerCall(isMainFrame: true, requestUrl: Uri.parse(bundled)), isTrue);
      expect(policy.acceptsHandlerCall(isMainFrame: true, requestUrl: Uri.parse('$bundled#x')), isTrue);
      expect(policy.acceptsHandlerCall(isMainFrame: false, requestUrl: Uri.parse(bundled)), isFalse);
      expect(
        policy.acceptsHandlerCall(isMainFrame: true, requestUrl: Uri.parse('https://evil.example/assets/renderer/index.html')),
        isFalse,
      );
      expect(policy.acceptsHandlerCall(isMainFrame: true, requestUrl: null), isFalse);
    });
  });

  test('the JS bridge is limited to local file pages', () {
    expect(bridgeOriginAllowList(TargetPlatform.macOS), {r'^(file://|null)$'});
    expect(bridgeOriginAllowList(TargetPlatform.iOS), {r'^(file://|null)$'});
    expect(bridgeOriginAllowList(TargetPlatform.windows), {r'^(file://|null)$'});
    expect(bridgeOriginAllowList(TargetPlatform.android), {'file://'});
  });

  test('jsCall JSON-encodes arguments and never returns a value', () {
    expect(jsCall('findNext'), 'window.mdv.findNext(); null');
    expect(
      jsCall('render', ['a "quote"\n</script>', {'theme': 'dark'}]),
      r'window.mdv.render("a \"quote\"\n</script>", {"theme":"dark"}); null',
    );
  });

  test('print support per platform', () {
    expect(printModeFor(TargetPlatform.macOS), PrintMode.native);
    expect(printModeFor(TargetPlatform.iOS), PrintMode.native);
    expect(printModeFor(TargetPlatform.android), PrintMode.native);
    expect(printModeFor(TargetPlatform.windows), PrintMode.javascript);
    expect(printModeFor(TargetPlatform.linux), PrintMode.unsupported);
  });

  test('unavailability reasons name what to install', () {
    expect(unavailableReasonFor(TargetPlatform.windows), contains('WebView2'));
    expect(unavailableReasonFor(TargetPlatform.linux), contains('WPE WebKit'));
    expect(unavailableReasonFor(TargetPlatform.macOS), isNotEmpty);
  });
}
