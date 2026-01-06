import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_sqflite/drift_sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ---------- Таблицы ----------

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get email => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get name => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get date => dateTime()(); // Привязка к дню
  DateTimeColumn get endDate => dateTime().nullable()(); // для диапазона
  IntColumn get priority => integer().withDefault(const Constant(1))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
}

class TaskTags extends Table {
  IntColumn get taskId => integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId => integer().references(Tags, #id, onDelete: KeyAction.cascade)();
  @override
  Set<Column> get primaryKey => {taskId, tagId};
}

class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()(); // 'user' | 'ai'
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
}

class Plans extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()(); // срок, опционально
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

class UserSettings extends Table {
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  @override
  Set<Column> get primaryKey => {userId};
}

// ---------- База ----------

@DriftDatabase(
  tables: [Users, Tasks, Tags, TaskTags, ChatMessages, Plans, Notes, UserSettings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX idx_tasks_user_date ON tasks(user_id, date);');
          await customStatement('CREATE INDEX idx_tasks_user_completed ON tasks(user_id, is_completed);');
          await customStatement('CREATE INDEX idx_task_tags_tag ON task_tags(tag_id);');
          await customStatement('CREATE INDEX idx_chat_user_created ON chat_messages(user_id, created_at);');
          await customStatement('CREATE INDEX idx_plans_user ON plans(user_id);');
          await customStatement('CREATE INDEX idx_notes_user_created ON notes(user_id, created_at);');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Добавляем end_date и priority в tasks
            await customStatement('ALTER TABLE tasks ADD COLUMN end_date INTEGER;');
            await customStatement('ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 1;');
            // Обновим индекс по user/date (на случай старой схемы без него)
            await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_user_date ON tasks(user_id, date);');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_user_completed ON tasks(user_id, is_completed);');
          }
          if (from < 3) {
            // Повторная защита: убеждаемся, что колонки точно есть
            final result = await customSelect("PRAGMA table_info(tasks);").get();
            final columnNames = result.map((row) => row.data['name'] as String).toSet();
            if (!columnNames.contains('end_date')) {
              await customStatement('ALTER TABLE tasks ADD COLUMN end_date INTEGER;');
            }
            if (!columnNames.contains('priority')) {
              await customStatement('ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 1;');
            }
            await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_user_date ON tasks(user_id, date);');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_user_completed ON tasks(user_id, is_completed);');
          }
        },
        beforeOpen: (details) async {
          // Дополнительная защита: если колонок нет (старый файл без миграции), добавим.
          await customStatement(
              "PRAGMA foreign_keys = ON;"); // включаем FK на всякий случай

          // Проверяем наличие end_date и priority в tasks
          final result = await customSelect("PRAGMA table_info(tasks);").get();
          final columnNames = result.map((row) => row.data['name'] as String).toSet();
          if (!columnNames.contains('end_date')) {
            await customStatement('ALTER TABLE tasks ADD COLUMN end_date INTEGER;');
          }
          if (!columnNames.contains('priority')) {
            await customStatement('ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 1;');
          }
          // Индексы
          await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_user_date ON tasks(user_id, date);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_user_completed ON tasks(user_id, is_completed);');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'app.db'));
    return NativeDatabase.createInBackground(file);
  });
}

