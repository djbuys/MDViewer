import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native window behaviour for the macOS title bar, which Flutter draws
/// itself (`mdviewer/window`): dragging and zooming from its empty parts, and
/// whether the window is in full screen (the traffic lights are hidden then).
class WindowControls {
  WindowControls({this.channel = const MethodChannel('mdviewer/window')});

  /// The app's window (macOS). [listen] is called once at startup.
  static final WindowControls instance = WindowControls();

  final MethodChannel channel;

  /// Whether the window is in full screen, as reported by the native side.
  ValueListenable<bool> get fullScreen => _fullScreen;
  final ValueNotifier<bool> _fullScreen = ValueNotifier(false);

  /// Starts receiving `fullScreenChanged(bool)` and reads the current state.
  Future<void> listen() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'fullScreenChanged' && call.arguments is bool) _fullScreen.value = call.arguments as bool;
      return null;
    });
    try {
      _fullScreen.value = await channel.invokeMethod<bool>('isFullScreen') ?? false;
    } on MissingPluginException {
      // No native window support (tests, other platforms).
    } on PlatformException {
      // Best-effort.
    }
  }

  /// Starts moving the window with the mouse button that is still down.
  Future<void> startDrag() => _invoke('startDrag');

  /// Zooms, minimizes or does nothing, following the system's
  /// "double-click a window's title bar" setting.
  Future<void> toggleZoom() => _invoke('toggleZoom');

  void dispose() {
    channel.setMethodCallHandler(null);
    _fullScreen.dispose();
  }

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
