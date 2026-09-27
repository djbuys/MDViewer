import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Asks where to save a file; returns the chosen path or null if cancelled.
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

/// Writes [bytes] to [path] (the only file the app ever writes for the user,
/// and only where the user chose).
typedef FileWriter = Future<void> Function(String path, Uint8List bytes);

Future<String?> pickPdfSaveLocation(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf'], uniformTypeIdentifiers: ['com.adobe.pdf']),
    ],
  );
  return location?.path;
}

Future<void> writeFileBytes(String path, Uint8List bytes) => File(path).writeAsBytes(bytes, flush: true);
