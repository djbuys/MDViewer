import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/window_controls.dart';
import 'app_actions.dart';

/// Title-bar height on macOS, where Flutter draws the unified title bar
/// under the transparent native one (see MainFlutterWindow.swift).
const double macTitleBarHeight = 52;

/// Room for the traffic lights on macOS.
const double macTrafficLightInset = 78;

const double _minTitleWidth = 120;
const double _dividerWidth = 9;

/// The app's title bar: document title plus icon buttons for the actions
/// that fit; the rest go into the `⋮` overflow menu.
///
/// On macOS it shares one row with the traffic lights and its empty parts
/// move and zoom the window. Elsewhere it looks like a normal [AppBar].
class MdTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const MdTitleBar({
    super.key,
    required this.title,
    required this.actions,
    required this.platform,
    this.leading,
    this.wide = true,
    this.windowControls,
  });

  final String title;
  final List<AppAction> actions;
  final TargetPlatform platform;

  /// Shown before the title (the files drawer button on narrow layouts).
  final Widget? leading;

  /// Separates button groups with dividers.
  final bool wide;

  /// Defaults to [WindowControls.instance].
  final WindowControls? windowControls;

  WindowControls get _controls => windowControls ?? WindowControls.instance;

  bool get _mac => platform == TargetPlatform.macOS;

  bool get _desktop => _mac || platform == TargetPlatform.windows || platform == TargetPlatform.linux;

  /// Width reserved for each icon button.
  double get buttonExtent => _desktop ? 40 : 48;

  @override
  Size get preferredSize => Size.fromHeight(_mac ? macTitleBarHeight : kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    if (!_mac) return _layout(trafficLightInset: 0);
    // The traffic lights are hidden in full screen.
    return ValueListenableBuilder<bool>(
      valueListenable: _controls.fullScreen,
      builder: (context, fullScreen, _) => _layout(trafficLightInset: fullScreen ? 0 : macTrafficLightInset),
    );
  }

  Widget _layout({required double trafficLightInset}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final leadingWidth = trafficLightInset + (leading == null ? 0 : buttonExtent);
        final split = splitTitleBarActions(
          actions,
          available: constraints.maxWidth - leadingWidth - _minTitleWidth - 16,
          extent: buttonExtent,
          dividerWidth: wide ? _dividerWidth : 0,
        );
        final buttons = _buttons(context, split.bar, overflow: split.overflow);
        return _mac ? _macBar(context, buttons, trafficLightInset: trafficLightInset) : _appBar(context, buttons);
      },
    );
  }

  Widget _appBar(BuildContext context, List<Widget> buttons) => AppBar(
        automaticallyImplyLeading: false,
        leading: leading,
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [...buttons, const SizedBox(width: 4)],
      );

  Widget _macBar(BuildContext context, List<Widget> buttons, {required double trafficLightInset}) {
    final theme = Theme.of(context);
    Widget dragArea(Widget child) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => unawaited(_controls.startDrag()),
          onDoubleTap: () => unawaited(_controls.toggleZoom()),
          child: child,
        );
    return Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant, width: 0)),
        ),
        child: SizedBox(
          height: macTitleBarHeight,
          child: Row(
            children: [
              if (trafficLightInset > 0) dragArea(SizedBox(width: trafficLightInset, height: macTitleBarHeight)),
              ?leading,
              Expanded(
                child: dragArea(
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        key: const Key('title-bar-title'),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
              ...buttons,
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buttons(BuildContext context, List<AppAction> bar, {required List<AppAction> overflow}) {
    final widgets = <Widget>[];
    ActionGroup? previous;
    for (final action in bar) {
      if (wide && previous != null && action.group != previous) {
        widgets.add(const SizedBox(
          width: _dividerWidth,
          height: 20,
          child: VerticalDivider(width: _dividerWidth, thickness: 1),
        ));
      }
      previous = action.group;
      widgets.add(SizedBox.square(key: action.anchorKey, dimension: buttonExtent, child: _button(action)));
    }
    widgets.add(SizedBox.square(dimension: buttonExtent, child: _overflowButton(overflow)));
    return widgets;
  }

  Widget _button(AppAction action) {
    if (action.children.isNotEmpty) {
      return PopupMenuButton<AppAction>(
        key: Key('action-${action.id}'),
        tooltip: action.label,
        icon: Icon(action.icon),
        padding: EdgeInsets.zero,
        onSelected: (child) => child.onSelected?.call(),
        itemBuilder: (_) => [
          for (final child in action.children)
            PopupMenuItem(key: Key('menu-${child.id}'), value: child, child: Text(child.label)),
        ],
      );
    }
    return IconButton(
      key: Key('action-${action.id}'),
      tooltip: action.label,
      icon: Icon(action.icon),
      padding: EdgeInsets.zero,
      onPressed: action.onSelected,
    );
  }

  Widget _overflowButton(List<AppAction> overflow) => PopupMenuButton<AppAction>(
        key: const Key('action-more'),
        tooltip: 'More',
        icon: const Icon(Icons.more_vert),
        padding: EdgeInsets.zero,
        onSelected: (action) => action.onSelected?.call(),
        itemBuilder: (_) {
          final items = <PopupMenuEntry<AppAction>>[];
          ActionGroup? previous;
          var first = true;
          for (final action in overflow) {
            if (!first && action.group != previous) items.add(const PopupMenuDivider());
            first = false;
            previous = action.group;
            if (action.children.isEmpty) {
              items.add(_menuItem(action, action.label));
            } else {
              for (final child in action.children) {
                items.add(_menuItem(child, '${action.label}: ${child.label}'));
              }
            }
          }
          return items;
        },
      );

  static PopupMenuItem<AppAction> _menuItem(AppAction action, String text) => PopupMenuItem<AppAction>(
        key: Key('menu-${action.id}'),
        value: action,
        enabled: action.enabled,
        child: Row(
          children: [
            Icon(action.icon, size: 20),
            const SizedBox(width: 12),
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}

/// Splits [actions] into title-bar buttons and overflow-menu items.
///
/// Title-bar candidates (those with a group) are admitted by priority, highest
/// first, while their buttons fit in [available] pixels; the first priority
/// level that does not fit, and everything below it, goes to the overflow
/// menu. Pinned actions and the overflow button itself always stay. Both
/// lists keep the original order; overflow-only actions come last.
@visibleForTesting
({List<AppAction> bar, List<AppAction> overflow}) splitTitleBarActions(
  List<AppAction> actions, {
  required double available,
  required double extent,
  double dividerWidth = 0,
}) {
  final candidates = [for (final a in actions) if (a.group != null && !a.menuOnly) a];
  final pinned = candidates.where((a) => a.priority >= ActionPriority.pinned);
  // The overflow button and the pinned buttons always stay.
  var remaining = available - extent * (1 + pinned.length);
  final visibleGroups = {for (final a in pinned) a.group};
  final levels = {for (final a in candidates) if (a.priority < ActionPriority.pinned) a.priority}.toList()
    ..sort((a, b) => b.compareTo(a));
  final admitted = <int>{ActionPriority.pinned};
  for (final level in levels) {
    final members = candidates.where((a) => a.priority == level);
    final newGroups = {for (final a in members) a.group}.difference(visibleGroups);
    // A divider separates each newly shown group from the ones already there.
    final dividers = newGroups.length - (visibleGroups.isEmpty ? 1 : 0);
    final cost = extent * members.length + dividerWidth * (dividers < 0 ? 0 : dividers);
    if (cost > remaining) break;
    remaining -= cost;
    admitted.add(level);
    visibleGroups.addAll(newGroups);
  }
  bool shown(AppAction a) => admitted.contains(a.priority.clamp(0, ActionPriority.pinned));
  return (
    bar: [for (final a in candidates) if (shown(a)) a],
    overflow: [
      for (final a in candidates) if (!shown(a)) a,
      for (final a in actions) if (a.group == null && !a.menuOnly) a,
    ],
  );
}
