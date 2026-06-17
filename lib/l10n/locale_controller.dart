import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Глобальный контроллер языка приложения.
///
/// Хранит выбранную [Locale] в [ValueNotifier], чтобы [MaterialApp] мог
/// перестраиваться через [ValueListenableBuilder], а настройки — менять язык
/// из любого места без Provider/Bloc. Значение сохраняется в SharedPreferences.
///
/// Поддерживаемые языки: русский (ru), английский (en), испанский (es),
/// китайский (zh).
class LocaleController {
  LocaleController._();

  static final ValueNotifier<Locale> locale =
      ValueNotifier<Locale>(const Locale('ru'));

  static const String _prefsKey = 'app_locale';

  /// Все поддерживаемые языки с подписями для меню настроек.
  static const Map<String, String> supported = {
    'ru': 'Русский',
    'en': 'English',
    'es': 'Español',
    'zh': '中文',
  };

  /// Загружает сохранённый язык при старте приложения.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null && supported.containsKey(code)) {
      locale.value = Locale(code);
    }
  }

  /// Меняет язык и сохраняет выбор.
  static Future<void> setLanguage(String code) async {
    if (!supported.containsKey(code)) return;
    locale.value = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
  }

  /// Текущий код языка (ru/en/es/zh).
  static String get code => locale.value.languageCode;

  /// Человекочитаемая подпись текущего языка для настроек.
  static String get label => supported[code] ?? 'Русский';

  /// Подпись по коду языка.
  static String labelFor(String code) => supported[code] ?? code;
}
