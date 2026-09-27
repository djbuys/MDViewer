import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

class Settings extends ChangeNotifier {
  Settings._(this._prefs, this._themeMode, this._fontScale);

  static const minFontScale = 0.8;
  static const maxFontScale = 1.6;
  static const fontScaleStep = 0.1;
  static const _themeKey = 'themeMode';
  static const _fontScaleKey = 'fontScale';

  static Future<Settings> load([SharedPreferences? prefs]) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final mode = AppThemeMode.values.asNameMap()[store.getString(_themeKey)] ?? AppThemeMode.system;
    final scale = _clamp(store.getDouble(_fontScaleKey) ?? 1.0);
    return Settings._(store, mode, scale);
  }

  final SharedPreferences _prefs;
  AppThemeMode _themeMode;
  double _fontScale;

  AppThemeMode get themeMode => _themeMode;
  double get fontScale => _fontScale;

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
