import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/document/text_decoding.dart';

Uint8List bytes(List<int> list) => Uint8List.fromList(list);

void main() {
  test('decodes plain UTF-8', () {
    expect(decodeText(bytes(utf8.encode('héllo'))), 'héllo');
  });

  test('strips a UTF-8 byte order mark', () {
    expect(decodeText(bytes([0xEF, 0xBB, 0xBF, ...utf8.encode('# Hi')])), '# Hi');
  });

  test('replaces malformed UTF-8 instead of throwing', () {
    final text = decodeText(bytes([0x61, 0xFF, 0x62]));
    expect(text, 'a�b');
  });

  test('decodes UTF-16 LE and BE with byte order marks', () {
    expect(decodeText(bytes([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00])), 'hi');
    expect(decodeText(bytes([0xFE, 0xFF, 0x00, 0x68, 0x00, 0x69])), 'hi');
  });

  test('decodes empty input', () {
    expect(decodeText(bytes([])), '');
  });
}
