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
      ValueNotifier<ThemeMode>(ThemeMode.light);

  static const String _prefsKey = 'app_theme_mode';

  /// Загружает сохранённый режим темы при старте приложения.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsKey);
    mode.value = value == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  /// Переключает тему и сохраняет выбор.
  static Future<void> setDark(bool isDark) async {
    mode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, isDark ? 'dark' : 'light');
  }

  static bool get isDark => mode.value == ThemeMode.dark;
}
