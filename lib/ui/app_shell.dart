import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../platform/document_access.dart';
import '../search/find_bar.dart';
import '../search/folder_search_dialog.dart';
import '../settings/settings.dart';
import 'app_actions.dart';
import 'document_commands.dart';
import 'document_pane.dart';
import 'file_sidebar.dart';
import 'open_commands.dart';
import 'title_bar.dart';
import 'toc_panel.dart';

const double wideLayoutBreakpoint = 900;

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> implements AppActionHost {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  AppLifecycleListener? _lifecycle;
  StreamSubscription<String>? _messages;
  StreamSubscription<IncomingDocument>? _incoming;
  AppServices? _services;
  bool _finding = false;
  String _findQuery = '';
  int _findSession = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(services, _services)) return;
    _services = services;
    unawaited(_messages?.cancel());
    _messages = services.document.messages.listen((message) {
      if (mounted) showMessage(context, message);
    });
    _lifecycle?.dispose();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(services.document.checkForChanges()));
    unawaited(_incoming?.cancel());
    _incoming = services.incoming.documents.listen((document) => unawaited(services.actions.openIncoming(document)));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await services.incoming.takeInitial();
      if (initial.isNotEmpty) await services.actions.openIncoming(initial.first);
    });
  }

  @override
  void dispose() {
    unawaited(_messages?.cancel());
    unawaited(_incoming?.cancel());
    _lifecycle?.dispose();
    super.dispose();
  }

  void _syncAppearance(BuildContext context, AppServices services) {
    final settings = services.settings;
    final dark = switch (settings.themeMode) {
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
    };
    // Idempotent and does not notify listeners, so safe to call from build.
    services.document.setAppearance(dark: dark, fontScale: settings.fontScale);
  }

  @override
  void openFind() => _openFind();

  void _openFind([String query = '']) => setState(() {
        _finding = true;
        _findQuery = query;
        _findSession++;
      });

  void _closeFind() => setState(() => _finding = false);

  @override
  Future<void> searchFolder() async {
    final services = AppScope.of(context);
    final workspace = services.document.workspace;
    if (workspace == null || !workspace.isFolder) return;
    final result = await FolderSearchDialog.show(context, workspace);
    if (result == null || !mounted) return;
    final (hit, query) = result;
    await services.document.open(hit.path);
    if (mounted) _openFind(query);
  }

  @override
  Future<void> printDocument() async {
    final services = AppScope.of(context);
    try {
      await services.renderer.print();
    } catch (e) {
      if (mounted) showMessage(context, 'Printing failed: $e');
    }
  }

  @override
  void openContentsDrawer() => _scaffoldKey.currentState?.openEndDrawer();

  @override
  final GlobalKey shareAnchor = GlobalKey(debugLabel: 'share');
  final GlobalKey _titleBarKey = GlobalKey(debugLabel: 'title bar');

  /// Keeps the document pane (and its WebView) alive when the layout
  /// changes around it: wide/narrow switches, panels appearing.
  final GlobalKey _documentPaneKey = GlobalKey(debugLabel: 'document');

  @override
  Future<void> savePdf() => savePdfCommand(context, AppScope.of(context));

  @override
  Future<void> shareDocument() {
    // The share button when it is in the title bar, else the title bar
    // (the button is in the overflow menu).
    final box = (shareAnchor.currentContext ?? _titleBarKey.currentContext)?.findRenderObject();
    final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    return shareDocumentCommand(context, AppScope.of(context), origin: origin);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.settings, services.document, services.recents]),
      builder: (context, _) {
        _syncAppearance(context, services);
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= wideLayoutBreakpoint;
            final platform = defaultTargetPlatform;
            final actions = buildAppActions(
              context: context,
              services: services,
              host: this,
              wide: wide,
              platform: platform,
            );
            Widget shell = _buildScaffold(context, services, actions, wide: wide, platform: platform);
            shell = CallbackShortcuts(
              bindings: shortcutBindings(actions),
              child: Focus(autofocus: true, child: shell),
            );
            if (_isDesktop) {
              shell = DropTarget(
                onDragDone: (details) {
                  if (details.files.isEmpty) return;
                  unawaited(services.actions.openIncoming(IncomingDocument(path: details.files.first.path)));
                },
                child: shell,
              );
            }
            if (!kIsWeb && platform == TargetPlatform.macOS) {
              shell = PlatformMenuBar(menus: macMenus(actions), child: shell);
            }
            return shell;
          },
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AppServices services,
    List<AppAction> actions, {
    required bool wide,
    required TargetPlatform platform,
  }) {
    final document = services.document;
    final settings = services.settings;
    final hasFolder = document.workspace?.isFolder ?? false;
    final hasHeadings = document.headings.isNotEmpty;
    final body = Column(
      children: [
        if (_finding)
          FindBar(
            key: ValueKey('find-$_findSession'),
            renderer: services.renderer,
            onClose: _closeFind,
            initialQuery: _findQuery,
          ),
        Expanded(child: DocumentPane(key: _documentPaneKey)),
      ],
    );
    final filesDrawer = !wide && hasFolder;
    return Scaffold(
      key: _scaffoldKey,
      appBar: MdTitleBar(
        key: _titleBarKey,
        title: document.title,
        actions: actions,
        platform: platform,
        wide: wide,
        leading: filesDrawer
            ? IconButton(
                key: const Key('action-files'),
                tooltip: 'Files',
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : null,
      ),
      drawer: filesDrawer
          ? Drawer(child: SafeArea(child: FileSidebar(onOpened: () => _scaffoldKey.currentState?.closeDrawer())))
          : null,
      endDrawer: !wide && hasHeadings
          ? Drawer(child: SafeArea(child: TocPanel(onSelected: () => _scaffoldKey.currentState?.closeEndDrawer())))
          : null,
      body: wide
          ? Row(
              children: [
                if (hasFolder && settings.sidebarVisible) ...[
                  const SizedBox(width: 280, child: FileSidebar()),
                  const VerticalDivider(width: 1),
                ],
                Expanded(child: body),
                if (hasHeadings && settings.tocVisible) ...[
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 240, child: TocPanel()),
                ],
              ],
            )
          : body,
    );
  }
}
