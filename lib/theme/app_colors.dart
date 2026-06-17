import 'package:flutter/material.dart';

/// Семантические цвета приложения, зависящие от текущей темы.
///
/// Вместо жёстко прописанных Colors.white/Colors.black по всему коду берём
/// цвета отсюда: `AppColors.of(context).surface` и т.п. Значения сами
/// подстраиваются под светлую/тёмную тему по [Theme.of(context).brightness].
class AppColors {
  final Brightness brightness;
  const AppColors(this.brightness);

  static AppColors of(BuildContext context) =>
      AppColors(Theme.of(context).brightness);

  bool get isDark => brightness == Brightness.dark;

  /// Фон экрана.
  Color get background => isDark ? const Color(0xFF000000) : Colors.white;

  /// Поверхность карточек/панелей.
  Color get surface => isDark ? const Color(0xFF1C1C1E) : Colors.white;

  /// Приподнятая поверхность (модалки, шторки).
  Color get elevatedSurface => isDark ? const Color(0xFF2C2C2E) : Colors.white;

  /// Второстепенный фон (поля, бейджи, лёгкие блоки).
  Color get surfaceVariant =>
      isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F5);

  /// Основной текст.
  Color get textPrimary => isDark ? Colors.white : Colors.black;

  /// Второстепенный текст (подписи).
  Color get textSecondary =>
      isDark ? const Color(0xFFAEAEB2) : const Color(0xFF6E6E73);

  /// Третичный текст (плейсхолдеры, мелкие подписи).
  Color get textTertiary =>
      isDark ? const Color(0xFF8E8E93) : const Color(0xFF999999);

  /// Границы и разделители.
  Color get border => isDark ? const Color(0xFF38383A) : const Color(0xFFF5F5F5);

  /// Разделительные линии.
  Color get divider =>
      isDark ? const Color(0xFF38383A) : const Color(0xFFEEEEEE);

  /// Цвет иконок по умолчанию.
  Color get icon => isDark ? Colors.white : Colors.black;

  /// Инверсный цвет (для тёмных кнопок на светлом и наоборот).
  Color get inverseSurface => isDark ? Colors.white : Colors.black;

  /// Текст на инверсной поверхности.
  Color get onInverseSurface => isDark ? Colors.black : Colors.white;
}
