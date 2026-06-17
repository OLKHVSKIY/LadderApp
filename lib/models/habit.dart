import 'package:flutter/cupertino.dart';

/// Палитра цветов и набор значков привычек.
///
/// Значки берутся по индексу из фиксированного списка const-IconData — это
/// сохраняет tree-shaking иконок (хранить codePoint напрямую нельзя, иначе
/// Flutter ругается и отключает оптимизацию). В БД у привычки лежит индекс.
class HabitPalette {
  HabitPalette._();

  // Системные цвета iOS.
  static const List<int> colors = <int>[
    0xFFFF3B30, // красный
    0xFFFF9500, // оранжевый
    0xFFFFCC00, // жёлтый
    0xFF34C759, // зелёный
    0xFF00C7BE, // бирюзовый
    0xFF007AFF, // синий
    0xFF5856D6, // индиго
    0xFFAF52DE, // фиолетовый
    0xFFFF2D55, // розовый
  ];

  static const List<IconData> icons = <IconData>[
    CupertinoIcons.flame,
    CupertinoIcons.book,
    CupertinoIcons.drop,
    CupertinoIcons.heart,
    CupertinoIcons.bolt,
    CupertinoIcons.sun_max,
    CupertinoIcons.moon,
    CupertinoIcons.bed_double,
    CupertinoIcons.sportscourt,
    CupertinoIcons.paintbrush,
    CupertinoIcons.music_note,
    CupertinoIcons.cart,
  ];

  static int colorIndex(int colorValue) {
    final i = colors.indexOf(colorValue);
    return i < 0 ? 0 : i;
  }
}

/// Привычка — повторяющееся действие с собственной «цепочкой» выполнения.
class Habit {
  final int? id; // null = ещё не сохранена
  final String title;
  final String? description;
  final int colorValue;
  final int iconIndex;
  final int scheduleMask; // битовая маска дней недели (бит 0 = пн … бит 6 = вс)
  final DateTime? startDate; // с какого дня активна (null = трактуем как сегодня)
  final DateTime? endDate; // по какой день включительно; null = бессрочно

  const Habit({
    this.id,
    required this.title,
    this.description,
    required this.colorValue,
    required this.iconIndex,
    required this.scheduleMask,
    this.startDate,
    this.endDate,
  });

  // Пресеты расписания.
  static const int maskDaily = 127; // 0b1111111
  static const int maskWeekdays = 31; // пн–пт
  static const int maskWeekends = 96; // сб+вс

  // Пресеты длительности (в днях от старта, включительно). 0 = бессрочно.
  static const List<int> durationPresets = <int>[0, 21, 30, 66];

  Color get color => Color(colorValue);

  IconData get icon =>
      HabitPalette.icons[iconIndex.clamp(0, HabitPalette.icons.length - 1)];

  /// Запланирована ли привычка на этот день недели (1 = пн … 7 = вс).
  bool isScheduledOn(int weekday) =>
      ((scheduleMask >> (weekday - 1)) & 1) == 1;

  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Входит ли день в период действия привычки [startDate, endDate].
  bool isWithinPeriod(DateTime day) {
    final d = _norm(day);
    if (startDate != null && d.isBefore(_norm(startDate!))) return false;
    if (endDate != null && d.isAfter(_norm(endDate!))) return false;
    return true;
  }

  /// Активна ли привычка в этот день: и по расписанию, и по периоду.
  bool isActiveOn(DateTime day) =>
      isWithinPeriod(day) && isScheduledOn(day.weekday);

  /// Русский ключ для подписи расписания (переводится через tr()).
  String get scheduleLabel {
    switch (scheduleMask) {
      case maskDaily:
        return 'Каждый день';
      case maskWeekdays:
        return 'По будням';
      case maskWeekends:
        return 'Выходные';
      default:
        return 'Свой график';
    }
  }

  /// Кол-во дней в пресете, если период ровно совпадает с одним из них; иначе
  /// null (бессрочно или произвольный диапазон).
  int? get durationPresetDays {
    if (endDate == null) return 0;
    final start = _norm(startDate ?? DateTime.now());
    final days = _norm(endDate!).difference(start).inDays + 1;
    return durationPresets.contains(days) ? days : null;
  }
}

/// Привычка вместе с посчитанной статистикой на текущий день.
class HabitWithStats {
  final Habit habit;
  final int streak; // длина текущей цепочки
  final bool completedToday; // отмечена ли сегодня
  final bool scheduledToday; // запланирована ли на сегодня
  final bool atRisk; // цепочка жива, но сегодня ещё не отмечена

  const HabitWithStats({
    required this.habit,
    required this.streak,
    required this.completedToday,
    required this.scheduledToday,
    required this.atRisk,
  });
}
