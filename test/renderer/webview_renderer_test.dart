import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/renderer/renderer_bridge.dart';
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

  group('page loads', () {
    late List<String> calls;
    late int contentNodes;
    late bool hasApi;

    Future<Object?> evaluate(String source) async {
      calls.add(source);
      if (source.contains('typeof window.mdv')) return hasApi;
      if (source.contains('childNodes.length')) return contentNodes;
      return null;
    }

    setUp(() {
      calls = [];
      contentNodes = 0;
      hasApi = true;
    });

    const options = RenderOptions(dark: true, fontScale: 1.2, heavyFeatures: true, restoreScrollY: 40);
    final replayed = jsCall('render', [
      '# A',
      const RenderOptions(dark: true, fontScale: 1.2, heavyFeatures: true).toJson(),
    ]);

    test('the first load makes the renderer ready and flushes a pending render', () async {
      final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
      addTearDown(renderer.dispose);
      await renderer.render('# A', options);
      await renderer.debugHandlePageLoaded(evaluate);
      expect(renderer.status.value, RendererStatus.ready);
      expect(calls.last, jsCall('render', ['# A', options.toJson()]));
    });

    test('a reload while ready replays the last render without the scroll restore', () async {
      final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
      addTearDown(renderer.dispose);
      await renderer.debugHandlePageLoaded(evaluate);
      await renderer.render('# A', options);
      expect(calls.last, jsCall('render', ['# A', options.toJson()]));

      calls.clear();
      await renderer.debugHandlePageLoaded(evaluate);
      expect(calls.last, replayed);
      expect(renderer.status.value, RendererStatus.ready);
    });

    test('a repeated load event on a page that still shows content does not re-render', () async {
      final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
      addTearDown(renderer.dispose);
      await renderer.debugHandlePageLoaded(evaluate);
      await renderer.render('# A', options);
      contentNodes = 3;
      calls.clear();
      await renderer.debugHandlePageLoaded(evaluate);
      expect(calls.where((c) => c.contains('mdv.render')), isEmpty);
    });

    test('a reload before anything was rendered sends nothing', () async {
      final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
      addTearDown(renderer.dispose);
      await renderer.debugHandlePageLoaded(evaluate);
      await renderer.debugHandlePageLoaded(evaluate);
      expect(calls.where((c) => c.contains('mdv.render')), isEmpty);
    });

    group('a foreign main-frame page', () {
      final rendererUrl = Uri.parse('file:///app/flutter_assets/assets/renderer/index.html');
      final evil = Uri.parse('https://evil.example/page');
      late int reloads;
      Future<void> reload() async => reloads++;

      setUp(() => reloads = 0);

      test('is replaced by the renderer page, which then replays the last render', () async {
        final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
        addTearDown(renderer.dispose);
        await renderer.debugHandleLoadStop(rendererUrl, evaluate: evaluate, reloadRenderer: reload);
        expect(renderer.status.value, RendererStatus.ready);
        await renderer.render('# A', options);
        expect(reloads, 0);

        calls.clear();
        await renderer.debugHandleLoadStop(evil, evaluate: evaluate, reloadRenderer: reload);
        expect(reloads, 1);
        expect(renderer.status.value, RendererStatus.loading);
        expect(calls, isEmpty, reason: 'nothing is evaluated in the foreign page');

        await renderer.debugHandleLoadStop(rendererUrl, evaluate: evaluate, reloadRenderer: reload);
        expect(renderer.status.value, RendererStatus.ready);
        expect(calls.last, replayed);
      });

      test('is replaced even before the renderer page was ever captured', () async {
        final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
        addTearDown(renderer.dispose);
        await renderer.debugHandleLoadStop(evil, evaluate: evaluate, reloadRenderer: reload);
        expect(reloads, 1);
        expect(calls, isEmpty);
        await renderer.debugHandleLoadStop(rendererUrl, evaluate: evaluate, reloadRenderer: reload);
        expect(renderer.status.value, RendererStatus.ready);
      });

      test('that keeps coming back makes the renderer unavailable instead of looping', () async {
        final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
        addTearDown(renderer.dispose);
        await renderer.debugHandleLoadStop(rendererUrl, evaluate: evaluate, reloadRenderer: reload);
        for (var i = 0; i < 5; i++) {
          await renderer.debugHandleLoadStop(evil, evaluate: evaluate, reloadRenderer: reload);
        }
        expect(reloads, 3);
        expect(renderer.status.value, RendererStatus.unavailable);
      });
    });

    test('a page without the renderer API makes the renderer unavailable', () async {
      final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
      addTearDown(renderer.dispose);
      hasApi = false;
      await renderer.debugHandlePageLoaded(evaluate);
      expect(renderer.status.value, RendererStatus.unavailable);
    });
  });

  test('calls before the page is ready are safe no-ops', () async {
    final renderer = WebViewRendererController(platform: TargetPlatform.macOS);
    await renderer.render('# Hi', const RenderOptions(dark: false, fontScale: 1, heavyFeatures: true));
    await renderer.find('x');
    expect(await renderer.scrollPosition(), 0);
    renderer.dispose();
  });
}
