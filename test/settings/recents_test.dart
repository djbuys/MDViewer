import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/settings/recents.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecentEntry file(String path) => RecentEntry(kind: RecentKind.file, location: path, displayName: path.split('/').last);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('adds newest first, de-duplicates and persists', () async {
    final recents = await Recents.load();
    await recents.add(file('/a.md'));
    await recents.add(file('/b.md'));
    await recents.add(file('/a.md'));
    expect(recents.entries.map((e) => e.location), ['/a.md', '/b.md']);
    expect((await Recents.load()).entries.map((e) => e.location), ['/a.md', '/b.md']);
  });

  test('keeps at most 10 entries', () async {
    final recents = await Recents.load();
    for (var i = 0; i < 12; i++) {
      await recents.add(file('/$i.md'));
    }
    expect(recents.entries, hasLength(Recents.maxEntries));
    expect(recents.entries.first.location, '/11.md');
  });

  test('a file and a folder at the same location are different entries', () async {
    final recents = await Recents.load();
    await recents.add(file('/x'));
    await recents.add(const RecentEntry(kind: RecentKind.folder, location: '/x', displayName: 'x'));
    expect(recents.entries, hasLength(2));
  });

  test('round-trips bookmarks and removes entries', () async {
    final recents = await Recents.load();
    const entry = RecentEntry(kind: RecentKind.folder, location: '/d', displayName: 'd', bookmark: 'Ym9vaw==');
    await recents.add(entry);
    final loaded = await Recents.load();
    expect(loaded.entries.single.bookmark, 'Ym9vaw==');
    await loaded.remove(entry);
    expect((await Recents.load()).entries, isEmpty);
  });

  test('skips malformed stored entries', () async {
    SharedPreferences.setMockInitialValues({
      'recents': '[{"kind":"file","location":"/ok.md","displayName":"ok.md"},{"bad":true},42]',
    });
    expect((await Recents.load()).entries.map((e) => e.location), ['/ok.md']);
  });

  test('survives a corrupt JSON blob', () async {
    SharedPreferences.setMockInitialValues({'recents': 'not json'});
    expect((await Recents.load()).entries, isEmpty);
  });
}
