import 'package:drift/drift.dart' as dr;
import 'package:uuid/uuid.dart';
// Скрываем сгенерированный Drift-класс строки Habit, чтобы не конфликтовал с
// нашей доменной моделью Habit из models/habit.dart.
import '../app_database.dart' hide Habit;
import '../../models/habit.dart';

class HabitRepository {
  final AppDatabase db;
  HabitRepository(this.db);

  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Создать привычку, вернуть её id. [screenId] — кастомный экран, к которому
  /// привязана привычка (null = личная привычка на главном экране задач).
  Future<int> addHabit(Habit h, int userId, {int? screenId}) async {
    return db.into(db.habits).insert(
          HabitsCompanion.insert(
            uuid: dr.Value(const Uuid().v4()),
            userId: userId,
            screenId: dr.Value(screenId),
            title: h.title,
            description: dr.Value(h.description),
            colorValue: dr.Value(h.colorValue),
            iconIndex: dr.Value(h.iconIndex),
            scheduleMask: dr.Value(h.scheduleMask),
            startDate: dr.Value(_norm(h.startDate ?? DateTime.now())),
            endDate: dr.Value(h.endDate == null ? null : _norm(h.endDate!)),
          ),
        );
  }

  /// Обновить существующую привычку.
  Future<void> updateHabit(Habit h) async {
    if (h.id == null) return;
    await (db.update(db.habits)..where((t) => t.id.equals(h.id!))).write(
      HabitsCompanion(
        title: dr.Value(h.title),
        description: dr.Value(h.description),
        colorValue: dr.Value(h.colorValue),
        iconIndex: dr.Value(h.iconIndex),
        scheduleMask: dr.Value(h.scheduleMask),
        startDate: dr.Value(_norm(h.startDate ?? DateTime.now())),
        endDate: dr.Value(h.endDate == null ? null : _norm(h.endDate!)),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
  }

  /// Удалить привычку (soft-delete для будущей синхронизации).
  Future<void> deleteHabit(int id) async {
    await (db.update(db.habits)..where((t) => t.id.equals(id))).write(
      HabitsCompanion(
        isDeleted: dr.Value(true),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
  }

  /// Переключить отметку выполнения привычки на день. Возвращает новое
  /// состояние (true = теперь выполнено).
  Future<bool> toggleCompletion(int habitId, DateTime day) async {
    final d = _norm(day);
    final existing = await (db.select(db.habitCompletions)
          ..where((t) => t.habitId.equals(habitId) & t.day.equals(d)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.habitCompletions).insert(
            HabitCompletionsCompanion.insert(
              uuid: dr.Value(const Uuid().v4()),
              habitId: habitId,
              day: d,
            ),
          );
      return true;
    }
    final nowDeleted = !existing.isDeleted;
    await (db.update(db.habitCompletions)
          ..where((t) => t.id.equals(existing.id)))
        .write(
      HabitCompletionsCompanion(
        isDeleted: dr.Value(nowDeleted),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
    return !nowDeleted;
  }

  /// Загрузить привычки пользователя с посчитанной статистикой на [today].
  /// [screenId] == null → личные привычки главного экрана (screen_id IS NULL);
  /// заданный → привычки конкретного кастомного экрана.
  Future<List<HabitWithStats>> loadHabitsWithStats(
      int userId, DateTime today, {int? screenId}) async {
    final habitRows = await (db.select(db.habits)
          ..where((t) =>
              t.userId.equals(userId) &
              t.isDeleted.equals(false) &
              (screenId == null
                  ? t.screenId.isNull()
                  : t.screenId.equals(screenId)))
          ..orderBy([(t) => dr.OrderingTerm.asc(t.id)]))
        .get();
    if (habitRows.isEmpty) return [];

    final ids = habitRows.map((e) => e.id).toList();
    final comps = await (db.select(db.habitCompletions)
          ..where((t) => t.habitId.isIn(ids) & t.isDeleted.equals(false)))
        .get();

    final byHabit = <int, Set<DateTime>>{};
    for (final c in comps) {
      byHabit.putIfAbsent(c.habitId, () => <DateTime>{}).add(_norm(c.day));
    }

    final t = _norm(today);
    final result = <HabitWithStats>[];
    for (final r in habitRows) {
      final habit = Habit(
        id: r.id,
        title: r.title,
        description: r.description,
        colorValue: r.colorValue,
        iconIndex: r.iconIndex,
        scheduleMask: r.scheduleMask,
        startDate: r.startDate,
        endDate: r.endDate,
      );
      final done = byHabit[r.id] ?? <DateTime>{};
      final streak = _streak(done, r.scheduleMask, t, r.startDate);
      final completedToday = done.contains(t);
      // Привычка активна на день только если попадает и в расписание, и в период.
      final scheduledToday = habit.isActiveOn(t);
      result.add(HabitWithStats(
        habit: habit,
        streak: streak,
        completedToday: completedToday,
        scheduledToday: scheduledToday,
        atRisk: scheduledToday && !completedToday && streak > 0,
      ));
    }
    return result;
  }

  /// Длина текущей цепочки: идём назад от сегодня по запланированным дням,
  /// считаем подряд выполненные. Сегодня, если ещё не отмечено, цепочку не
  /// рвёт (даём шанс отметить позже).
  int _streak(Set<DateTime> done, int mask, DateTime today, DateTime? start) {
    final startDay = start == null ? null : _norm(start);
    int streak = 0;
    DateTime cursor = today;
    int guard = 0;
    while (guard++ < 800) {
      // Не уходим раньше даты старта привычки.
      if (startDay != null && cursor.isBefore(startDay)) break;
      final scheduled = ((mask >> (cursor.weekday - 1)) & 1) == 1;
      if (scheduled) {
        if (done.contains(cursor)) {
          streak++;
        } else if (cursor == today) {
          // сегодня ещё не отмечено — не прерываем
        } else {
          break;
        }
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
