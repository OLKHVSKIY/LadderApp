import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Глобальный контроллер темы приложения (светлая/тёмная).
///
/// Хранит выбранный [ThemeMode] в [ValueNotifier], чтобы [MaterialApp] мог
/// перестраиваться через [ValueListenableBuilder], а настройки — менять тему
/// из любого места без Provider/Bloc. Значение сохраняется в SharedPreferences.
class ThemeController {
  ThemeController._();

  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static const String _prefsKey = 'app_theme_mode';

  /// Загружает сохранённый режим темы при старте приложения.
  /// Если выбор не сохранён — используем системную тему.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsKey);
    mode.value = value == 'dark'
        ? ThemeMode.dark
        : value == 'light'
            ? ThemeMode.light
            : ThemeMode.system;
  }

  /// Переключает тему и сохраняет выбор.
  static Future<void> setDark(bool isDark) async {
    mode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, isDark ? 'dark' : 'light');
  }

  /// Текущая тёмность с учётом системного режима.
  static bool get isDark {
    if (mode.value == ThemeMode.dark) return true;
    if (mode.value == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }
}
