import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import '../models/task.dart';
import '../data/database_instance.dart';
import '../data/repositories/task_repository.dart';

/// Результат импорта событий Google Календаря.
class CalendarImportResult {
  /// Сколько новых задач реально создано.
  final int imported;

  /// Сколько событий пропущено как уже существующие (дубликаты).
  final int skipped;

  const CalendarImportResult({required this.imported, required this.skipped});
}

/// Пользователь отменил вход в Google-аккаунт.
class GoogleSignInCancelled implements Exception {}

/// В .env не указан GOOGLE_IOS_CLIENT_ID — интеграция ещё не настроена.
///
/// Без client ID нативный GoogleSignIn SDK падает с необрабатываемым
/// исключением, поэтому проверяем заранее и не вызываем вход.
class GoogleNotConfigured implements Exception {}

/// Импорт событий Google Календаря в задачи приложения.
///
/// Использует официальный путь Google: google_sign_in (OAuth 2.0) для входа
/// и googleapis (Calendar API v3) для чтения событий. Запрашивается только
/// доступ на чтение (scope calendar.readonly).
class GoogleCalendarService {
  /// Доступ только на чтение — мы ничего не меняем в календаре пользователя.
  static const List<String> _scopes = [gcal.CalendarApi.calendarReadonlyScope];

  /// iOS OAuth client ID берём из .env (GOOGLE_IOS_CLIENT_ID).
  ///
  /// На iOS нужно ещё прописать обратную схему (reversed client ID)
  /// в ios/Runner/Info.plist как CFBundleURLSchemes.
  GoogleSignIn _buildSignIn() {
    final iosClientId = dotenv.maybeGet('GOOGLE_IOS_CLIENT_ID');
    return GoogleSignIn(
      scopes: _scopes,
      clientId: (iosClientId != null && iosClientId.isNotEmpty) ? iosClientId : null,
    );
  }

  // Глобальный (статический) флаг: один импорт за раз на всё приложение —
  // защита от гонок при многократном нажатии (см. AppleCalendarService).
  static bool _importing = false;

  /// Главный метод: вход в аккаунт, чтение событий, сохранение их задачами.
  ///
  /// Импортируются события за последний месяц и все будущие. Каждое событие
  /// превращается в задачу: название → заголовок, описание → описание,
  /// время начала → дата, время окончания → endDate.
  Future<CalendarImportResult> importEvents() async {
    if (_importing) {
      return const CalendarImportResult(imported: 0, skipped: 0);
    }
    _importing = true;
    try {
      final iosClientId = dotenv.maybeGet('GOOGLE_IOS_CLIENT_ID');
      if (iosClientId == null || iosClientId.isEmpty) {
        throw GoogleNotConfigured();
      }

      final googleSignIn = _buildSignIn();

      // Тихая попытка восстановить прошлый вход, иначе показываем экран входа.
      GoogleSignInAccount? account = await googleSignIn.signInSilently();
      account ??= await googleSignIn.signIn();
      if (account == null) {
        throw GoogleSignInCancelled();
      }

      final httpClient = await googleSignIn.authenticatedClient();
      if (httpClient == null) {
        throw Exception('Не удалось получить доступ к Google Календарю');
      }

      try {
        final events = await _fetchEvents(httpClient);
        return await _saveEventsAsTasks(events);
      } finally {
        httpClient.close();
      }
    } finally {
      _importing = false;
    }
  }

