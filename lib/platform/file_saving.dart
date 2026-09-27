import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

/// Asks where to save a file; returns the chosen path or null if cancelled.
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

Future<String?> pickPdfSaveLocation(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf'], uniformTypeIdentifiers: ['com.adobe.pdf']),
    ],
  );
  return location?.path;
}

/// [path] with a `.pdf` extension: appended when the chosen name has none or
/// another one (`report.txt` becomes `report.txt.pdf`).
String ensurePdfExtension(String path) => p.extension(path).toLowerCase() == '.pdf' ? path : '$path.pdf';

/// Waits until a complete PDF exists at [path]: it starts with `%PDF-`, has
/// an `%%EOF` marker near the end, its size is stable between two polls and,
/// if [previousModified] is given (the file that was there before), it was
/// modified after that. Returns false after [timeout].
///
/// Used where the platform writes the file asynchronously without reliably
/// reporting completion (macOS print-to-file).
Future<bool> waitForPdfFile(
  String path, {
  DateTime? previousModified,
  Duration timeout = const Duration(seconds: 60),
  Duration interval = const Duration(milliseconds: 100),
}) async {
  final file = File(path);
  final deadline = DateTime.now().add(timeout);
  int? lastSize;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final stat = await file.stat();
      final fresh = previousModified == null || stat.modified.isAfter(previousModified);
      if (stat.type == FileSystemEntityType.file && fresh && stat.size > 0) {
        if (stat.size == lastSize && await _isCompletePdf(file, stat.size)) return true;
        lastSize = stat.size;
      }
    } on FileSystemException {
      // Not there yet, or being replaced.
    }
    await Future<void>.delayed(interval);
  }
  return false;
}

Future<bool> _isCompletePdf(File file, int size) async {
  final handle = await file.open();
  try {
    final head = latin1.decode(await handle.read(5));
    await handle.setPosition(size > 1024 ? size - 1024 : 0);
    final tail = latin1.decode(await handle.read(1024));
    return head == '%PDF-' && tail.contains('%%EOF');
  } finally {
    await handle.close();
  }
}
