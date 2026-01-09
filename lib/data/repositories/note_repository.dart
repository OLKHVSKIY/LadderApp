import 'dart:convert';
import 'package:drift/drift.dart' as dr;
import '../app_database.dart';
import '../../models/note_model.dart';
import '../user_session.dart';
import 'note_file_repository.dart';

class NoteRepository {
  final AppDatabase db;
  NoteFileRepository? _fileRepository;

  NoteRepository(this.db);
  
  NoteFileRepository get _fileRepo {
    _fileRepository ??= NoteFileRepository(db);
    return _fileRepository!;
  }

  /// Сохранить заметку
  Future<int> saveNote(NoteModel note, int userId) async {
    final jsonStr = jsonEncode(note.toJson());
    int noteId;
    if (note.id != null) {
      await (db.update(db.notes)..where((n) => n.id.equals(note.id!))).write(
        NotesCompanion(
          title: dr.Value(note.title),
          content: dr.Value(jsonStr),
          updatedAt: dr.Value(DateTime.now()),
        ),
      );
      noteId = note.id!;
    } else {
      noteId = await db.into(db.notes).insert(
            NotesCompanion.insert(
              userId: userId,
              title: note.title,
              content: jsonStr,
              createdAt: dr.Value(DateTime.now()),
              updatedAt: dr.Value(DateTime.now()),
            ),
          );
    }
    // Сохраняем файлы
    if (note.attachedFiles != null && note.attachedFiles!.isNotEmpty) {
      await _fileRepo.saveNoteFiles(noteId, note.attachedFiles!);
    } else {
      await _fileRepo.deleteNoteFiles(noteId);
    }
    return noteId;
  }

  /// Загрузить все заметки пользователя
  Future<List<NoteModel>> loadNotes(int userId) async {
    final rows = await (db.select(db.notes)
          ..where((n) => n.userId.equals(userId))
          ..orderBy([(n) => dr.OrderingTerm.desc(n.updatedAt)]))
        .get();
    
    final result = <NoteModel>[];
    for (final r in rows) {
      try {
        final map = jsonDecode(r.content) as Map<String, dynamic>;
        final files = await _fileRepo.loadNoteFiles(r.id);
        final note = NoteModel.fromJson(
          map,
          id: r.id,
          createdAt: r.createdAt,
          updatedAt: r.updatedAt,
        ).copyWith(attachedFiles: files.isNotEmpty ? files : null);
        result.add(note);
      } catch (_) {
        // Пропускаем некорректные записи
      }
    }
    return result;
  }

  /// Удалить заметку
  Future<void> deleteNote(int id) async {
    // Удаляем файлы перед удалением заметки
    await _fileRepo.deleteNoteFiles(id);
    await (db.delete(db.notes)..where((n) => n.id.equals(id))).go();
  }
}

