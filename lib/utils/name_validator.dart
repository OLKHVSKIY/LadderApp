/// Валидация имени пользователя: ограничение длины и фильтр нецензурной
/// лексики. Эмодзи разрешены (для проверки на мат они просто игнорируются).
class NameValidator {
  NameValidator._();

  /// Максимум видимых символов (рун — эмодзи считается за 1).
  static const int maxLength = 24;
  static const int minLength = 2;

  /// Мягкий лимит для поля ввода в UTF-16 единицах — с запасом, чтобы эмодзи
  /// не обрезались; точная проверка по рунам идёт в [validate].
  static const int inputMaxLength = 60;

  // Корни нецензурных слов (рус. + англ.). Проверяются как подстроки в
  // нормализованном виде (строчные, только буквы, схлопнутые повторы).
  static const List<String> _banned = <String>[
    // RU
    'хуй', 'хуе', 'хуё', 'хуя', 'хуйн', 'хуйл',
    'пизд', 'пезд',
    'ебал', 'ебан', 'ебат', 'ебуч', 'ёбан', 'еблан', 'выеб', 'наеб', 'уеб',
    'отъеб', 'разъеб', 'въеб', 'заеб', 'долбоеб', 'долбоёб',
    'бляд', 'блят', 'блэт', 'блеад',
    'сука', 'суки', 'сучар',
    'залуп', 'манда', 'мудак', 'мудил', 'мудозв',
    'гондон', 'гандон', 'пидор', 'пидар', 'пидр',
    'дроч', 'шлюх', 'мраз', 'гнид',
    // EN
    'fuck', 'fuk', 'fck', 'shit', 'bitch', 'cunt', 'asshole', 'dick',
    'pussy', 'nigger', 'nigga', 'faggot', 'whore', 'slut', 'bastard', 'motherfuck',
  ];

  /// Возвращает русский ключ ошибки для tr() или null, если имя корректно.
  static String? validate(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return 'Введите имя';
    final len = name.runes.length;
    if (len < minLength) return 'Имя слишком короткое';
    if (len > maxLength) return 'Имя слишком длинное';
    if (_hasProfanity(name)) return 'Такое имя нельзя';
    return null;
  }

  static bool _hasProfanity(String name) {
    final lower = name.toLowerCase();
    // Оставляем только буквы (латиница + кириллица), выкидывая эмодзи,
    // пробелы, цифры и пунктуацию — чтобы не обойти фильтр разделителями.
    final letters = lower.replaceAll(RegExp(r'[^a-zа-яё]'), '');
    if (letters.isEmpty) return false;
    // Схлопываем повторяющиеся буквы (хуууй → хуй).
    final collapsed =
        letters.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
    for (final w in _banned) {
      if (collapsed.contains(w) || letters.contains(w)) return true;
    }
    return false;
  }
}
