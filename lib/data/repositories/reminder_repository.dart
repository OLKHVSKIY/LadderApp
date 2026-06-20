import 'package:drift/drift.dart' as dr;
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../../models/reminder_model.dart';

/// Доступ к напоминаниям (таблица reminders).
class ReminderRepository {
  final AppDatabase db;
  ReminderRepository(this.db);

  Reminder _toModel(ReminderRow row) => Reminder(
        id: row.id,
        userId: row.userId,
        ownerType: row.ownerType,
        ownerId: row.ownerId,
        title: row.title,
        body: row.body,
        fireAt: row.fireAt,
        repeatRule: row.repeatRule,
        snoozedUntil: row.snoozedUntil,
        isEnabled: row.isEnabled,
      );

  /// Создать напоминание, вернуть его id.
  Future<int> addReminder(Reminder r) async {
    return db.into(db.reminders).insert(
          RemindersCompanion.insert(
            uuid: dr.Value(const Uuid().v4()),
            userId: r.userId,
            ownerType: dr.Value(r.ownerType),
            ownerId: dr.Value(r.ownerId),
            title: r.title,
            body: dr.Value(r.body),
            fireAt: r.fireAt,
            repeatRule: dr.Value(r.repeatRule),
            snoozedUntil: dr.Value(r.snoozedUntil),
            isEnabled: dr.Value(r.isEnabled),
          ),
        );
  }

  /// Обновить существующее напоминание.
  Future<void> updateReminder(Reminder r) async {
    if (r.id == null) return;
    await (db.update(db.reminders)..where((t) => t.id.equals(r.id!))).write(
      RemindersCompanion(
        ownerType: dr.Value(r.ownerType),
        ownerId: dr.Value(r.ownerId),
        title: dr.Value(r.title),
        body: dr.Value(r.body),
        fireAt: dr.Value(r.fireAt),
        repeatRule: dr.Value(r.repeatRule),
        snoozedUntil: dr.Value(r.snoozedUntil),
        isEnabled: dr.Value(r.isEnabled),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
  }

  /// Отложить напоминание («snooze») на заданную длительность от текущего момента.
  Future<void> snooze(int id, Duration by) async {
    await (db.update(db.reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        snoozedUntil: dr.Value(DateTime.now().add(by)),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
  }

  /// Удалить напоминание (soft-delete для будущей синхронизации).
  Future<void> deleteReminder(int id) async {
    await (db.update(db.reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        isDeleted: const dr.Value(true),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
  }

  /// Удалить все напоминания, привязанные к сущности (например, к задаче).
  Future<void> deleteForOwner(String ownerType, int ownerId) async {
    await (db.update(db.reminders)
          ..where((t) => t.ownerType.equals(ownerType) & t.ownerId.equals(ownerId)))
        .write(
      RemindersCompanion(
        isDeleted: const dr.Value(true),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
  }

  /// Все активные напоминания пользователя.
  Future<List<Reminder>> loadAll(int userId) async {
    final rows = await (db.select(db.reminders)
          ..where((t) => t.userId.equals(userId) & t.isDeleted.equals(false)))
        .get();
    return rows.map(_toModel).toList();
  }

  /// Напоминания, привязанные к конкретной сущности.
  Future<List<Reminder>> loadForOwner(String ownerType, int ownerId) async {
    final rows = await (db.select(db.reminders)
          ..where((t) =>
              t.ownerType.equals(ownerType) &
              t.ownerId.equals(ownerId) &
              t.isDeleted.equals(false)))
        .get();
    return rows.map(_toModel).toList();
  }
}
