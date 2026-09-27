import 'package:flutter/services.dart';

/// Native window behaviour for the empty parts of the macOS title bar,
/// which Flutter draws itself (`mdviewer/window`).
class WindowControls {
  const WindowControls({this.channel = const MethodChannel('mdviewer/window')});

  final MethodChannel channel;

  /// Starts moving the window with the mouse button that is still down.
  Future<void> startDrag() => _invoke('startDrag');

  /// Zooms, minimizes or does nothing, following the system's
  /// "double-click a window's title bar" setting.
  Future<void> toggleZoom() => _invoke('toggleZoom');

  Future<void> _invoke(String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No native window support (tests, other platforms).
    } on PlatformException {
      // Window management is best-effort.
    }
  }
}
