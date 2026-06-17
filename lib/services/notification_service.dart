import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/app_translations.dart';

/// Локальные уведомления о начале заметок таймлайна.
///
/// При наступлении времени начала заметки приходит системное уведомление вида
/// «Заметка на 15:10» с названием заметки в теле. Работает даже когда
/// приложение закрыто или в фоне (zonedSchedule + точное время).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // База часовых поясов — для точного расписания в местном времени.
    tzdata.initializeTimeZones();
    try {
      final localName = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {
      // Если не удалось определить пояс — останется UTC; уведомления всё равно
      // создадутся (с возможным сдвигом времени).
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      // Разрешения запрашиваем отдельно (requestPermissions), чтобы
      // контролировать момент показа системного запроса.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Запрашивает разрешение на показ уведомлений (iOS / Android 13+).
  Future<void> requestPermissions() async {
    await init();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'timeline_notes',
      'Заметки таймлайна',
      channelDescription: 'Напоминания о начале заметок на шкале времени',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Планирует уведомление на начало заметки.
  ///
  /// [id] — стабильный идентификатор (id заметки), чтобы при изменении/удалении
  /// можно было перепланировать или отменить именно это уведомление.
  Future<void> scheduleNoteReminder({
    required int id,
    required String title,
    required DateTime startTime,
  }) async {
    await init();
    // На прошедшее время уведомление не имеет смысла.
    if (!startTime.isAfter(DateTime.now())) return;

    final when = tz.TZDateTime.from(startTime, tz.local);
    final hh = startTime.hour.toString().padLeft(2, '0');
    final mm = startTime.minute.toString().padLeft(2, '0');

    try {
      await _plugin.zonedSchedule(
        id,
        tr('Заметка на {0}', ['$hh:$mm']),
        title,
        when,
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Не удалось запланировать уведомление: $e');
    }
  }

  /// Отменяет ранее запланированное уведомление заметки.
  Future<void> cancelNoteReminder(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  // Канал и детали уведомлений событий.
  static const NotificationDetails _eventDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'events',
      'События',
      channelDescription: 'Напоминания о событиях (дни рождения и т.п.)',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  // Уведомления событий живут в отдельных диапазонах id, чтобы не пересекаться
  // с уведомлениями заметок (которые используют id заметки).
  static int _onDayId(int eventId) => 900000000 + eventId;
  static int _dayBeforeId(int eventId) => 800000000 + eventId;

  /// Планирует уведомления о событии (за 1 день и/или в день). Время показа —
  /// 9:00. Для ежегодных событий уведомление повторяется каждый год по
  /// месяцу/дню; для разовых — однократно (только если время в будущем).
  Future<void> scheduleEventReminders({
    required int id,
    required String title,
    required DateTime date,
    required bool repeatYearly,
    required bool notifyDayBefore,
    required bool notifyOnDay,
  }) async {
    await init();
    // Перепланируем с нуля: сначала снимаем прежние.
    await cancelEventReminders(id);

    if (notifyOnDay) {
      final onDay = DateTime(date.year, date.month, date.day, 9);
      await _scheduleEvent(
        notificationId: _onDayId(id),
        title: tr('Сегодня: {0}', [title]),
        body: title,
        when: onDay,
        repeatYearly: repeatYearly,
      );
    }
    if (notifyDayBefore) {
      final before =
          DateTime(date.year, date.month, date.day, 9).subtract(const Duration(days: 1));
      await _scheduleEvent(
        notificationId: _dayBeforeId(id),
        title: tr('Завтра: {0}', [title]),
        body: title,
        when: before,
        repeatYearly: repeatYearly,
      );
    }
  }

  Future<void> _scheduleEvent({
    required int notificationId,
    required String title,
    required String body,
    required DateTime when,
    required bool repeatYearly,
  }) async {
    var fireAt = when;
    if (repeatYearly) {
      // Для ежегодного: если в этом году дата уже прошла — берём следующий год,
      // дальше система сама повторяет по matchDateTimeComponents.
      while (!fireAt.isAfter(DateTime.now())) {
        fireAt = DateTime(fireAt.year + 1, fireAt.month, fireAt.day,
            fireAt.hour, fireAt.minute);
      }
    } else if (!fireAt.isAfter(DateTime.now())) {
      // Разовое уже прошедшее — не планируем.
      return;
    }

    try {
      await _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        tz.TZDateTime.from(fireAt, tz.local),
        _eventDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents:
            repeatYearly ? DateTimeComponents.dateAndTime : null,
      );
    } catch (e) {
      debugPrint('Не удалось запланировать уведомление события: $e');
    }
  }

  /// Отменяет оба уведомления события.
  Future<void> cancelEventReminders(int id) async {
    await init();
    await _plugin.cancel(_onDayId(id));
    await _plugin.cancel(_dayBeforeId(id));
  }
}
