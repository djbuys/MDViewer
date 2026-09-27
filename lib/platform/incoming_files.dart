import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'document_access.dart';

/// Documents handed to the app by the OS: launch arguments (Windows/Linux)
/// and native open events (macOS Finder, iOS "Open in", Android VIEW intents).
class IncomingFiles {
  IncomingFiles({this.args = const [], MethodChannel? channel, bool? useChannel})
      : _channel = channel ?? const MethodChannel('mdviewer/incoming'),
        _useChannel = useChannel ?? (Platform.isMacOS || Platform.isIOS || Platform.isAndroid);

  /// Command-line arguments (Windows/Linux file associations pass paths here).
  final List<String> args;
  final MethodChannel _channel;
  final bool _useChannel;
  final StreamController<IncomingDocument> _documents = StreamController<IncomingDocument>.broadcast();

  /// Documents opened while the app is running.
  Stream<IncomingDocument> get documents => _documents.stream;

  /// Documents the app was launched with. Call once, after the first frame.
  Future<List<IncomingDocument>> takeInitial() async {
    final initial = [
      for (final arg in args)
        if (!arg.startsWith('-')) IncomingDocument(path: arg),
    ];
    if (_useChannel) {
      _channel.setMethodCallHandler(_handle);
      try {
        initial.addAll(_parse(await _channel.invokeListMethod<Object?>('takePending')));
      } on MissingPluginException {
        // Platform without a native side.
      } on PlatformException {
        // Treat native failures as "nothing pending".
      }
    }
    return initial;
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'open') _parse(call.arguments as List<Object?>?).forEach(_documents.add);
    return null;
  }

  static List<IncomingDocument> _parse(List<Object?>? raw) => [
        for (final item in raw ?? const <Object?>[])
          if (item is Map && item['path'] is String)
            IncomingDocument(
              path: item['path'] as String,
              bookmark: item['bookmark'] is String ? item['bookmark'] as String : null,
            ),
      ];

  void dispose() => _documents.close();
}
