import 'package:shared_preferences/shared_preferences.dart';

/// Снимок состояния серии (стрика) выполнения задач.
class StreakInfo {
  final int current; // текущая длина серии (0, если прервана)
  final int best; // рекорд
  final bool completedToday; // сегодня уже отмечена задача
  final bool atRisk; // серия жива, но сегодня ещё ничего не отмечено

  const StreakInfo({
    required this.current,
    required this.best,
    required this.completedToday,
    required this.atRisk,
  });
}

/// Хранит и считает «серию» выполнения задач (как в Duolingo).
///
/// День определяется по локальному времени устройства (`DateTime.now()`),
/// то есть зависит от часового пояса/часов в настройках телефона —
/// геолокация не нужна. Данные лежат в SharedPreferences.
class StreakService {
  static const _kCount = 'streak_count';
  static const _kLast = 'streak_last_date';
  static const _kBest = 'streak_best';

  /// Последнее известное состояние серии в этой сессии. Обновляется при
  /// каждом [getInfo]/[recordCompletion]. Нужно, чтобы виджеты могли показать
  /// корректное значение сразу (без мерцания «неактивно → активно», пока идёт
  /// асинхронная загрузка из SharedPreferences).
  static StreakInfo? cached;

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Текущее состояние серии без изменения данных.
  static Future<StreakInfo> getInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kCount) ?? 0;
    final best = prefs.getInt(_kBest) ?? 0;
    final last = prefs.getString(_kLast);

    final now = DateTime.now();
    final todayKey = _dateKey(now);
    final yesterdayKey = _dateKey(now.subtract(const Duration(days: 1)));

    final StreakInfo info;
    if (last == todayKey) {
      info = StreakInfo(
          current: count, best: best, completedToday: true, atRisk: false);
    } else if (last == yesterdayKey) {
      // Серия ещё жива, но сегодня задача не отмечена.
      info = StreakInfo(
          current: count, best: best, completedToday: false, atRisk: true);
    } else {
      // Пропущен день — серия прервана.
      info = StreakInfo(
          current: 0, best: best, completedToday: false, atRisk: false);
    }
    cached = info;
    return info;
  }

  /// Зафиксировать выполнение задачи сегодня и продлить/начать серию.
  static Future<StreakInfo> recordCompletion() async {
    final prefs = await SharedPreferences.getInstance();
    var count = prefs.getInt(_kCount) ?? 0;
    var best = prefs.getInt(_kBest) ?? 0;
    final last = prefs.getString(_kLast);

    final now = DateTime.now();
    final todayKey = _dateKey(now);
    final yesterdayKey = _dateKey(now.subtract(const Duration(days: 1)));

    if (last == todayKey) {
      // Уже засчитано сегодня — ничего не меняем.
      final info = StreakInfo(
          current: count, best: best, completedToday: true, atRisk: false);
      cached = info;
      return info;
    }

    if (last == yesterdayKey) {
      count += 1; // продлеваем серию
    } else {
      count = 1; // начинаем новую серию
    }
    if (count > best) best = count;

    await prefs.setInt(_kCount, count);
    await prefs.setInt(_kBest, best);
    await prefs.setString(_kLast, todayKey);

    final info = StreakInfo(
        current: count, best: best, completedToday: true, atRisk: false);
    cached = info;
    return info;
  }
}
