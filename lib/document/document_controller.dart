import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../renderer/renderer_controller.dart';
import '../workspace/file_source.dart';
import '../workspace/workspace.dart';
import 'external_launcher.dart';
import 'link_router.dart';
import 'text_decoding.dart';

enum DocumentStatus { empty, loading, ready, error }

const Map<String, String> _imageMimeTypes = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.bmp': 'image/bmp',
  '.ico': 'image/x-icon',
  '.avif': 'image/avif',
};

String? imageMimeType(String path) => _imageMimeTypes[p.extension(path).toLowerCase()];

/// The open workspace and document: loading, history, link routing,
/// resource resolution and live reload. UI listens to this.
class DocumentController extends ChangeNotifier {
  DocumentController({
    required this.renderer,
    required this.launcher,
    this.reloadDebounce = const Duration(milliseconds: 200),
    this.largeFileBytes = 5 * 1024 * 1024,
    this.hugeFileBytes = 50 * 1024 * 1024,
  }) {
    renderer.resourceResolver = resolveResource;
    _subscriptions.addAll([
      renderer.headings.listen(_onHeadings),
      renderer.linkClicks.listen((href) => unawaited(handleLink(href))),
      renderer.rendered.listen((_) => _onRendered()),
      renderer.renderErrors.listen(_onRenderError),
    ]);
  }

  final RendererController renderer;
  final ExternalLauncher launcher;
  final Duration reloadDebounce;
  final int largeFileBytes;
  final int hugeFileBytes;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  final StreamController<String> _messages = StreamController<String>.broadcast();
  final List<String> _back = [];
  final List<String> _forward = [];

  Workspace? _workspace;
  String? _path;
  DocumentStatus _status = DocumentStatus.empty;
  String? _error;
  String? _text;
  DateTime? _modified;
  bool _fileMissing = false;
  bool _heavyFeatures = true;
  bool _tooLarge = false;
  bool _showPlainText = false;
  List<Heading> _headings = const [];
  bool _dark = false;
  double _fontScale = 1.0;
  String? _pendingFragment;
  int _loadGeneration = 0;
  String? _watchedPath;
  StreamSubscription<void>? _watchSubscription;
  Timer? _debounce;

  Workspace? get workspace => _workspace;
  String? get currentPath => _path;
  DocumentStatus get status => _status;
  String? get errorMessage => _error;
  String? get text => _text;
  bool get fileMissing => _fileMissing;
  bool get heavyFeatures => _heavyFeatures;
  bool get tooLarge => _tooLarge;
  bool get showPlainText => _showPlainText;
  List<Heading> get headings => _headings;
  bool get canGoBack => _back.isNotEmpty && _path != null;
  bool get canGoForward => _forward.isNotEmpty && _path != null;
  bool get dark => _dark;
  double get fontScale => _fontScale;

  /// Transient user-facing messages (shown as snackbars).
  Stream<String> get messages => _messages.stream;

  String get title {
    final path = _path;
    final workspace = _workspace;
    if (path != null && workspace != null) return workspace.source.pathContext.basename(path);
    return workspace?.displayName ?? 'MDViewer';
  }

  Future<void> openWorkspace(Workspace workspace, {String? file}) async {
    _workspace = workspace;
    _back.clear();
    _forward.clear();
    _stopWatching();
    final target = file ?? await workspace.defaultDocument();
    if (target == null) {
      _loadGeneration++;
      _path = null;
      _text = null;
      _error = null;
      _headings = const [];
      _status = DocumentStatus.empty;
      notifyListeners();
      return;
    }
    await _load(target);
  }

  Future<void> open(String path, {String? fragment}) async {
    if (path == _path && _status == DocumentStatus.ready) {
      if (fragment != null) await renderer.scrollToHeading(fragment);
      return;
    }
    final current = _path;
    if (current != null) {
      _back.add(current);
      _forward.clear();
    }
    await _load(path, fragment: fragment);
  }

  Future<void> goBack() async {
    final current = _path;
    if (_back.isEmpty || current == null) return;
    _forward.add(current);
    await _load(_back.removeLast());
  }

  Future<void> goForward() async {
    final current = _path;
    if (_forward.isEmpty || current == null) return;
    _back.add(current);
    await _load(_forward.removeLast());
  }

  Future<void> reload() async {
    final path = _path;
    if (path != null) await _load(path, preserveScroll: _status == DocumentStatus.ready);
  }

  /// Re-reads the document if it changed on disk, or marks it missing if it
  /// was deleted (keeping the last render on screen).
  Future<void> checkForChanges() async {
    final workspace = _workspace;
    final path = _path;
    if (workspace == null || path == null) return;
    final stat = await workspace.source.stat(path);
    if (path != _path) return;
    if (stat == null) {
      if (!_fileMissing) {
        _fileMissing = true;
        notifyListeners();
      }
      return;
    }
    if (_fileMissing || _status == DocumentStatus.error || stat.modified != _modified) {
      await _load(path, preserveScroll: _status == DocumentStatus.ready);
    }
  }

