import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ---------- Таблицы ----------

// Sync-поля (uuid / updatedAt / isDeleted) добавлены в каждую таблицу, чтобы
// будущая синхронизация с бэкендом сводилась к «отправь строки с
// updatedAt > last_sync», а удаление было мягким (soft-delete) и переносимым
// между устройствами. uuid — стабильный глобальный идентификатор строки
// (autoIncrement id локален и на разных устройствах конфликтует).

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  TextColumn get email => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get name => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get date => dateTime()(); // Привязка к дню
  DateTimeColumn get endDate => dateTime().nullable()(); // для диапазона
  IntColumn get priority => integer().withDefault(const Constant(1))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get subtasks => text().nullable()(); // JSON-список подзадач/чек-листа
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  TextColumn get name => text().unique()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class TaskTags extends Table {
  IntColumn get taskId => integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId => integer().references(Tags, #id, onDelete: KeyAction.cascade)();
  TextColumn get uuid => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {taskId, tagId};
}

class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()(); // 'user' | 'ai'
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class Plans extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()(); // срок, опционально
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class UserSettings extends Table {
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get uuid => text().nullable()();
  TextColumn get name => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {userId};
}

class TaskFiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get taskId => integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get filePath => text()();
  TextColumn get fileType => text()(); // pdf, doc, docx, xls, xlsx, jpg, png, etc.
  IntColumn get fileSize => integer()(); // размер в байтах
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class NoteFiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get noteId => integer().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get filePath => text()();
  TextColumn get fileType => text()(); // pdf, doc, docx, xls, xlsx, jpg, png, etc.
  IntColumn get fileSize => integer()(); // размер в байтах
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class DelegatedTasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get originalTaskId => integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  IntColumn get fromUserId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get fromUserEmail => text()();
  TextColumn get fromUserName => text().nullable()();
  TextColumn get toUserEmail => text()();
  TextColumn get taskTitle => text()();
  TextColumn get taskDescription => text().nullable()();
  DateTimeColumn get taskDate => dateTime()();
  DateTimeColumn get taskEndDate => dateTime().nullable()();
  IntColumn get taskPriority => integer()();
  TextColumn get taskTags => text()(); // JSON массив тегов
  BoolColumn get isAccepted => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeclined => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class CustomTaskScreens extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class CustomTasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get screenId => integer().references(CustomTaskScreens, #id, onDelete: KeyAction.cascade)();
  IntColumn get creatorId => integer().references(Users, #id, onDelete: KeyAction.setNull).nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class CustomScreenUsers extends Table {
  IntColumn get screenId => integer().references(CustomTaskScreens, #id, onDelete: KeyAction.cascade)();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get uuid => text().nullable()();
  DateTimeColumn get addedAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {screenId, userId};
}

// Привычки (трекер) — отдельная сущность с собственными «цепочками»
// выполнения. scheduleMask — битовая маска дней недели (бит 0 = понедельник …
// бит 6 = воскресенье): 127 = каждый день, 31 = будни, 96 = выходные.
// colorValue/iconIndex ссылаются на палитру и список значков в коде
// (lib/models/habit.dart), чтобы не ломать tree-shaking иконок.
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  // К какому кастомному экрану привязана привычка. null = личная привычка на
  // главном экране задач.
  IntColumn get screenId => integer().references(CustomTaskScreens, #id, onDelete: KeyAction.cascade).nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFFFF3B30))();
  IntColumn get iconIndex => integer().withDefault(const Constant(0))();
  IntColumn get scheduleMask => integer().withDefault(const Constant(127))();
  // Период действия привычки. startDate — с какого дня привычка активна
  // (по умолчанию — день создания). endDate — по какой день включительно;
  // null = бессрочно.
  DateTimeColumn get startDate => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get endDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

// Отметки выполнения привычки по дням (day нормализован к полуночи).
class HabitCompletions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get habitId => integer().references(Habits, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get day => dateTime()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

// События — отметки в календаре, которые не закрываются галочкой, а просто
// отображаются (день рождения, годовщина и т.п.). Могут повторяться ежегодно.
class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable()();
  IntColumn get userId => integer().references(Users, #id, onDelete: KeyAction.cascade)();
  // К какому кастомному экрану привязано событие. null = на главном экране.
  IntColumn get screenId => integer().references(CustomTaskScreens, #id, onDelete: KeyAction.cascade).nullable()();
  TextColumn get title => text()();
  // Описание события (необязательное).
  TextColumn get description => text().nullable()();
  DateTimeColumn get date => dateTime()();
  // Повтор: true = каждый год (по месяцу/дню), false = один раз.
  BoolColumn get repeatYearly => boolean().withDefault(const Constant(false))();
  // Уведомления: за 1 день до и/или в день события.
  BoolColumn get notifyDayBefore => boolean().withDefault(const Constant(false))();
  BoolColumn get notifyOnDay => boolean().withDefault(const Constant(false))();
  // Путь к выбранной из галереи картинке (скопирована в documents).
  TextColumn get imagePath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

// ---------- База ----------

@DriftDatabase(
  tables: [Users, Tasks, Tags, TaskTags, ChatMessages, Plans, Notes, UserSettings, TaskFiles, NoteFiles, DelegatedTasks, CustomTaskScreens, CustomTasks, CustomScreenUsers, Habits, HabitCompletions, Events],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 14;

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
          await customStatement('CREATE INDEX idx_habits_user ON habits(user_id);');
          await customStatement('CREATE INDEX idx_habit_completions_habit ON habit_completions(habit_id, day);');
          await customStatement('CREATE INDEX idx_events_user_date ON events(user_id, date);');
        },
        onUpgrade: (m, from, to) async {
          if (from < 6) {
            // Добавляем таблицы для кастомных экранов задач
            await m.createTable(customTaskScreens);
            await m.createTable(customTasks);
          }
          if (from < 7) {
            // Добавляем поле creatorId в CustomTasks и таблицу CustomScreenUsers
            await customStatement('ALTER TABLE custom_tasks ADD COLUMN creator_id INTEGER REFERENCES users(id) ON DELETE SET NULL;');
            await m.createTable(customScreenUsers);
          }
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
          if (from < 4) {
            // Добавляем таблицы для файлов
            await m.createTable(taskFiles);
            await m.createTable(noteFiles);
            await customStatement('CREATE INDEX IF NOT EXISTS idx_task_files_task ON task_files(task_id);');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_note_files_note ON note_files(note_id);');
          }
          if (from < 5) {
            // Добавляем таблицу для делегированных задач
            await m.createTable(delegatedTasks);
            await customStatement('CREATE INDEX IF NOT EXISTS idx_delegated_tasks_to_email ON delegated_tasks(to_user_email);');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_delegated_tasks_accepted ON delegated_tasks(is_accepted, is_declined);');
          }
          if (from < 8) {
            // Sync-поля во всех таблицах: uuid (стабильный глобальный id),
            // updated_at (где не было — для дельта-синхронизации), is_deleted
            // (soft-delete). Существующим строкам uuid проставляем случайным
            // hex(randomblob), а updated_at — текущим временем.
            Future<void> addSyncColumns(String table,
                {bool addUpdatedAt = false}) async {
              final info =
                  await customSelect('PRAGMA table_info($table);').get();
              final cols =
                  info.map((r) => r.data['name'] as String).toSet();
              if (!cols.contains('uuid')) {
                await customStatement('ALTER TABLE $table ADD COLUMN uuid TEXT;');
                await customStatement(
                    "UPDATE $table SET uuid = lower(hex(randomblob(16))) WHERE uuid IS NULL;");
              }
              if (addUpdatedAt && !cols.contains('updated_at')) {
                await customStatement(
                    'ALTER TABLE $table ADD COLUMN updated_at INTEGER;');
                await customStatement(
                    "UPDATE $table SET updated_at = strftime('%s','now') WHERE updated_at IS NULL;");
              }
              if (!cols.contains('is_deleted')) {
                await customStatement(
                    'ALTER TABLE $table ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;');
              }
            }

            await addSyncColumns('users');
            await addSyncColumns('tasks');
            await addSyncColumns('tags', addUpdatedAt: true);
            await addSyncColumns('task_tags', addUpdatedAt: true);
            await addSyncColumns('chat_messages', addUpdatedAt: true);
            await addSyncColumns('plans');
            await addSyncColumns('notes');
            await addSyncColumns('user_settings');
            await addSyncColumns('task_files', addUpdatedAt: true);
            await addSyncColumns('note_files', addUpdatedAt: true);
            await addSyncColumns('delegated_tasks', addUpdatedAt: true);
            await addSyncColumns('custom_task_screens');
            await addSyncColumns('custom_tasks');
            await addSyncColumns('custom_screen_users', addUpdatedAt: true);
          }
          if (from < 9) {
            // Трекер привычек: отдельные сущности с цепочками выполнения.
            await m.createTable(habits);
            await m.createTable(habitCompletions);
            await customStatement('CREATE INDEX IF NOT EXISTS idx_habits_user ON habits(user_id);');
            await customStatement('CREATE INDEX IF NOT EXISTS idx_habit_completions_habit ON habit_completions(habit_id, day);');
          }
          if (from < 10) {
            // Период действия привычки (start_date/end_date).
            final cols = await customSelect('PRAGMA table_info(habits);').get();
            final names = cols.map((r) => r.data['name'] as String).toSet();
            if (!names.contains('start_date')) {
              await customStatement('ALTER TABLE habits ADD COLUMN start_date INTEGER;');
              await customStatement('UPDATE habits SET start_date = created_at WHERE start_date IS NULL;');
            }
            if (!names.contains('end_date')) {
              await customStatement('ALTER TABLE habits ADD COLUMN end_date INTEGER;');
            }
          }
          if (from < 11) {
            // Привязка привычки к кастомному экрану (screen_id, null = личная).
            final cols = await customSelect('PRAGMA table_info(habits);').get();
            final names = cols.map((r) => r.data['name'] as String).toSet();
            if (!names.contains('screen_id')) {
              await customStatement('ALTER TABLE habits ADD COLUMN screen_id INTEGER REFERENCES custom_task_screens(id) ON DELETE CASCADE;');
            }
          }
          if (from < 12) {
            // Таблица событий (день рождения и т.п. — отображаются, не закрываются).
            await m.createTable(events);
            await customStatement('CREATE INDEX IF NOT EXISTS idx_events_user_date ON events(user_id, date);');
          }
          if (from < 13) {
            // Описание события.
            final cols = await customSelect('PRAGMA table_info(events);').get();
            final names = cols.map((r) => r.data['name'] as String).toSet();
            if (!names.contains('description')) {
              await customStatement('ALTER TABLE events ADD COLUMN description TEXT;');
            }
          }
          if (from < 14) {
            // Подзадачи / чек-лист внутри задачи (JSON в колонке subtasks).
            final cols = await customSelect('PRAGMA table_info(tasks);').get();
            final names = cols.map((r) => r.data['name'] as String).toSet();
            if (!names.contains('subtasks')) {
              await customStatement('ALTER TABLE tasks ADD COLUMN subtasks TEXT;');
            }
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
          if (!columnNames.contains('subtasks')) {
            await customStatement('ALTER TABLE tasks ADD COLUMN subtasks TEXT;');
          }
          // Индексы
          await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_user_date ON tasks(user_id, date);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_tasks_user_completed ON tasks(user_id, is_completed);');

          // Подстраховка для периода привычек (если таблица была без колонок).
          final habitInfo = await customSelect("PRAGMA table_info(habits);").get();
          final habitCols =
              habitInfo.map((row) => row.data['name'] as String).toSet();
          if (habitCols.isNotEmpty && !habitCols.contains('start_date')) {
            await customStatement('ALTER TABLE habits ADD COLUMN start_date INTEGER;');
            await customStatement('UPDATE habits SET start_date = created_at WHERE start_date IS NULL;');
          }
          if (habitCols.isNotEmpty && !habitCols.contains('end_date')) {
            await customStatement('ALTER TABLE habits ADD COLUMN end_date INTEGER;');
          }
          if (habitCols.isNotEmpty && !habitCols.contains('screen_id')) {
            await customStatement('ALTER TABLE habits ADD COLUMN screen_id INTEGER REFERENCES custom_task_screens(id) ON DELETE CASCADE;');
          }

          // Подстраховка для описания событий.
          final eventInfo = await customSelect("PRAGMA table_info(events);").get();
          final eventCols =
              eventInfo.map((row) => row.data['name'] as String).toSet();
          if (eventCols.isNotEmpty && !eventCols.contains('description')) {
            await customStatement('ALTER TABLE events ADD COLUMN description TEXT;');
          }
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

