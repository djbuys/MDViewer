import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../platform/edit_commands.dart';
import '../settings/settings.dart';
import 'open_commands.dart';

/// Title-bar button groups, in display order. Dividers separate them on wide
/// layouts.
enum ActionGroup { navigation, file, search, view, output, share }

/// How long an action keeps its title-bar button as the bar gets narrower:
/// the lowest priority moves into the overflow menu first.
abstract final class ActionPriority {
  static const toggles = 1;
  static const output = 2;
  static const appearance = 3;
  static const searchFolder = 4;
  static const open = 5;
  static const history = 6;
  static const share = 7;

  /// Never moves into the overflow menu.
  static const pinned = 1000;
}

/// One user command. The title bar, the overflow menu, keyboard shortcuts and
/// the macOS menu bar are all built from the same list, so their labels,
/// shortcuts and enabled state cannot drift apart.
@immutable
class AppAction {
  const AppAction({
    required this.id,
    required this.label,
    required this.icon,
    this.menuLabel,
    this.shortcut,
    this.onSelected,
    this.group,
    this.priority = 0,
    this.children = const [],
    this.menuOnly = false,
    this.anchorKey,
  });

  /// Keys: `action-<id>` for the title-bar button, `menu-<id>` for the
  /// overflow item.
  final String id;

  /// Tooltip and overflow-menu text.
  final String label;

  /// macOS menu bar text, when it differs from [label].
  final String? menuLabel;
  final IconData icon;
  final SingleActivator? shortcut;

  /// Null when the action is disabled.
  final VoidCallback? onSelected;

  /// The title-bar group; null for actions that live only in the overflow
  /// menu (and the menu bar).
  final ActionGroup? group;
  final int priority;

  /// Sub-actions (recent files): a popup in the title bar, a submenu in the
  /// menu bar, individual items in the overflow menu.
  final List<AppAction> children;

  /// Only in the macOS menu bar (Copy, Select All): no button, no overflow
  /// item and no Flutter shortcut binding.
  final bool menuOnly;

  /// Put on the title-bar button so the action can find where it is on
  /// screen (the iPad share popover anchors to it).
  final GlobalKey? anchorKey;

  bool get enabled => onSelected != null || children.isNotEmpty;
  String get menuTitle => menuLabel ?? label;
}

/// What the actions need from the app shell's UI state.
abstract interface class AppActionHost {
  void openFind();
  Future<void> searchFolder();
  Future<void> printDocument();
  Future<void> savePdf();
  Future<void> shareDocument();
  void openContentsDrawer();

  /// Anchors the share button.
  GlobalKey get shareAnchor;
}

bool _usesMeta(TargetPlatform platform) => platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

String themeLabel(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => 'Theme: follow system',
      AppThemeMode.light => 'Theme: light',
      AppThemeMode.dark => 'Theme: dark',
    };

IconData themeIcon(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => Icons.brightness_auto,
      AppThemeMode.light => Icons.light_mode,
      AppThemeMode.dark => Icons.dark_mode,
    };

