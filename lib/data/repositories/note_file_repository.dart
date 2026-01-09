import 'dart:io';
import 'package:drift/drift.dart' as dr;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../app_database.dart' as db;
import '../../models/attached_file.dart';

class NoteFileRepository {
  final db.AppDatabase database;

  NoteFileRepository(this.database);

  /// Сохранить файлы для заметки
  Future<void> saveNoteFiles(int noteId, List<AttachedFile> files) async {
    // Удаляем старые файлы
    await (database.delete(database.noteFiles)..where((nf) => nf.noteId.equals(noteId))).go();

    // Сохраняем новые файлы
    for (final file in files) {
      // Копируем файл в постоянное хранилище
      final permanentPath = await _copyFileToPermanentStorage(file.filePath, file.fileName);
      
      await database.into(database.noteFiles).insert(
        db.NoteFilesCompanion.insert(
          noteId: noteId,
          fileName: file.fileName,
          filePath: permanentPath,
          fileType: file.fileType,
          fileSize: file.fileSize,
        ),
      );
    }
  }

  /// Загрузить файлы для заметки
  Future<List<AttachedFile>> loadNoteFiles(int noteId) async {
    final rows = await (database.select(database.noteFiles)
          ..where((nf) => nf.noteId.equals(noteId)))
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

  /// Удалить файлы заметки
  Future<void> deleteNoteFiles(int noteId) async {
    // Получаем файлы перед удалением, чтобы удалить их с диска
    final files = await loadNoteFiles(noteId);
    
    // Удаляем записи из БД
    await (database.delete(database.noteFiles)..where((nf) => nf.noteId.equals(noteId))).go();
    
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
    final filesDir = Directory(path.join(appDir.path, 'note_files'));
    
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