  Future<void> handleLink(String href) async {
    final workspace = _workspace;
    final path = _path;
    if (workspace == null || path == null) return;
    final target = LinkRouter(workspace).classify(href, currentFile: path);
    switch (target) {
      case InDocumentAnchor(:final fragment):
        await renderer.scrollToHeading(fragment);
      case WorkspaceDocument(path: final document, :final fragment):
        await open(document, fragment: fragment);
      case ExternalLink(:final uri):
        if (!await launcher.launchUri(uri)) _messages.add('Could not open $uri');
      case WorkspaceFile(path: final file):
        final name = workspace.source.pathContext.basename(file);
        if (!launcher.canOpenFiles) {
          _messages.add('Opening $name is not supported on this device');
        } else if (!await launcher.openFile(file)) {
          _messages.add('Could not open $name');
        }
      case UnsupportedLink(href: final unsupported):
        _messages.add('Unsupported link: $unsupported');
    }
  }

  Future<String?> resolveResource(String reference) async {
    final workspace = _workspace;
    final path = _path;
    if (workspace == null || path == null) return null;
    final clean = reference.split('#').first.split('?').first;
    final resolved = workspace.resolve(path, clean);
    if (resolved == null) return null;
    final mime = imageMimeType(resolved);
    if (mime == null) return null;
    try {
      final bytes = await workspace.source.readBytes(resolved);
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } on FileSourceException {
      return null;
    }
  }

  void setAppearance({required bool dark, required double fontScale}) {
    if (dark == _dark && fontScale == _fontScale) return;
    _dark = dark;
    _fontScale = fontScale;
    if (_status == DocumentStatus.ready && _text != null && !_tooLarge && !_showPlainText) {
      unawaited(() async {
        final y = await renderer.scrollPosition();
        await _render(restoreScrollY: y);
      }());
    }
  }

  void showAsPlainText() {
    if (_text == null) return;
    _showPlainText = true;
    _status = DocumentStatus.ready;
    _error = null;
    notifyListeners();
  }

  Future<void> _load(String path, {String? fragment, bool preserveScroll = false}) async {
    final workspace = _workspace;
    if (workspace == null) return;
    final generation = ++_loadGeneration;
    final scrollY = preserveScroll ? await renderer.scrollPosition() : null;
    if (generation != _loadGeneration) return;
    final samePath = path == _path;
    _path = path;
    _status = DocumentStatus.loading;
    _error = null;
    _fileMissing = false;
    _showPlainText = false;
    if (!samePath) _headings = const [];
    notifyListeners();
    _watch(path);
    try {
      final stat = await workspace.source.stat(path);
      if (generation != _loadGeneration) return;
      if (stat == null) throw FileSourceException(path, 'File not found: $path');
      final bytes = await workspace.source.readBytes(path);
      if (generation != _loadGeneration) return;
      _modified = stat.modified;
      _tooLarge = stat.size > hugeFileBytes;
      _heavyFeatures = stat.size <= largeFileBytes;
      _text = decodeText(bytes);
      _pendingFragment = fragment;
      _status = DocumentStatus.ready;
      notifyListeners();
      if (!_tooLarge) await _render(restoreScrollY: scrollY);
    } on FileSourceException catch (e) {
      if (generation != _loadGeneration) return;
      _text = null;
      _status = DocumentStatus.error;
      _error = e.message;
      notifyListeners();
    }
  }

  Future<void> _render({double? restoreScrollY}) => renderer.render(
        _text!,
        RenderOptions(
          dark: _dark,
          fontScale: _fontScale,
          heavyFeatures: _heavyFeatures,
          restoreScrollY: restoreScrollY,
        ),
      );

  void _watch(String path) {
    if (_watchedPath == path) return;
    _stopWatching();
    final source = _workspace!.source;
    if (!source.supportsWatch) return;
    _watchedPath = path;
    _watchSubscription = source.watch(path).listen((_) {
      _debounce?.cancel();
      _debounce = Timer(reloadDebounce, () => unawaited(checkForChanges()));
    });
  }

  void _stopWatching() {
    _debounce?.cancel();
    _debounce = null;
    unawaited(_watchSubscription?.cancel());
    _watchSubscription = null;
    _watchedPath = null;
  }

  void _onHeadings(List<Heading> headings) {
    _headings = headings;
    notifyListeners();
  }

  void _onRendered() {
    final fragment = _pendingFragment;
    _pendingFragment = null;
    if (fragment != null) unawaited(renderer.scrollToHeading(fragment));
  }

  void _onRenderError(String message) {
    _status = DocumentStatus.error;
    _error = 'The document could not be rendered: $message';
    notifyListeners();
  }

  @override
  void dispose() {
    _stopWatching();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_messages.close());
    super.dispose();
  }
}