/// Every command, in title-bar order.
List<AppAction> buildAppActions({
  required BuildContext context,
  required AppServices services,
  required AppActionHost host,
  required bool wide,
  required TargetPlatform platform,
}) {
  final document = services.document;
  final settings = services.settings;
  final hasDocument = document.currentPath != null;
  final hasFolder = document.workspace?.isFolder ?? false;
  final hasHeadings = document.headings.isNotEmpty;
  final meta = _usesMeta(platform);
  SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) =>
      SingleActivator(k, meta: meta, control: !meta, shift: shift);
  VoidCallback? when(bool enabled, VoidCallback callback) => enabled ? callback : null;

  return [
    AppAction(
      id: 'back',
      label: 'Back',
      icon: Icons.arrow_back,
      shortcut: key(LogicalKeyboardKey.bracketLeft),
      onSelected: when(document.canGoBack, () => unawaited(document.goBack())),
      group: ActionGroup.navigation,
      priority: ActionPriority.history,
    ),
    AppAction(
      id: 'forward',
      label: 'Forward',
      icon: Icons.arrow_forward,
      shortcut: key(LogicalKeyboardKey.bracketRight),
      onSelected: when(document.canGoForward, () => unawaited(document.goForward())),
      group: ActionGroup.navigation,
      priority: ActionPriority.history,
    ),
    AppAction(
      id: 'open-file',
      label: 'Open file',
      menuLabel: 'Open File…',
      icon: Icons.file_open_outlined,
      shortcut: key(LogicalKeyboardKey.keyO),
      onSelected: () => unawaited(openFileCommand(context)),
      group: ActionGroup.file,
      priority: ActionPriority.open,
    ),
    AppAction(
      id: 'open-folder',
      label: 'Open folder',
      menuLabel: 'Open Folder…',
      icon: Icons.folder_open_outlined,
      shortcut: key(LogicalKeyboardKey.keyO, shift: true),
      onSelected: () => unawaited(openFolderCommand(context)),
      group: ActionGroup.file,
      priority: ActionPriority.open,
    ),
    if (services.recents.entries.isNotEmpty)
      AppAction(
        id: 'recents',
        label: 'Recent',
        menuLabel: 'Open Recent',
        icon: Icons.history,
        group: ActionGroup.file,
        priority: ActionPriority.open,
        children: [
          for (final (index, entry) in services.recents.entries.indexed)
            AppAction(
              id: 'recent-$index',
              label: entry.displayName,
              icon: Icons.history,
              onSelected: () => unawaited(openRecentCommand(context, entry)),
            ),
        ],
      ),
    AppAction(
      id: 'find',
      label: 'Find in document',
      menuLabel: 'Find…',
      icon: Icons.search,
      shortcut: key(LogicalKeyboardKey.keyF),
      onSelected: when(hasDocument, host.openFind),
      group: ActionGroup.search,
      priority: ActionPriority.pinned,
    ),
    if (hasFolder)
      AppAction(
        id: 'search-folder',
        label: 'Search folder',
        menuLabel: 'Search Folder…',
        icon: Icons.manage_search,
        shortcut: key(LogicalKeyboardKey.keyF, shift: true),
        onSelected: () => unawaited(host.searchFolder()),
        group: ActionGroup.search,
        priority: ActionPriority.searchFolder,
      ),
    AppAction(
      id: 'font-down',
      label: 'Smaller text',
      menuLabel: 'Smaller Text',
      icon: Icons.text_decrease,
      shortcut: key(LogicalKeyboardKey.minus),
      onSelected: when(settings.fontScale > Settings.minFontScale, () => unawaited(settings.decreaseFontScale())),
      group: ActionGroup.view,
      priority: ActionPriority.appearance,
    ),
    AppAction(
      id: 'font-up',
      label: 'Larger text',
      menuLabel: 'Larger Text',
      icon: Icons.text_increase,
      shortcut: key(LogicalKeyboardKey.equal),
      onSelected: when(settings.fontScale < Settings.maxFontScale, () => unawaited(settings.increaseFontScale())),
      group: ActionGroup.view,
      priority: ActionPriority.appearance,
    ),
    AppAction(
      id: 'theme',
      label: themeLabel(settings.themeMode),
      icon: themeIcon(settings.themeMode),
      onSelected: () => unawaited(settings.cycleThemeMode()),
      group: ActionGroup.view,
      priority: ActionPriority.appearance,
    ),
    if (wide && hasFolder)
      AppAction(
        id: 'toggle-sidebar',
        label: settings.sidebarVisible ? 'Hide files' : 'Show files',
        menuLabel: settings.sidebarVisible ? 'Hide Files' : 'Show Files',
        icon: Icons.vertical_split_outlined,
        onSelected: () => unawaited(settings.toggleSidebar()),
        group: ActionGroup.view,
        priority: ActionPriority.toggles,
      ),
    if (wide && hasHeadings)
      AppAction(
        id: 'toggle-toc',
        label: settings.tocVisible ? 'Hide contents' : 'Show contents',
        menuLabel: settings.tocVisible ? 'Hide Contents' : 'Show Contents',
        icon: Icons.toc,
        onSelected: () => unawaited(settings.toggleToc()),
        group: ActionGroup.view,
        priority: ActionPriority.toggles,
      ),
    if (!wide && hasHeadings)
      AppAction(
        id: 'contents',
        label: 'Contents',
        icon: Icons.toc,
        onSelected: host.openContentsDrawer,
        group: ActionGroup.view,
        priority: ActionPriority.toggles,
      ),
    if (services.renderer.canPrint)
      AppAction(
        id: 'print',
        label: 'Print',
        menuLabel: 'Print…',
        icon: Icons.print_outlined,
        shortcut: key(LogicalKeyboardKey.keyP),
        onSelected: when(hasDocument, () => unawaited(host.printDocument())),
        group: ActionGroup.output,
        priority: ActionPriority.output,
      ),
    if (services.renderer.canSavePdf)
      AppAction(
        id: 'save-pdf',
        label: 'Save as PDF',
        menuLabel: 'Save as PDF…',
        icon: Icons.picture_as_pdf_outlined,
        onSelected: when(hasDocument, () => unawaited(host.savePdf())),
        group: ActionGroup.output,
        priority: ActionPriority.output,
      ),
    if (services.sharer.isSupported)
      AppAction(
        id: 'share',
        label: 'Share',
        icon: platform == TargetPlatform.iOS ? Icons.ios_share : Icons.share,
        onSelected: when(hasDocument, () => unawaited(host.shareDocument())),
        group: ActionGroup.share,
        priority: ActionPriority.share,
        anchorKey: host.shareAnchor,
      ),
    AppAction(
      id: 'reload',
      label: 'Reload',
      icon: Icons.refresh,
      shortcut: key(LogicalKeyboardKey.keyR),
      onSelected: when(hasDocument, () => unawaited(document.reload())),
    ),
    AppAction(
      id: 'font-reset',
      label: 'Reset text size (${(settings.fontScale * 100).round()}%)',
      menuLabel: 'Actual Size',
      icon: Icons.format_size,
      shortcut: key(LogicalKeyboardKey.digit0),
      onSelected: () => unawaited(settings.resetFontScale()),
    ),
    if (platform == TargetPlatform.macOS) ...[
      AppAction(
        id: 'copy',
        label: 'Copy',
        icon: Icons.copy,
        shortcut: key(LogicalKeyboardKey.keyC),
        onSelected: () => unawaited(const EditCommands().copy()),
        menuOnly: true,
      ),
      AppAction(
        id: 'select-all',
        label: 'Select All',
        icon: Icons.select_all,
        shortcut: key(LogicalKeyboardKey.keyA),
        onSelected: () => unawaited(const EditCommands().selectAll()),
        menuOnly: true,
      ),
    ],
  ];
}

