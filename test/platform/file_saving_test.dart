import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/platform/file_saving.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('mdv_wait'));
  tearDown(() => dir.delete(recursive: true));

  const complete = '%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n';
  const fast = Duration(milliseconds: 10);

  test('ensurePdfExtension appends .pdf unless the name already ends with it', () {
    expect(ensurePdfExtension('/out/report.pdf'), '/out/report.pdf');
    expect(ensurePdfExtension('/out/report.PDF'), '/out/report.PDF');
    expect(ensurePdfExtension('/out/report'), '/out/report.pdf');
    expect(ensurePdfExtension('/out/report.txt'), '/out/report.txt.pdf');
    expect(ensurePdfExtension('/out/notes.md'), '/out/notes.md.pdf');
  });

  test('waits for a complete PDF written later', () async {
    final path = p.join(dir.path, 'out.pdf');
    Timer(const Duration(milliseconds: 60), () => File(path).writeAsStringSync('%PDF-1.4\npartial'));
    Timer(const Duration(milliseconds: 150), () => File(path).writeAsStringSync(complete));
    expect(await waitForPdfFile(path, timeout: const Duration(seconds: 5), interval: fast), isTrue);
  });

  test('times out when nothing (or only a partial file) appears', () async {
    final path = p.join(dir.path, 'out.pdf');
    expect(await waitForPdfFile(path, timeout: const Duration(milliseconds: 100), interval: fast), isFalse);
    File(path).writeAsStringSync('%PDF-1.4\npartial');
    expect(await waitForPdfFile(path, timeout: const Duration(milliseconds: 100), interval: fast), isFalse);
  });

  test('an older file at the path does not count until it is rewritten', () async {
    final path = p.join(dir.path, 'out.pdf');
    File(path).writeAsStringSync(complete);
    final old = DateTime.now().subtract(const Duration(minutes: 5));
    File(path).setLastModifiedSync(old);
    final previous = File(path).lastModifiedSync();
    expect(
      await waitForPdfFile(path, previousModified: previous, timeout: const Duration(milliseconds: 100), interval: fast),
      isFalse,
    );
    Timer(const Duration(milliseconds: 50), () => File(path).writeAsStringSync(complete));
    expect(
      await waitForPdfFile(path, previousModified: previous, timeout: const Duration(seconds: 5), interval: fast),
      isTrue,
    );
  });
}