  /// Сколько событий ещё не импортировано (для индикатора).
  ///
  /// Вход только тихий (signInSilently): если пользователь не входил,
  /// возвращаем 0 и не показываем экран входа ради бейджа.
  Future<int> countNewEvents() async {
    final iosClientId = dotenv.maybeGet('GOOGLE_IOS_CLIENT_ID');
    if (iosClientId == null || iosClientId.isEmpty) return 0;

    final googleSignIn = _buildSignIn();
    final account = await googleSignIn.signInSilently();
    if (account == null) return 0;

    final httpClient = await googleSignIn.authenticatedClient();
    if (httpClient == null) return 0;

    try {
      final events = await _fetchEvents(httpClient);
      final repo = TaskRepository(appDatabase);
      final existing = await repo.searchAllTasks();
      final existingKeys =
          existing.map((t) => _dedupKey(t.title, t.date)).toSet();

      final seen = <String>{};
      var count = 0;
      for (final event in events) {
        final title = (event.summary ?? '').trim();
        if (title.isEmpty) continue;
        final start = _eventStart(event);
        if (start == null) continue;
        final key = _dedupKey(title, start);
        if (existingKeys.contains(key) || seen.contains(key)) continue;
        seen.add(key);
        count++;
      }
      return count;
    } finally {
      httpClient.close();
    }
  }

  /// Читает все события основного календаря постранично.
  Future<List<gcal.Event>> _fetchEvents(dynamic httpClient) async {
    final calendarApi = gcal.CalendarApi(httpClient);

    final now = DateTime.now();
    final timeMin = DateTime(now.year, now.month - 1, now.day).toUtc();

    final events = <gcal.Event>[];
    String? pageToken;
    do {
      final response = await calendarApi.events.list(
        'primary',
        timeMin: timeMin,
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 2500,
        pageToken: pageToken,
      );
      if (response.items != null) {
        events.addAll(response.items!);
      }
      pageToken = response.nextPageToken;
    } while (pageToken != null);
    return events;
  }

  /// Преобразует события в задачи и сохраняет, пропуская дубликаты.
  ///
  /// Вся работа идёт в одной транзакции БД: это сериализует возможные
  /// параллельные импорты и гарантирует атомарность — дубликаты не
  /// появляются даже при гонке.
  Future<CalendarImportResult> _saveEventsAsTasks(List<gcal.Event> events) async {
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
        final title = (event.summary ?? '').trim();
        if (title.isEmpty) {
          // События без названия (например, занятость) пропускаем.
          skipped++;
          continue;
        }

        final start = _eventStart(event);
        if (start == null) {
          skipped++;
          continue;
        }
        final end = _eventEnd(event);

        final key = _dedupKey(title, start);
        if (existingKeys.contains(key)) {
          skipped++;
          continue;
        }

        final description = event.description?.trim();
        await repo.addTask(
          Task(
            id: event.id ?? '${DateTime.now().microsecondsSinceEpoch}',
            title: title,
            description: (description != null && description.isNotEmpty) ? description : null,
            priority: 2,
            tags: const ['#календарь'],
            date: start,
            endDate: end,
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
  /// Обе даты приводим к локальному времени: задача из БД может вернуться в
  /// UTC, а событие — в локальной зоне, из-за чего день у событий около
  /// полуночи/на весь день не совпадал и дубликаты не отсеивались.
  String _dedupKey(String title, DateTime date) {
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    return '${title.trim().toLowerCase()}|${day.toIso8601String()}';
  }

  /// Дата начала события. У события на весь день время указано в [date],
  /// у обычного — в [dateTime].
  DateTime? _eventStart(gcal.Event event) {
    final s = event.start;
    if (s == null) return null;
    if (s.dateTime != null) return s.dateTime!.toLocal();
    if (s.date != null) return s.date!.toLocal();
    return null;
  }

  /// Дата окончания события (для периода). null, если события на один момент.
  DateTime? _eventEnd(gcal.Event event) {
    final e = event.end;
    if (e == null) return null;
    if (e.dateTime != null) return e.dateTime!.toLocal();
    if (e.date != null) {
      // У all-day событий Google указывает end как следующий день (эксклюзивно),
      // поэтому отнимаем сутки, чтобы получить реальный последний день.
      return e.date!.toLocal().subtract(const Duration(days: 1));
    }
    return null;
  }

  /// Выход из Google-аккаунта (на случай, если потребуется сбросить вход).
  Future<void> signOut() async {
    try {
      await _buildSignIn().signOut();
    } catch (e) {
      debugPrint('Google signOut error: $e');
    }
  }
}
