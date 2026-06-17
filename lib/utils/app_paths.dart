import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Кэш пути к Documents-директории приложения + резолв путей картинок событий.
///
/// На iOS контейнер приложения (а с ним и путь к Documents) получает новый UUID
/// при каждой переустановке/полном ребилде. Поэтому в БД нельзя хранить
/// абсолютные пути — они «протухают». Храним ОТНОСИТЕЛЬНЫЙ путь
/// ('event_images/<файл>'), а абсолютный собираем в рантайме от текущей
/// Documents-директории.
class AppPaths {
  AppPaths._();

  static String _documentsPath = '';

  /// Вызвать один раз на старте приложения (в main, после ensureInitialized).
  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _documentsPath = dir.path;
  }

  static String get documentsPath => _documentsPath;

  /// Папка с картинками событий (относительный путь от Documents).
  static const String eventImagesDir = 'event_images';

  /// Превратить сохранённый в БД путь в абсолютный для текущего запуска.
  /// Поддерживает и новые относительные пути, и старые абсолютные
  /// (после переустановки они битые — резолвим по имени файла).
  static String? resolveEventImage(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    // Относительный путь — собираем от текущей Documents-директории.
    if (!p.isAbsolute(stored)) {
      return p.join(_documentsPath, stored);
    }
    // Абсолютный путь: если файл на месте — используем как есть.
    if (File(stored).existsSync()) return stored;
    // Иначе путь устарел (сменился контейнер) — ищем тот же файл по имени
    // в текущей папке картинок.
    final name = p.basename(stored);
    return p.join(_documentsPath, eventImagesDir, name);
  }
}
