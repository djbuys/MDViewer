import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'renderer_bridge.dart';
import 'renderer_controller.dart';

/// Hosts the bundled JS renderer in a WebView. Only one view should be
/// mounted per controller; keep it mounted for the app's lifetime.
class WebViewRendererController implements RendererController {
  WebViewRendererController({TargetPlatform? platform, this.readyTimeout = const Duration(seconds: 15)})
      : _platform = platform ?? defaultTargetPlatform;

  final TargetPlatform _platform;
  final Duration readyTimeout;

  final ValueNotifier<RendererStatus> _status = ValueNotifier(RendererStatus.loading);
  final _headings = StreamController<List<Heading>>.broadcast();
  final _links = StreamController<String>.broadcast();
  final _finds = StreamController<FindResult>.broadcast();
  final _rendered = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();

  InAppWebViewController? _web;
  final RendererNavigationPolicy _policy = RendererNavigationPolicy();
  ResourceResolver? _resolver;
  Timer? _readyTimer;
  String? _reason;
  ({String markdown, RenderOptions options})? _pending;

  @override
  ValueListenable<RendererStatus> get status => _status;
  @override
  String? get unavailableReason => _reason;
  @override
  Stream<List<Heading>> get headings => _headings.stream;
  @override
  Stream<String> get linkClicks => _links.stream;
  @override
  Stream<FindResult> get findResults => _finds.stream;
  @override
  Stream<void> get rendered => _rendered.stream;
  @override
  Stream<String> get renderErrors => _errors.stream;
  @override
  set resourceResolver(ResourceResolver? resolver) => _resolver = resolver;
  @override
  bool get canPrint => printModeFor(_platform) != PrintMode.unsupported;

  @override
  Widget buildView(BuildContext context) => _RendererView(controller: this);

  void startReadyTimer() {
    _readyTimer?.cancel();
    _readyTimer = Timer(readyTimeout, () {
      if (_status.value == RendererStatus.loading) markUnavailable();
    });
  }

  void markUnavailable() {
    _readyTimer?.cancel();
    _reason = unavailableReasonFor(_platform);
    _status.value = RendererStatus.unavailable;
  }

  /// Evaluates JavaScript in the renderer page. Integration tests only.
  @visibleForTesting
  Future<Object?> debugEvaluate(String source) async => _web?.evaluateJavascript(source: source);

  /// Handler calls are served only for the renderer page's main frame.
  bool _acceptsCall(JavaScriptHandlerFunctionData data) =>
      _policy.acceptsHandlerCall(isMainFrame: data.isMainFrame, requestUrl: data.requestUrl);

  void _attach(InAppWebViewController web) {
    _web = web;
    web.addJavaScriptHandler(
      handlerName: 'headingsChanged',
      callback: (JavaScriptHandlerFunctionData data) {
        if (!_acceptsCall(data)) return null;
        final list = data.args.isEmpty ? const <Object?>[] : data.args.first as List<Object?>;
        _headings.add([for (final item in list) Heading.fromJson(item! as Map<dynamic, dynamic>)]);
        return null;
      },
    );
    web.addJavaScriptHandler(
      handlerName: 'linkClicked',
      callback: (JavaScriptHandlerFunctionData data) {
        if (!_acceptsCall(data)) return null;
        _links.add((data.args.first as Map<dynamic, dynamic>)['href'] as String);
        return null;
      },
    );
    web.addJavaScriptHandler(
      handlerName: 'findResult',
      callback: (JavaScriptHandlerFunctionData data) {
        if (!_acceptsCall(data)) return null;
        _finds.add(FindResult.fromJson(data.args.first as Map<dynamic, dynamic>));
        return null;
      },
    );
    web.addJavaScriptHandler(
      handlerName: 'rendered',
      callback: (JavaScriptHandlerFunctionData data) {
        if (!_acceptsCall(data)) return null;
        _rendered.add(null);
        return null;
      },
    );
    web.addJavaScriptHandler(
      handlerName: 'renderError',
      callback: (JavaScriptHandlerFunctionData data) {
        if (!_acceptsCall(data)) return null;
        _errors.add((data.args.first as Map<dynamic, dynamic>)['message'] as String);
        return null;
      },
    );
    web.addJavaScriptHandler(
      handlerName: 'resolveResource',
      callback: (JavaScriptHandlerFunctionData data) async {
        if (!_acceptsCall(data)) return null;
        final path = (data.args.first as Map<dynamic, dynamic>)['path'] as String;
        return await _resolver?.call(path);
      },
    );
  }

