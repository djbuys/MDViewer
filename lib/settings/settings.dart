import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

/// The user's view choices, persisted across launches.
class Settings extends ChangeNotifier {
  Settings._(this._prefs)
      : _themeMode = AppThemeMode.values.asNameMap()[_prefs.getString(_themeKey)] ?? AppThemeMode.system,
        _fontScale = _clamp(_prefs.getDouble(_fontScaleKey) ?? 1.0),
        _sidebarVisible = _prefs.getBool(_sidebarKey) ?? true,
        _tocVisible = _prefs.getBool(_tocKey) ?? true;

  static const minFontScale = 0.8;
  static const maxFontScale = 1.6;
  static const fontScaleStep = 0.1;
  static const _themeKey = 'themeMode';
  static const _fontScaleKey = 'fontScale';
  static const _sidebarKey = 'sidebarVisible';
  static const _tocKey = 'tocVisible';

  static Future<Settings> load([SharedPreferences? prefs]) async =>
      Settings._(prefs ?? await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  AppThemeMode _themeMode;
  double _fontScale;
  bool _sidebarVisible;
  bool _tocVisible;

  AppThemeMode get themeMode => _themeMode;
  double get fontScale => _fontScale;

  /// Whether the files sidebar is shown in the wide layout.
  bool get sidebarVisible => _sidebarVisible;

  /// Whether the contents panel is shown in the wide layout.
  bool get tocVisible => _tocVisible;

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_themeKey, mode.name);
  }

  Future<void> cycleThemeMode() =>
      setThemeMode(AppThemeMode.values[(_themeMode.index + 1) % AppThemeMode.values.length]);

  Future<void> increaseFontScale() => _setFontScale(_fontScale + fontScaleStep);
  Future<void> decreaseFontScale() => _setFontScale(_fontScale - fontScaleStep);
  Future<void> resetFontScale() => _setFontScale(1.0);

  Future<void> toggleSidebar() async {
    _sidebarVisible = !_sidebarVisible;
    notifyListeners();
    await _prefs.setBool(_sidebarKey, _sidebarVisible);
  }

  Future<void> toggleToc() async {
    _tocVisible = !_tocVisible;
    notifyListeners();
    await _prefs.setBool(_tocKey, _tocVisible);
  }

  Future<void> _setFontScale(double value) async {
    final scale = _clamp(value);
    if (scale == _fontScale) return;
    _fontScale = scale;
    notifyListeners();
    await _prefs.setDouble(_fontScaleKey, scale);
  }

  static double _clamp(double value) =>
      ((value.clamp(minFontScale, maxFontScale) * 10).round() / 10).toDouble();
}
