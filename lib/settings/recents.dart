import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RecentKind { file, folder }

@immutable
class RecentEntry {
  const RecentEntry({required this.kind, required this.location, required this.displayName, this.bookmark});

  final RecentKind kind;

  /// A filesystem path, or an Android content/tree URI.
  final String location;
  final String displayName;

  /// iOS security-scoped bookmark data, base64-encoded.
  final String? bookmark;

  bool sameTarget(RecentEntry other) => other.kind == kind && other.location == location;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'location': location,
        'displayName': displayName,
        if (bookmark != null) 'bookmark': bookmark,
      };

  static RecentEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = RecentKind.values.asNameMap()[json['kind']];
    final location = json['location'];
    final displayName = json['displayName'];
    final bookmark = json['bookmark'];
    if (kind == null || location is! String || displayName is! String) return null;
    return RecentEntry(
      kind: kind,
      location: location,
      displayName: displayName,
      bookmark: bookmark is String ? bookmark : null,
    );
  }
}

class Recents extends ChangeNotifier {
  Recents._(this._prefs, this._entries);

  static const maxEntries = 10;
  static const _key = 'recents';

  static Future<Recents> load([SharedPreferences? prefs]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final entries = <RecentEntry>[];
    final raw = store.getString(_key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          entries.addAll(decoded.map(RecentEntry.fromJson).whereType<RecentEntry>());
        }
      } on FormatException {
        // Corrupt preferences: start with an empty list.
      }
    }
    return Recents._(store, entries);
  }

  final SharedPreferences _prefs;
  final List<RecentEntry> _entries;

  List<RecentEntry> get entries => List.unmodifiable(_entries);

  Future<void> add(RecentEntry entry) async {
    _entries
      ..removeWhere(entry.sameTarget)
      ..insert(0, entry);
    if (_entries.length > maxEntries) _entries.removeRange(maxEntries, _entries.length);
    await _save();
  }

  Future<void> remove(RecentEntry entry) async {
    _entries.removeWhere(entry.sameTarget);
    await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.setString(_key, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }
}
