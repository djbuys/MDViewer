import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// Hands the open document to the OS share sheet (iOS and Android).
abstract interface class DocumentSharer {
  /// Whether sharing is offered on this platform.
  bool get isSupported;

  /// Shares [bytes] as a file called [name]. [origin] anchors the iPad
  /// popover (global coordinates).
  Future<void> share({required Uint8List bytes, required String name, required String mimeType, Rect? origin});
}

class SharePlusDocumentSharer implements DocumentSharer {
  const SharePlusDocumentSharer();

  @override
  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  @override
  Future<void> share({required Uint8List bytes, required String name, required String mimeType, Rect? origin}) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, name: name, mimeType: mimeType)],
      fileNameOverrides: [name],
      subject: name,
      title: name,
      sharePositionOrigin: origin,
    ));
  }
}
