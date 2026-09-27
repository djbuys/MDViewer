import 'dart:io';

import 'package:flutter/services.dart';

/// Whether MDViewer opens Markdown files by default, and making it so.
///
/// Only macOS supports this: Windows and Linux builds (zip/tar) cannot set
/// file associations programmatically, and iOS/Android have no such concept.
abstract interface class DefaultAppHandler {
  bool get isSupported;

  /// Whether MDViewer is the default app for `.md` / Markdown files.
  Future<bool> isDefault();

  /// Asks the OS to make MDViewer the default; true on success. macOS may
  /// show its own confirmation first.
  Future<bool> makeDefault();
}

DefaultAppHandler createDefaultAppHandler() =>
    Platform.isMacOS ? const MacDefaultAppHandler() : const UnsupportedDefaultAppHandler();

/// macOS: LaunchServices through the `mdviewer/default_app` channel
/// (AppDelegate.swift).
class MacDefaultAppHandler implements DefaultAppHandler {
  const MacDefaultAppHandler({this.channel = const MethodChannel('mdviewer/default_app')});

  final MethodChannel channel;

  @override
  bool get isSupported => true;

  @override
  Future<bool> isDefault() => _call('isDefault');

  @override
  Future<bool> makeDefault() => _call('makeDefault');

  Future<bool> _call(String method) async {
    try {
      return await channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

class UnsupportedDefaultAppHandler implements DefaultAppHandler {
  const UnsupportedDefaultAppHandler();

  @override
  bool get isSupported => false;

  @override
  Future<bool> isDefault() async => false;

  @override
  Future<bool> makeDefault() async => false;
}
