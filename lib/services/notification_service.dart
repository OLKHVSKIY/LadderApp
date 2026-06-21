import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/app_translations.dart';
import '../models/reminder_model.dart';

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

  /// Отменяет уведомление заметки, запланированное прежней реализацией
  /// (когда id уведомления совпадал с id заметки). Нужно для подчистки легаси —
  /// новые напоминания идут через сущность Reminder / [scheduleReminder].
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

  // ---------- Напоминания (сущность Reminder) ----------

  // Канал и детали уведомлений напоминаний.
  static const NotificationDetails _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Напоминания',
      channelDescription: 'Напоминания о задачах и делах',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  // Напоминания живут в отдельном диапазоне id (700000000+), чтобы не
  // пересекаться с уведомлениями заметок (id заметки) и событий.
  static int _reminderNotifId(int reminderId) => 700000000 + reminderId;

  /// Переводит правило повтора напоминания в компоненты совпадения для
  /// flutter_local_notifications (система сама повторяет показ).
  static DateTimeComponents? _repeatComponents(String repeatRule) {
    switch (repeatRule) {
      case 'daily':
        return DateTimeComponents.time;
      case 'weekly':
        return DateTimeComponents.dayOfWeekAndTime;
      case 'monthly':
        return DateTimeComponents.dayOfMonthAndTime;
      case 'yearly':
        return DateTimeComponents.dateAndTime;
      default:
        return null; // 'none'
    }
  }

  /// Планирует уведомление напоминания.
  ///
  /// [id] — id строки reminders (стабильный, для перепланирования/отмены).
  /// [fireAt] — фактическое время показа (учитывайте snooze на стороне вызова).
  /// [repeatRule] — 'none'|'daily'|'weekly'|'monthly'|'yearly'.
  Future<void> scheduleReminder({
    required int id,
    required String title,
    String? body,
    required DateTime fireAt,
    String repeatRule = 'none',
  }) async {
    await init();
    // Перепланируем с нуля.
    await _plugin.cancel(_reminderNotifId(id));

    final components = _repeatComponents(repeatRule);
    var when = fireAt;
    if (components == null) {
      // Разовое уже прошедшее — не планируем.
      if (!when.isAfter(DateTime.now())) return;
    } else {
      // Повторяющееся: сдвигаем на ближайшее будущее срабатывание.
      while (!when.isAfter(DateTime.now())) {
        switch (repeatRule) {
          case 'daily':
            when = when.add(const Duration(days: 1));
            break;
          case 'weekly':
            when = when.add(const Duration(days: 7));
            break;
          case 'monthly':
            when = DateTime(when.year, when.month + 1, when.day, when.hour,
                when.minute);
            break;
          case 'yearly':
            when = DateTime(when.year + 1, when.month, when.day, when.hour,
                when.minute);
            break;
          default:
            return;
        }
      }
    }

    try {
      await _plugin.zonedSchedule(
        _reminderNotifId(id),
        title,
        body ?? title,
        tz.TZDateTime.from(when, tz.local),
        _reminderDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: components,
      );
    } catch (e) {
      debugPrint('Не удалось запланировать напоминание: $e');
    }
  }

  /// Отменяет запланированное напоминание.
  Future<void> cancelReminder(int id) async {
    await init();
    await _plugin.cancel(_reminderNotifId(id));
  }

  /// Полная пересборка локальных напоминаний при запуске приложения.
  ///
  /// Снимает ВСЕ ранее запланированные уведомления напоминаний (диапазон
  /// 700000000+) и легаси-уведомления заметок (мелкие id) — в т.ч.
  /// «осиротевшие» от удалённых/старых записей, чтобы не приходили дубли. Затем
  /// планирует заново из актуальных строк reminders. Уведомления событий
  /// (id 800000000+/900000000+) НЕ трогаем.
  Future<void> resyncReminders(List<Reminder> reminders) async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id < 800000000) {
        await _plugin.cancel(p.id);
      }
    }
    for (final r in reminders) {
      if (r.id == null || !r.isEnabled) continue;
      await scheduleReminder(
        id: r.id!,
        title: r.title,
        body: r.body,
        fireAt: r.effectiveTime,
        repeatRule: r.repeatRule,
      );
    }
  }
}
