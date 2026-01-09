import 'package:drift/drift.dart' as dr;
import 'package:drift/drift.dart' show OrderingTerm;
import '../app_database.dart' as db;
import '../user_session.dart';
import '../../models/task.dart' as model;
import 'task_file_repository.dart';

class DelegatedTaskRepository {
  final db.AppDatabase database;
  final TaskFileRepository _fileRepository;

  DelegatedTaskRepository(this.database) : _fileRepository = TaskFileRepository(database);

  /// Делегировать задачу другому пользователю
  Future<void> delegateTask({
    required int taskId,
    required String toUserEmail,
    required bool deleteFromMe,
  }) async {
    final userId = UserSession.currentUserId;
    if (userId == null) throw Exception('Нет авторизованного пользователя');

    // Получаем задачу
    final taskRow = await (database.select(database.tasks)..where((t) => t.id.equals(taskId))).getSingle();
    
    // Получаем информацию о пользователе
    final userRow = await (database.select(database.users)..where((u) => u.id.equals(userId))).getSingle();
    
    // Получаем теги задачи
    final tags = await _getTagsForTask(taskId);
    final tagsJson = tags.join(',');

    // Создаем запись о делегированной задаче
    await database.into(database.delegatedTasks).insert(
      db.DelegatedTasksCompanion.insert(
        originalTaskId: taskId,
        fromUserId: userId,
        fromUserEmail: userRow.email,
        fromUserName: dr.Value(userRow.name),
        toUserEmail: toUserEmail,
        taskTitle: taskRow.title,
        taskDescription: dr.Value(taskRow.description),
        taskDate: taskRow.date,
        taskEndDate: dr.Value(taskRow.endDate),
        taskPriority: taskRow.priority,
        taskTags: tagsJson,
      ),
    );

    // Если нужно удалить у отправителя
    if (deleteFromMe) {
      await (database.delete(database.tasks)..where((t) => t.id.equals(taskId))).go();
    }
  }

  /// Получить делегированные задачи для текущего пользователя
  Future<List<DelegatedTaskInfo>> getPendingDelegatedTasks() async {
    final userEmail = UserSession.currentEmail;
    if (userEmail == null) return [];

    final rows = await (database.select(database.delegatedTasks)
          ..where((dt) => dt.toUserEmail.equals(userEmail))
          ..where((dt) => dt.isAccepted.equals(false))
          ..where((dt) => dt.isDeclined.equals(false))
          ..orderBy([(dt) => OrderingTerm.desc(dt.createdAt)]))
        .get();

    return rows.map((row) {
      final tags = row.taskTags.isNotEmpty 
          ? row.taskTags.split(',').where((t) => t.isNotEmpty).map((t) => t.toString()).toList() 
          : <String>[];
      return DelegatedTaskInfo(
        id: row.id,
        originalTaskId: row.originalTaskId,
        fromUserEmail: row.fromUserEmail,
        fromUserName: row.fromUserName,
        taskTitle: row.taskTitle,
        taskDescription: row.taskDescription,
        taskDate: row.taskDate,
        taskEndDate: row.taskEndDate,
        taskPriority: row.taskPriority,
        taskTags: tags,
        createdAt: row.createdAt,
      );
    }).toList();
  }

  /// Принять делегированную задачу
  Future<void> acceptDelegatedTask(int delegatedTaskId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) throw Exception('Нет авторизованного пользователя');

    final delegatedRow = await (database.select(database.delegatedTasks)
          ..where((dt) => dt.id.equals(delegatedTaskId)))
        .getSingle();

    // Создаем задачу для получателя
    final taskId = await database.into(database.tasks).insert(
      db.TasksCompanion.insert(
        userId: userId,
        title: delegatedRow.taskTitle,
        description: dr.Value(delegatedRow.taskDescription),
        date: delegatedRow.taskDate,
        endDate: dr.Value(delegatedRow.taskEndDate),
        priority: dr.Value(delegatedRow.taskPriority),
        isCompleted: dr.Value(false),
        createdAt: dr.Value(DateTime.now()),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );

    // Копируем теги
    if (delegatedRow.taskTags.isNotEmpty) {
      final tags = delegatedRow.taskTags.split(',').where((t) => t.isNotEmpty).toList();
      for (final tagName in tags) {
        final tagId = await _getOrCreateTag(tagName);
        await database.into(database.taskTags).insertOnConflictUpdate(
          db.TaskTagsCompanion(
            taskId: dr.Value(taskId),
            tagId: dr.Value(tagId),
          ),
        );
      }
    }

    // Копируем файлы, если есть
    if (delegatedRow.originalTaskId != null) {
      final originalFiles = await _fileRepository.loadTaskFiles(delegatedRow.originalTaskId);
      if (originalFiles.isNotEmpty) {
        await _fileRepository.saveTaskFiles(taskId, originalFiles);
      }
    }

    // Помечаем как принятую
    await (database.update(database.delegatedTasks)..where((dt) => dt.id.equals(delegatedTaskId))).write(
      db.DelegatedTasksCompanion(
        isAccepted: dr.Value(true),
      ),
    );
  }

  /// Отклонить делегированную задачу
  Future<void> declineDelegatedTask(int delegatedTaskId) async {
    await (database.update(database.delegatedTasks)..where((dt) => dt.id.equals(delegatedTaskId))).write(
      db.DelegatedTasksCompanion(
        isDeclined: dr.Value(true),
      ),
    );
  }

  Future<List<String>> _getTagsForTask(int taskId) async {
    final rows = await (database.select(database.taskTags)
          ..where((tt) => tt.taskId.equals(taskId)))
        .get();
    
    final tagIds = rows.map((r) => r.tagId).toList();
    if (tagIds.isEmpty) return [];

    final tags = await (database.select(database.tags)
          ..where((t) => t.id.isIn(tagIds)))
        .get();
    
    return tags.map((t) => t.name).toList();
  }

  Future<int> _getOrCreateTag(String tagName) async {
    final existing = await (database.select(database.tags)..where((t) => t.name.equals(tagName))).getSingleOrNull();
    if (existing != null) return existing.id;

    return await database.into(database.tags).insert(
      db.TagsCompanion.insert(name: tagName),
    );
  }
}

class DelegatedTaskInfo {
  final int id;
  final int? originalTaskId;
  final String fromUserEmail;
  final String? fromUserName;
  final String taskTitle;
  final String? taskDescription;
  final DateTime taskDate;
  final DateTime? taskEndDate;
  final int taskPriority;
  final List<String> taskTags;
  final DateTime createdAt;

  DelegatedTaskInfo({
    required this.id,
    this.originalTaskId,
    required this.fromUserEmail,
    this.fromUserName,
    required this.taskTitle,
    this.taskDescription,
    required this.taskDate,
    this.taskEndDate,
    required this.taskPriority,
    required this.taskTags,
    required this.createdAt,
  });
}
