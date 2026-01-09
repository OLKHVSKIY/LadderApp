import 'package:drift/drift.dart' as dr;
import '../app_database.dart' as db;
import '../user_session.dart';
import '../../models/task.dart' as model;
import 'task_file_repository.dart';

class TaskRepository {
  final db.AppDatabase database;
  TaskFileRepository? _fileRepository;
  bool _checkedSchema = false;
  
  TaskRepository(this.database);
  
  TaskFileRepository get _fileRepo {
    _fileRepository ??= TaskFileRepository(database);
    return _fileRepository!;
  }

  Future<void> _ensureTaskColumns() async {
    if (_checkedSchema) return;
    final result = await database.customSelect("PRAGMA table_info(tasks);").get();
    final columnNames = result.map((row) => row.data['name'] as String).toSet();
    if (!columnNames.contains('end_date')) {
      await database.customStatement('ALTER TABLE tasks ADD COLUMN end_date INTEGER;');
    }
    if (!columnNames.contains('priority')) {
      await database.customStatement('ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 1;');
    }
    _checkedSchema = true;
  }

  Future<int> addTask(model.Task task) async {
    final userId = UserSession.currentUserId;
    if (userId == null) throw Exception('Нет авторизованного пользователя');
    await _ensureTaskColumns();
    final taskId = await database.into(database.tasks).insert(
          db.TasksCompanion.insert(
            userId: userId,
            title: task.title,
            description: dr.Value(task.description),
            date: task.date,
            endDate: dr.Value(task.endDate),
            priority: dr.Value(task.priority),
            isCompleted: dr.Value(task.isCompleted),
            createdAt: dr.Value(DateTime.now()),
            updatedAt: dr.Value(DateTime.now()),
          ),
        );
    // Теги
    for (final tagName in task.tags) {
      final tagId = await _getOrCreateTag(tagName);
      await database.into(database.taskTags).insertOnConflictUpdate(
            db.TaskTagsCompanion(
              taskId: dr.Value(taskId),
              tagId: dr.Value(tagId),
            ),
          );
    }
    // Файлы
    if (task.attachedFiles != null && task.attachedFiles!.isNotEmpty) {
      await _fileRepo.saveTaskFiles(taskId, task.attachedFiles!);
    }
    return taskId;
  }

  Future<void> updateCompletion(int taskId, bool isCompleted) async {
    await (database.update(database.tasks)..where((t) => t.id.equals(taskId))).write(
      db.TasksCompanion(
        isCompleted: dr.Value(isCompleted),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
  }

  Future<List<model.Task>> tasksForDate(DateTime date) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return [];
    await _ensureTaskColumns();
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final rows = await (database.select(database.tasks)
          ..where((t) =>
              t.userId.equals(userId) &
              ((t.date.isBiggerOrEqualValue(dayStart) & t.date.isSmallerThanValue(dayEnd)) |
                  (t.endDate.isNotNull() &
                      t.date.isSmallerOrEqualValue(dayEnd) &
                      t.endDate.isBiggerOrEqualValue(dayStart)))))
        .get();

    final result = <model.Task>[];
    for (final row in rows) {
      final tags = await _tagsForTask(row.id);
      final files = await _fileRepo.loadTaskFiles(row.id);
      result.add(
        model.Task(
          id: row.id.toString(),
          title: row.title,
          description: row.description,
          priority: row.priority,
          tags: tags,
          date: row.date,
          endDate: row.endDate,
          isCompleted: row.isCompleted,
          attachedFiles: files.isNotEmpty ? files : null,
        ),
      );
    }
    return result;
  }

  Future<List<model.Task>> tasksForDateRange(DateTime startDate, DateTime endDate) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return [];
    await _ensureTaskColumns();
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1));

    final rows = await (database.select(database.tasks)
          ..where((t) =>
              t.userId.equals(userId) &
              ((t.date.isBiggerOrEqualValue(start) & t.date.isSmallerThanValue(end)) |
                  (t.endDate.isNotNull() &
                      ((t.date.isSmallerOrEqualValue(end) & t.endDate.isBiggerOrEqualValue(start)))))))
        .get();

    final result = <model.Task>[];
    for (final row in rows) {
      final tags = await _tagsForTask(row.id);
      final files = await _fileRepo.loadTaskFiles(row.id);
      result.add(
        model.Task(
          id: row.id.toString(),
          title: row.title,
          description: row.description,
          priority: row.priority,
          tags: tags,
          date: row.date,
          endDate: row.endDate,
          isCompleted: row.isCompleted,
          attachedFiles: files.isNotEmpty ? files : null,
        ),
      );
    }
    return result;
  }

  Future<List<String>> _tagsForTask(int taskId) async {
    final q = database.select(database.tags).join([
      dr.innerJoin(database.taskTags, database.taskTags.tagId.equalsExp(database.tags.id)),
    ])
      ..where(database.taskTags.taskId.equals(taskId));
    final rows = await q.get();
    return rows.map((r) => r.readTable(database.tags).name).toList();
  }

  Future<int> _getOrCreateTag(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw Exception('Tag name is empty');
    final existing = await (database.select(database.tags)
          ..where((t) => t.name.equals(normalized)))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    return database.into(database.tags).insert(db.TagsCompanion.insert(name: normalized));
  }

  Future<void> updateTask(int id, model.Task task, {bool? isCompleted}) async {
    await _ensureTaskColumns();
    await (database.update(database.tasks)..where((t) => t.id.equals(id))).write(
      db.TasksCompanion(
        title: dr.Value(task.title),
        description: dr.Value(task.description),
        date: dr.Value(task.date),
        endDate: dr.Value(task.endDate),
        priority: dr.Value(task.priority),
        isCompleted: isCompleted != null ? dr.Value(isCompleted) : dr.Value(task.isCompleted),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
    // Обновляем теги: удаляем старые, вставляем новые
    await (database.delete(database.taskTags)..where((tt) => tt.taskId.equals(id))).go();
    for (final tagName in task.tags) {
      final tagId = await _getOrCreateTag(tagName);
      await database.into(database.taskTags).insertOnConflictUpdate(
            db.TaskTagsCompanion(
              taskId: dr.Value(id),
              tagId: dr.Value(tagId),
            ),
          );
    }
    // Обновляем файлы
    if (task.attachedFiles != null && task.attachedFiles!.isNotEmpty) {
      await _fileRepo.saveTaskFiles(id, task.attachedFiles!);
    } else {
      await _fileRepo.deleteTaskFiles(id);
    }
  }

  Future<void> deleteTask(int id) async {
    await _ensureTaskColumns();
    // Удаляем файлы перед удалением задачи
    await _fileRepo.deleteTaskFiles(id);
    await (database.delete(database.tasks)..where((t) => t.id.equals(id))).go();
  }

  /// Поиск всех задач пользователя
  Future<List<model.Task>> searchAllTasks() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return [];
    await _ensureTaskColumns();

    final rows = await (database.select(database.tasks)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => dr.OrderingTerm.desc(t.updatedAt)]))
        .get();

    final result = <model.Task>[];
    for (final row in rows) {
      final tags = await _tagsForTask(row.id);
      final files = await _fileRepo.loadTaskFiles(row.id);
      result.add(
        model.Task(
          id: row.id.toString(),
          title: row.title,
          description: row.description,
          priority: row.priority,
          tags: tags,
          date: row.date,
          endDate: row.endDate,
          isCompleted: row.isCompleted,
          attachedFiles: files.isNotEmpty ? files : null,
        ),
      );
    }
    return result;
  }
}

