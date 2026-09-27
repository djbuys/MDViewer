import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../platform/document_access.dart';
import '../search/find_bar.dart';
import '../search/folder_search_dialog.dart';
import '../settings/recents.dart';
import '../settings/settings.dart';
import 'document_pane.dart';
import 'file_sidebar.dart';
import 'open_commands.dart';
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

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  AppLifecycleListener? _lifecycle;
  StreamSubscription<String>? _messages;
  AppServices? _services;
  bool _sidebarVisible = true;
  bool _tocVisible = true;
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
  }

  @override
  void dispose() {
    unawaited(_messages?.cancel());
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

  void _openFind([String query = '']) => setState(() {
        _finding = true;
        _findQuery = query;
        _findSession++;
      });

  void _closeFind() => setState(() => _finding = false);

  Future<void> _searchFolder(AppServices services) async {
    final workspace = services.document.workspace;
    if (workspace == null || !workspace.isFolder) return;
    final result = await FolderSearchDialog.show(context, workspace);
    if (result == null || !mounted) return;
    final (hit, query) = result;
    await services.document.open(hit.path);
    if (mounted) _openFind(query);
  }

  Future<void> _print(AppServices services) async {
    try {
      await services.renderer.print();
    } catch (e) {
      if (mounted) showMessage(context, 'Printing failed: $e');
    }
  }

  String _themeLabel(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => 'Theme: follow system',
        AppThemeMode.light => 'Theme: light',
        AppThemeMode.dark => 'Theme: dark',
      };

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
            Widget shell = _buildScaffold(context, services, wide: wide);
            shell = _withShortcuts(services, shell);
            if (_isDesktop) {
              shell = DropTarget(
                onDragDone: (details) {
                  if (details.files.isEmpty) return;
                  unawaited(services.actions.openIncoming(IncomingDocument(path: details.files.first.path)));
                },
                child: shell,
              );
            }
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
              shell = _withMacMenus(services, shell);
            }
            return shell;
          },
        );
      },
    );
  }

  Widget _buildScaffold(BuildContext context, AppServices services, {required bool wide}) {
    final document = services.document;
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
        const Expanded(child: DocumentPane()),
      ],
    );
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(document.title, overflow: TextOverflow.ellipsis),
        actions: _actions(context, services, wide: wide),
      ),
      drawer: !wide && hasFolder
          ? Drawer(child: SafeArea(child: FileSidebar(onOpened: () => _scaffoldKey.currentState?.closeDrawer())))
          : null,
      endDrawer: !wide && hasHeadings
          ? Drawer(child: SafeArea(child: TocPanel(onSelected: () => _scaffoldKey.currentState?.closeEndDrawer())))
          : null,
      body: wide
          ? Row(
              children: [
                if (hasFolder && _sidebarVisible) ...[
                  const SizedBox(width: 280, child: FileSidebar()),
                  const VerticalDivider(width: 1),
                ],
                Expanded(child: body),
                if (hasHeadings && _tocVisible) ...[
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 240, child: TocPanel()),
                ],
              ],
            )
          : body,
    );
  }

  List<Widget> _actions(BuildContext context, AppServices services, {required bool wide}) {
    final document = services.document;
    final hasDocument = document.currentPath != null;
    final hasFolder = document.workspace?.isFolder ?? false;
    return [
      if (wide) ...[
        IconButton(
          key: const Key('action-back'),
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: document.canGoBack ? () => unawaited(document.goBack()) : null,
        ),
        IconButton(
          key: const Key('action-forward'),
          tooltip: 'Forward',
          icon: const Icon(Icons.arrow_forward),
          onPressed: document.canGoForward ? () => unawaited(document.goForward()) : null,
        ),
        IconButton(
          key: const Key('action-open-file'),
          tooltip: 'Open file',
          icon: const Icon(Icons.file_open_outlined),
          onPressed: () => openFileCommand(context),
        ),
        IconButton(
          key: const Key('action-open-folder'),
          tooltip: 'Open folder',
          icon: const Icon(Icons.folder_open_outlined),
          onPressed: () => openFolderCommand(context),
        ),
        if (services.recents.entries.isNotEmpty)
          PopupMenuButton<RecentEntry>(
            key: const Key('action-recents'),
            tooltip: 'Recent',
            icon: const Icon(Icons.history),
            onSelected: (entry) => openRecentCommand(context, entry),
            itemBuilder: (_) => [
              for (final entry in services.recents.entries)
                PopupMenuItem(value: entry, child: Text(entry.displayName)),
            ],
          ),
      ],
      if (hasDocument)
        IconButton(
          key: const Key('action-find'),
          tooltip: 'Find in document',
          icon: const Icon(Icons.search),
          onPressed: _openFind,
        ),
      if (wide && hasFolder)
        IconButton(
          key: const Key('action-search-folder'),
          tooltip: 'Search folder',
          icon: const Icon(Icons.manage_search),
          onPressed: () => unawaited(_searchFolder(services)),
        ),
      if (wide && hasFolder)
        IconButton(
          key: const Key('action-toggle-sidebar'),
          tooltip: _sidebarVisible ? 'Hide files' : 'Show files',
          icon: const Icon(Icons.vertical_split_outlined),
          onPressed: () => setState(() => _sidebarVisible = !_sidebarVisible),
        ),
      if (wide && document.headings.isNotEmpty)
        IconButton(
          key: const Key('action-toggle-toc'),
          tooltip: _tocVisible ? 'Hide contents' : 'Show contents',
          icon: const Icon(Icons.toc),
          onPressed: () => setState(() => _tocVisible = !_tocVisible),
        ),
      if (!wide && document.headings.isNotEmpty)
        IconButton(
          key: const Key('action-contents'),
          tooltip: 'Contents',
          icon: const Icon(Icons.toc),
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
      _overflowMenu(context, services, wide: wide),
    ];
  }

  Widget _overflowMenu(BuildContext context, AppServices services, {required bool wide}) {
    final document = services.document;
    final settings = services.settings;
    final hasFolder = document.workspace?.isFolder ?? false;
    return PopupMenuButton<VoidCallback>(
      key: const Key('action-more'),
      tooltip: 'More',
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        if (!wide) ...[
          PopupMenuItem(
            key: const Key('menu-open-file'),
            value: () => openFileCommand(context),
            child: const Text('Open file…'),
          ),
          PopupMenuItem(
            key: const Key('menu-open-folder'),
            value: () => openFolderCommand(context),
            child: const Text('Open folder…'),
          ),
          for (final entry in services.recents.entries.take(5))
            PopupMenuItem(
              value: () => openRecentCommand(context, entry),
              child: Text('Recent: ${entry.displayName}', overflow: TextOverflow.ellipsis),
            ),
          if (hasFolder)
            PopupMenuItem(
              value: () => unawaited(_searchFolder(services)),
              child: const Text('Search folder…'),
            ),
          if (document.canGoBack) PopupMenuItem(value: () => unawaited(document.goBack()), child: const Text('Back')),
          if (document.canGoForward)
            PopupMenuItem(value: () => unawaited(document.goForward()), child: const Text('Forward')),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(
          key: const Key('menu-theme'),
          value: () => unawaited(settings.cycleThemeMode()),
          child: Text(_themeLabel(settings.themeMode)),
        ),
        PopupMenuItem(
          key: const Key('menu-font-up'),
          value: () => unawaited(settings.increaseFontScale()),
          child: const Text('Larger text'),
        ),
        PopupMenuItem(
          key: const Key('menu-font-down'),
          value: () => unawaited(settings.decreaseFontScale()),
          child: const Text('Smaller text'),
        ),
        PopupMenuItem(
          key: const Key('menu-font-reset'),
          value: () => unawaited(settings.resetFontScale()),
          child: Text('Reset text size (${(settings.fontScale * 100).round()}%)'),
        ),
        if (document.currentPath != null) ...[
          PopupMenuItem(
            key: const Key('menu-reload'),
            value: () => unawaited(document.reload()),
            child: const Text('Reload'),
          ),
          if (services.renderer.canPrint)
            PopupMenuItem(
              key: const Key('menu-print'),
              value: () => unawaited(_print(services)),
              child: const Text('Print / Save as PDF…'),
            ),
        ],
      ],
    );
  }

  Widget _withShortcuts(AppServices services, Widget child) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
    SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, meta: mac, control: !mac, shift: shift);
    final document = services.document;
    return CallbackShortcuts(
      bindings: {
        key(LogicalKeyboardKey.keyO): () => openFileCommand(context),
        key(LogicalKeyboardKey.keyO, shift: true): () => openFolderCommand(context),
        key(LogicalKeyboardKey.keyF): () {
          if (document.currentPath != null) _openFind();
        },
        key(LogicalKeyboardKey.keyF, shift: true): () => unawaited(_searchFolder(services)),
        key(LogicalKeyboardKey.keyP): () {
          if (document.currentPath != null && services.renderer.canPrint) unawaited(_print(services));
        },
        key(LogicalKeyboardKey.keyR): () => unawaited(document.reload()),
        key(LogicalKeyboardKey.equal): () => unawaited(services.settings.increaseFontScale()),
        key(LogicalKeyboardKey.minus): () => unawaited(services.settings.decreaseFontScale()),
        key(LogicalKeyboardKey.digit0): () => unawaited(services.settings.resetFontScale()),
        key(LogicalKeyboardKey.bracketLeft): () => unawaited(document.goBack()),
        key(LogicalKeyboardKey.bracketRight): () => unawaited(document.goForward()),
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  /// macOS menu bar items work even while the WebView has keyboard focus.
  Widget _withMacMenus(AppServices services, Widget child) {
    final document = services.document;
    final settings = services.settings;
    return PlatformMenuBar(
      menus: [
        const PlatformMenu(
          label: 'MDViewer',
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'Open File…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
              onSelected: () => openFileCommand(context),
            ),
            PlatformMenuItem(
              label: 'Open Folder…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true, shift: true),
              onSelected: () => openFolderCommand(context),
            ),
            PlatformMenuItem(
              label: 'Reload',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
              onSelected: document.currentPath == null ? null : () => unawaited(document.reload()),
            ),
            PlatformMenuItem(
              label: 'Print…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyP, meta: true),
              onSelected: document.currentPath == null ? null : () => unawaited(_print(services)),
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: 'Find…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
              onSelected: document.currentPath == null ? null : _openFind,
            ),
            PlatformMenuItem(
              label: 'Search Folder…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true),
              onSelected: (document.workspace?.isFolder ?? false) ? () => unawaited(_searchFolder(services)) : null,
            ),
            PlatformMenuItem(
              label: 'Back',
              shortcut: const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true),
              onSelected: document.canGoBack ? () => unawaited(document.goBack()) : null,
            ),
            PlatformMenuItem(
              label: 'Forward',
              shortcut: const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true),
              onSelected: document.canGoForward ? () => unawaited(document.goForward()) : null,
            ),
            PlatformMenuItem(
              label: 'Larger Text',
              shortcut: const SingleActivator(LogicalKeyboardKey.equal, meta: true),
              onSelected: () => unawaited(settings.increaseFontScale()),
            ),
            PlatformMenuItem(
              label: 'Smaller Text',
              shortcut: const SingleActivator(LogicalKeyboardKey.minus, meta: true),
              onSelected: () => unawaited(settings.decreaseFontScale()),
            ),
            PlatformMenuItem(
              label: 'Actual Size',
              shortcut: const SingleActivator(LogicalKeyboardKey.digit0, meta: true),
              onSelected: () => unawaited(settings.resetFontScale()),
            ),
            PlatformMenuItem(
              label: _themeLabel(settings.themeMode),
              onSelected: () => unawaited(settings.cycleThemeMode()),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