/// Keyboard shortcuts for every enabled action (except menu-only ones, which
/// the native menu handles).
Map<ShortcutActivator, VoidCallback> shortcutBindings(List<AppAction> actions) => {
      for (final action in actions)
        if (action.shortcut != null && action.onSelected != null && !action.menuOnly)
          action.shortcut!: action.onSelected!,
    };

/// The macOS menu bar. Menu items work even while the WebView has keyboard
/// focus.
List<PlatformMenuItem> macMenus(List<AppAction> actions) {
  final byId = {for (final action in actions) action.id: action};
  List<PlatformMenuItem> items(List<String> ids) => [
        for (final id in ids)
          if (byId[id] case final action?) _menuItem(action),
      ];
  List<PlatformMenuItem> groups(List<List<String>> ids) => [
        for (final members in ids.map(items))
          if (members.isNotEmpty) PlatformMenuItemGroup(members: members),
      ];

  return [
    PlatformMenu(
      label: 'MDViewer',
      menus: [
        ..._provided([PlatformProvidedMenuItemType.about]),
        PlatformMenuItemGroup(members: _provided([PlatformProvidedMenuItemType.servicesSubmenu])),
        PlatformMenuItemGroup(
          members: _provided([
            PlatformProvidedMenuItemType.hide,
            PlatformProvidedMenuItemType.hideOtherApplications,
            PlatformProvidedMenuItemType.showAllApplications,
          ]),
        ),
        ..._provided([PlatformProvidedMenuItemType.quit]),
      ],
    ),
    PlatformMenu(
      label: 'File',
      menus: groups([
        ['open-file', 'open-folder', 'recents'],
        ['reload'],
        ['print', 'save-pdf'],
      ]),
    ),
    PlatformMenu(label: 'Edit', menus: items(['copy', 'select-all'])),
    PlatformMenu(
      label: 'View',
      menus: groups([
        ['find', 'search-folder'],
        ['back', 'forward'],
        ['font-up', 'font-down', 'font-reset'],
        ['theme'],
        ['toggle-sidebar', 'toggle-toc'],
      ]),
    ),
    PlatformMenu(
      label: 'Window',
      menus: _provided([
        PlatformProvidedMenuItemType.minimizeWindow,
        PlatformProvidedMenuItemType.zoomWindow,
        PlatformProvidedMenuItemType.toggleFullScreen,
        PlatformProvidedMenuItemType.arrangeWindowsInFront,
      ]),
    ),
  ];
}

PlatformMenuItem _menuItem(AppAction action) => action.children.isEmpty
    ? PlatformMenuItem(label: action.menuTitle, shortcut: action.shortcut, onSelected: action.onSelected)
    : PlatformMenu(label: action.menuTitle, menus: [for (final child in action.children) _menuItem(child)]);

/// The platform-provided menu items this OS actually offers.
List<PlatformMenuItem> _provided(List<PlatformProvidedMenuItemType> types) => [
      for (final type in types)
        if (PlatformProvidedMenuItem.hasMenu(type)) PlatformProvidedMenuItem(type: type),
    ];
