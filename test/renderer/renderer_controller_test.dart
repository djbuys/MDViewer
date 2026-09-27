import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/renderer/renderer_controller.dart';

void main() {
  test('Heading parses bridge JSON where numbers may be doubles', () {
    expect(
      Heading.fromJson({'id': 'intro', 'text': 'Intro', 'level': 2.0}),
      const Heading(id: 'intro', text: 'Intro', level: 2),
    );
  });

  test('FindResult parses bridge JSON', () {
    expect(FindResult.fromJson({'total': 3, 'current': 1.0}), const FindResult(total: 3, current: 1));
    expect(FindResult.none, const FindResult(total: 0, current: 0));
  });

  test('RenderOptions serializes for the JS renderer', () {
    expect(
      const RenderOptions(dark: true, fontScale: 1.2, heavyFeatures: false).toJson(),
      {'theme': 'dark', 'fontScale': 1.2, 'heavyFeatures': false},
    );
    expect(
      const RenderOptions(dark: false, fontScale: 1, heavyFeatures: true, restoreScrollY: 40).toJson(),
      {'theme': 'light', 'fontScale': 1.0, 'heavyFeatures': true, 'restoreScrollY': 40.0},
    );
  });
}
