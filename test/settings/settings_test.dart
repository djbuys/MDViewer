import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/settings/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to system theme and 1.0 font scale', () async {
    final settings = await Settings.load();
    expect(settings.themeMode, AppThemeMode.system);
    expect(settings.fontScale, 1.0);
  });

  test('persists theme mode and cycles through modes', () async {
    final settings = await Settings.load();
    await settings.cycleThemeMode();
    expect(settings.themeMode, AppThemeMode.light);
    await settings.cycleThemeMode();
    expect(settings.themeMode, AppThemeMode.dark);
    expect((await Settings.load()).themeMode, AppThemeMode.dark);
    await settings.cycleThemeMode();
    expect(settings.themeMode, AppThemeMode.system);
  });

  test('font scale steps by 0.1 within bounds and persists', () async {
    final settings = await Settings.load();
    var notified = 0;
    settings.addListener(() => notified++);
    await settings.increaseFontScale();
    expect(settings.fontScale, 1.1);
    for (var i = 0; i < 10; i++) {
      await settings.increaseFontScale();
    }
    expect(settings.fontScale, Settings.maxFontScale);
    for (var i = 0; i < 20; i++) {
      await settings.decreaseFontScale();
    }
    expect(settings.fontScale, Settings.minFontScale);
    await settings.resetFontScale();
    expect((await Settings.load()).fontScale, 1.0);
    expect(notified, greaterThan(0));
  });

  test('ignores corrupt stored values', () async {
    SharedPreferences.setMockInitialValues({'themeMode': 'purple', 'fontScale': 9.0});
    final settings = await Settings.load();
    expect(settings.themeMode, AppThemeMode.system);
    expect(settings.fontScale, Settings.maxFontScale);
  });

  test('files sidebar and contents panel default to visible and persist', () async {
    final settings = await Settings.load();
    expect(settings.sidebarVisible, isTrue);
    expect(settings.tocVisible, isTrue);
    var notified = 0;
    settings.addListener(() => notified++);
    await settings.toggleSidebar();
    await settings.toggleToc();
    expect(settings.sidebarVisible, isFalse);
    expect(settings.tocVisible, isFalse);
    expect(notified, 2);

    final reloaded = await Settings.load();
    expect(reloaded.sidebarVisible, isFalse);
    expect(reloaded.tocVisible, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sidebarVisible'), isFalse);
    expect(prefs.getBool('tocVisible'), isFalse);
  });

  test('remembers that the default-app question was asked', () async {
    final settings = await Settings.load();
    expect(settings.defaultAppPromptDone, isFalse);
    await settings.markDefaultAppPromptDone();
    expect(settings.defaultAppPromptDone, isTrue);
    expect((await Settings.load()).defaultAppPromptDone, isTrue);
  });
}
