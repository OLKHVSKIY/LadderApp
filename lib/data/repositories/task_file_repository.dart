import 'dart:io';
import 'package:drift/drift.dart' as dr;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../app_database.dart' as db;
import '../../models/attached_file.dart';

class TaskFileRepository {
  final db.AppDatabase database;

  TaskFileRepository(this.database);

  /// Сохранить файлы для задачи
  Future<void> saveTaskFiles(int taskId, List<AttachedFile> files) async {
    // Удаляем старые файлы
    await (database.delete(database.taskFiles)..where((tf) => tf.taskId.equals(taskId))).go();

    // Сохраняем новые файлы
    for (final file in files) {
      // Копируем файл в постоянное хранилище
      final permanentPath = await _copyFileToPermanentStorage(file.filePath, file.fileName);
      
      await database.into(database.taskFiles).insert(
        db.TaskFilesCompanion.insert(
          taskId: taskId,
          fileName: file.fileName,
          filePath: permanentPath,
          fileType: file.fileType,
          fileSize: file.fileSize,
        ),
      );
    }
  }

  /// Загрузить файлы для задачи
  Future<List<AttachedFile>> loadTaskFiles(int taskId) async {
    final rows = await (database.select(database.taskFiles)
          ..where((tf) => tf.taskId.equals(taskId)))
        .get();
    
    return rows.map((row) {
      return AttachedFile(
        id: row.id,
        fileName: row.fileName,
        filePath: row.filePath,
        fileType: row.fileType,
        fileSize: row.fileSize,
      );
    }).toList();
  }

  /// Удалить файлы задачи
  Future<void> deleteTaskFiles(int taskId) async {
    // Получаем файлы перед удалением, чтобы удалить их с диска
    final files = await loadTaskFiles(taskId);
    
    // Удаляем записи из БД
    await (database.delete(database.taskFiles)..where((tf) => tf.taskId.equals(taskId))).go();
    
    // Удаляем файлы с диска
    for (final file in files) {
      try {
        final fileObj = File(file.filePath);
        if (await fileObj.exists()) {
          await fileObj.delete();
        }
      } catch (e) {
        // Игнорируем ошибки удаления файлов
      }
    }
  }

  /// Копировать файл в постоянное хранилище
  Future<String> _copyFileToPermanentStorage(String sourcePath, String fileName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final filesDir = Directory(path.join(appDir.path, 'task_files'));
    
    if (!await filesDir.exists()) {
      await filesDir.create(recursive: true);
    }
    
    final sourceFile = File(sourcePath);
    final targetPath = path.join(filesDir.path, '${DateTime.now().millisecondsSinceEpoch}_$fileName');
    final targetFile = File(targetPath);
    
    await sourceFile.copy(targetPath);
    
    return targetPath;
  }
}
