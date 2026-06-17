/// Событие — отметка в календаре (день рождения, годовщина и т.п.).
///
/// Главное отличие от задачи: событие не закрывается галочкой, оно просто
/// отображается на выбранный день. Может повторяться каждый год.
class Event {
  final int? id; // null = ещё не сохранено
  final String title;
  final String? description; // необязательное описание
  final DateTime date;
  final bool repeatYearly; // true = каждый год, false = один раз
  final bool notifyDayBefore; // напомнить за 1 день
  final bool notifyOnDay; // напомнить в день события
  final String? imagePath; // путь к картинке из галереи (null = без картинки)

  const Event({
    this.id,
    required this.title,
    this.description,
    required this.date,
    this.repeatYearly = false,
    this.notifyDayBefore = false,
    this.notifyOnDay = false,
    this.imagePath,
  });

  /// Происходит ли событие в указанный день. Для ежегодного сравниваем
  /// только месяц и день, для разового — полную дату.
  bool occursOn(DateTime day) {
    if (repeatYearly) {
      return date.month == day.month && date.day == day.day;
    }
    return date.year == day.year &&
        date.month == day.month &&
        date.day == day.day;
  }

  Event copyWith({DateTime? date}) => Event(
        id: id,
        title: title,
        description: description,
        date: date ?? this.date,
        repeatYearly: repeatYearly,
        notifyDayBefore: notifyDayBefore,
        notifyOnDay: notifyOnDay,
        imagePath: imagePath,
      );
}
