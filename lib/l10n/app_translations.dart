import 'locale_controller.dart';
import 'translations_en.dart';
import 'translations_es.dart';
import 'translations_zh.dart';

/// Рантайм-локализация без gen-l10n.
///
/// Ключ перевода — исходная русская строка. [tr] смотрит на текущий язык
/// в [LocaleController] и достаёт перевод из карты соответствующего языка.
/// Если перевода нет (или язык русский) — возвращает исходную строку,
/// поэтому русский всегда работает как фолбэк.
///
/// Работает в любом коде (не только в виджетах), т.к. читает
/// [LocaleController.code] напрямую. UI обновляется через
/// ValueListenableBuilder на LocaleController.locale в MaterialApp.
///
/// Для строк с подстановками используйте плейсхолдеры `{0}`, `{1}` и т.д.
/// и передавайте значения через [args]. Пример:
/// `tr('Осталось {0} задач', [count])`.
String tr(String ru, [List<Object?>? args]) {
  String result;
  switch (LocaleController.code) {
    case 'en':
      result = translationsEn[ru] ?? ru;
      break;
    case 'es':
      result = translationsEs[ru] ?? ru;
      break;
    case 'zh':
      result = translationsZh[ru] ?? ru;
      break;
    default:
      result = ru;
  }
  if (args != null) {
    for (var i = 0; i < args.length; i++) {
      result = result.replaceAll('{$i}', '${args[i]}');
    }
  }
  return result;
}