  Future<void> _onLoadStop(InAppWebViewController web, Uri? url) async {
    if (url != null && !_policy.allowNavigation(url)) return;
    if (_status.value != RendererStatus.loading) return;
    Object? hasApi;
    try {
      hasApi = await web.evaluateJavascript(source: "typeof window.mdv === 'object'");
    } catch (_) {
      hasApi = false;
    }
    if (hasApi != true) {
      markUnavailable();
      return;
    }
    _readyTimer?.cancel();
    _status.value = RendererStatus.ready;
    await _flush();
  }

  Future<Object?> _eval(String source) async {
    final web = _web;
    if (web == null || _status.value != RendererStatus.ready) return null;
    try {
      return await web.evaluateJavascript(source: source);
    } catch (e) {
      debugPrint('Renderer call failed: $e');
      return null;
    }
  }

  Future<void> _flush() async {
    final pending = _pending;
    if (pending == null || _web == null || _status.value != RendererStatus.ready) return;
    _pending = null;
    await _eval(jsCall('render', [pending.markdown, pending.options.toJson()]));
  }

  @override
  Future<void> render(String markdown, RenderOptions options) async {
    _pending = (markdown: markdown, options: options);
    await _flush();
  }

  @override
  Future<void> scrollToHeading(String id) => _eval(jsCall('scrollToHeading', [id]));

  @override
  Future<double> scrollPosition() async {
    final value = await _eval('window.scrollY');
    return value is num ? value.toDouble() : 0;
  }

  @override
  Future<void> find(String query) => _eval(jsCall('find', [query]));
  @override
  Future<void> findNext() => _eval(jsCall('findNext'));
  @override
  Future<void> findPrevious() => _eval(jsCall('findPrev'));
  @override
  Future<void> clearFind() => _eval(jsCall('clearFind'));

  @override
  Future<void> print() async {
    switch (printModeFor(_platform)) {
      case PrintMode.native:
        await _web?.printCurrentPage();
      case PrintMode.javascript:
        await _eval(jsCall('print'));
      case PrintMode.unsupported:
        break;
    }
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _status.dispose();
    _headings.close();
    _links.close();
    _finds.close();
    _rendered.close();
    _errors.close();
  }
}

class _RendererView extends StatefulWidget {
  const _RendererView({required this.controller});

  final WebViewRendererController controller;

  @override
  State<_RendererView> createState() => _RendererViewState();
}

class _RendererViewState extends State<_RendererView> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkAvailability());
  }

  Future<void> _checkAvailability() async {
    final controller = widget.controller;
    if (controller._platform == TargetPlatform.windows) {
      String? version;
      try {
        version = await WebViewEnvironment.getAvailableVersion();
      } catch (_) {
        version = null;
      }
      if (version == null) {
        controller.markUnavailable();
        return;
      }
    }
    if (!mounted) return;
    controller.startReadyTimer();
    setState(() => _checked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.expand();
    final controller = widget.controller;
    return InAppWebView(
      initialFile: rendererAssetPath,
      initialSettings: InAppWebViewSettings(
        useShouldOverrideUrlLoading: true,
        javaScriptEnabled: true,
        transparentBackground: true,
        supportZoom: false,
        isInspectable: kDebugMode,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        mediaPlaybackRequiresUserGesture: true,
        javaScriptBridgeForMainFrameOnly: true,
        javaScriptBridgeOriginAllowList: bridgeOriginAllowList(controller._platform),
      ),
      onWebViewCreated: controller._attach,
      shouldOverrideUrlLoading: (web, action) async => controller._policy.allowNavigation(action.request.url)
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
      // Android does not route the initial load through shouldOverrideUrlLoading.
      onLoadStart: (web, url) => controller._policy.allowNavigation(url),
      onLoadStop: controller._onLoadStop,
      onReceivedError: (web, request, error) {
        if ((request.isForMainFrame ?? true) && controller._policy.isRendererLoad(request.url)) {
          controller.markUnavailable();
        }
      },
      onConsoleMessage: kDebugMode ? (web, message) => debugPrint('[renderer] ${message.message}') : null,
    );
  }
}
