import 'package:drift/drift.dart' as dr;
import 'package:uuid/uuid.dart';
// Скрываем сгенерированный Drift-класс строки Event, чтобы не конфликтовал с
// нашей доменной моделью Event из models/event.dart.
import '../app_database.dart' hide Event;
import '../../models/event.dart';

class EventRepository {
  final AppDatabase db;
  EventRepository(this.db);

  /// Создать событие, вернуть его id. [screenId] — кастомный экран (null =
  /// событие на главном экране задач).
  Future<int> addEvent(Event e, int userId, {int? screenId}) async {
    return db.into(db.events).insert(
          EventsCompanion.insert(
            uuid: dr.Value(const Uuid().v4()),
            userId: userId,
            screenId: dr.Value(screenId),
            title: e.title,
            description: dr.Value(e.description),
            date: e.date,
            repeatYearly: dr.Value(e.repeatYearly),
            notifyDayBefore: dr.Value(e.notifyDayBefore),
            notifyOnDay: dr.Value(e.notifyOnDay),
            imagePath: dr.Value(e.imagePath),
          ),
        );
  }

  /// Обновить существующее событие.
  Future<void> updateEvent(Event e) async {
    if (e.id == null) return;
    await (db.update(db.events)..where((t) => t.id.equals(e.id!))).write(
      EventsCompanion(
        title: dr.Value(e.title),
        description: dr.Value(e.description),
        date: dr.Value(e.date),
        repeatYearly: dr.Value(e.repeatYearly),
        notifyDayBefore: dr.Value(e.notifyDayBefore),
        notifyOnDay: dr.Value(e.notifyOnDay),
        imagePath: dr.Value(e.imagePath),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
  }

  /// Удалить событие (soft-delete для будущей синхронизации).
  Future<void> deleteEvent(int id) async {
    await (db.update(db.events)..where((t) => t.id.equals(id))).write(
      EventsCompanion(
        isDeleted: const dr.Value(true),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
  }

  /// Загрузить ВСЕ события пользователя (без фильтра по дню). [screenId] == null →
  /// события главного экрана (screen_id IS NULL); заданный → конкретного экрана.
  /// Нужно для меток под днями в календаре недели.
  Future<List<Event>> loadAllEvents(int userId, {int? screenId}) async {
    final rows = await (db.select(db.events)
          ..where((t) =>
              t.userId.equals(userId) &
              t.isDeleted.equals(false) &
              (screenId == null
                  ? t.screenId.isNull()
                  : t.screenId.equals(screenId))))
        .get();
    return rows
        .map((r) => Event(
              id: r.id,
              title: r.title,
              description: r.description,
              date: r.date,
              repeatYearly: r.repeatYearly,
              notifyDayBefore: r.notifyDayBefore,
              notifyOnDay: r.notifyOnDay,
              imagePath: r.imagePath,
            ))
        .toList();
  }

  /// Загрузить события пользователя, попадающие на [day]. [screenId] == null →
  /// события главного экрана (screen_id IS NULL); заданный → конкретного экрана.
  ///
  /// Ежегодные события фильтруем в Dart (по месяцу/дню), т.к. их нельзя выразить
  /// простым диапазоном дат. Событий немного — производительность не страдает.
  Future<List<Event>> loadEventsForDate(
      int userId, DateTime day, {int? screenId}) async {
    final all = await loadAllEvents(userId, screenId: screenId);
    return all.where((e) => e.occursOn(day)).toList();
  }
}
