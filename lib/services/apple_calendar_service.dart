import 'package:device_calendar/device_calendar.dart';

import '../models/task.dart';
import '../data/database_instance.dart';
import '../data/repositories/task_repository.dart';

/// Результат импорта событий Apple Календаря.
class CalendarImportResult {
  /// Сколько новых задач реально создано.
  final int imported;

  /// Сколько событий пропущено как уже существующие (дубликаты).
  final int skipped;

  const CalendarImportResult({required this.imported, required this.skipped});
}

/// Пользователь не дал доступ к календарю.
class CalendarPermissionDenied implements Exception {}

/// Импорт событий локального календаря iOS (Apple Календарь) в задачи.
///
/// Использует EventKit через пакет device_calendar — OAuth не нужен,
/// требуется только системное разрешение на доступ к календарю
/// (NSCalendarsUsageDescription / NSCalendarsFullAccessUsageDescription).
class AppleCalendarService {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  // Глобальный (статический) флаг: один импорт за раз на всё приложение.
  // Переживает пересоздание State настроек, поэтому два быстрых нажатия
  // (или два экземпляра сервиса) не могут запустить параллельные импорты,
  // которые читали бы БД до записи друг друга и плодили дубликаты.
  static bool _importing = false;

  /// Вход: запрос разрешения, чтение событий, сохранение их задачами.
  ///
  /// Импортируются события за последний месяц и год вперёд. Каждое событие
  /// превращается в задачу: название → заголовок, описание → описание,
  /// начало → дата, окончание → endDate.
  Future<CalendarImportResult> importEvents() async {
    // Уже идёт импорт — повторный запуск молча игнорируем.
    if (_importing) {
      return const CalendarImportResult(imported: 0, skipped: 0);
    }
    _importing = true;
    try {
      // Проверяем и при необходимости запрашиваем разрешение.
      var permissions = await _plugin.hasPermissions();
      if (permissions.data != true) {
        permissions = await _plugin.requestPermissions();
      }
      if (permissions.data != true) {
        throw CalendarPermissionDenied();
      }

      final events = await _fetchEvents();
      return _saveEventsAsTasks(events);
    } finally {
      _importing = false;
    }
  }

  /// Сколько событий календаря ещё не импортировано (для индикатора).
  ///
  /// Разрешение НЕ запрашиваем — если доступа нет, считаем 0, чтобы не
  /// показывать системный диалог ради бейджа.
  Future<int> countNewEvents() async {
    final permissions = await _plugin.hasPermissions();
    if (permissions.data != true) return 0;

    final events = await _fetchEvents();
    final repo = TaskRepository(appDatabase);
    final existing = await repo.searchAllTasks();
    final existingKeys = existing.map((t) => _dedupKey(t.title, t.date)).toSet();

    final seen = <String>{};
    var count = 0;
    for (final event in events) {
      final title = (event.title ?? '').trim();
      if (title.isEmpty || event.start == null) continue;
      final key = _dedupKey(title, event.start!.toLocal());
      if (existingKeys.contains(key) || seen.contains(key)) continue;
      seen.add(key);
      count++;
    }
    return count;
  }

  /// Читает события всех календарей устройства за период [-1 месяц; +1 год].
  Future<List<Event>> _fetchEvents() async {
    final calendarsResult = await _plugin.retrieveCalendars();
    final calendars = calendarsResult.data;
    if (calendars == null || calendars.isEmpty) return const [];

    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, now.day);
    final end = DateTime(now.year + 1, now.month, now.day);

    final events = <Event>[];
    for (final calendar in calendars) {
      final id = calendar.id;
      if (id == null) continue;
      final result = await _plugin.retrieveEvents(
        id,
        RetrieveEventsParams(startDate: start, endDate: end),
      );
      if (result.data != null) {
        events.addAll(result.data!);
      }
    }
    return events;
  }

  /// Преобразует события в задачи и сохраняет, пропуская дубликаты.
  ///
  /// Вся работа идёт в одной транзакции БД: это сериализует возможные
  /// параллельные импорты (второй увидит записи первого) и гарантирует
  /// атомарность — дубликаты не появляются даже при гонке.
  Future<CalendarImportResult> _saveEventsAsTasks(List<Event> events) async {
    return appDatabase.transaction(() async {
      final repo = TaskRepository(appDatabase);

      // Существующие задачи — чтобы не плодить дубликаты. Заодно схлопываем
      // уже накопившиеся дубли ранее импортированных событий (тег #календарь):
      // на каждый ключ оставляем одну задачу, лишние удаляем. Пользовательские
      // задачи (без тега) не трогаем.
      final existing = await repo.searchAllTasks();
      final existingKeys = <String>{};
      final keptCalendarKeys = <String>{};
      for (final t in existing) {
        final key = _dedupKey(t.title, t.date);
        final isCalendar = t.tags.contains('#календарь');
        if (isCalendar) {
          if (keptCalendarKeys.contains(key)) {
            final intId = int.tryParse(t.id);
            if (intId != null) await repo.deleteTask(intId);
            continue;
          }
          keptCalendarKeys.add(key);
        }
        existingKeys.add(key);
      }

      var imported = 0;
      var skipped = 0;

      for (final event in events) {
        final title = (event.title ?? '').trim();
        if (title.isEmpty || event.start == null) {
          skipped++;
          continue;
        }

        final startDate = event.start!.toLocal();
        // У all-day событий конец указан как следующий день — отнимаем сутки.
        DateTime? endDate;
        if (event.end != null) {
          endDate = event.end!.toLocal();
          if (event.allDay == true) {
            endDate = endDate.subtract(const Duration(days: 1));
          }
          if (!endDate.isAfter(startDate)) endDate = null;
        }

        final key = _dedupKey(title, startDate);
        if (existingKeys.contains(key)) {
          skipped++;
          continue;
        }

        final description = event.description?.trim();
        await repo.addTask(
          Task(
            id: event.eventId ?? '${DateTime.now().microsecondsSinceEpoch}',
            title: title,
            description: (description != null && description.isNotEmpty) ? description : null,
            priority: 2,
            tags: const ['#календарь'],
            date: startDate,
            endDate: endDate,
          ),
        );
        existingKeys.add(key);
        imported++;
      }

      return CalendarImportResult(imported: imported, skipped: skipped);
    });
  }

  /// Ключ для отсеивания дубликатов: название + день начала.
  ///
  /// Обе даты приводим к локальному времени перед сравнением: задача из БД
  /// может вернуться в UTC, а событие — в локальной зоне, из-за чего день
  /// у событий около полуночи/на весь день не совпадал и дубликаты не
  /// отсеивались при повторном импорте.
  String _dedupKey(String title, DateTime date) {
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    return '${title.trim().toLowerCase()}|${day.toIso8601String()}';
  }
}
