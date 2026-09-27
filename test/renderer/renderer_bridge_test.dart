import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/renderer/renderer_bridge.dart';

void main() {
  test('only the renderer page itself may load', () {
    expect(isRendererPage(Uri.parse('file:///app/flutter_assets/assets/renderer/index.html')), isTrue);
    expect(isRendererPage(Uri.parse('https://localhost/assets/renderer/index.html')), isTrue);
    expect(isRendererPage(Uri.parse('https://example.com/')), isFalse);
    expect(isRendererPage(Uri.parse('file:///etc/passwd')), isFalse);
    expect(isRendererPage(null), isFalse);
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
