/// Доменная модель напоминания — отдельная сущность (раньше «жила» в
/// timeline-заметках). Привязывается к задаче/событию/привычке либо существует
/// сама по себе. Планированием уведомлений занимается NotificationService.
class Reminder {
  final int? id;
  final int userId;
  // 'task' | 'event' | 'habit' | 'standalone'
  final String ownerType;
  final int? ownerId;
  final String title;
  final String? body;
  final DateTime fireAt;
  // 'none' | 'daily' | 'weekly' | 'monthly' | 'yearly'
  final String repeatRule;
  final DateTime? snoozedUntil;
  final bool isEnabled;

  const Reminder({
    this.id,
    required this.userId,
    this.ownerType = 'standalone',
    this.ownerId,
    required this.title,
    this.body,
    required this.fireAt,
    this.repeatRule = 'none',
    this.snoozedUntil,
    this.isEnabled = true,
  });

  /// Фактическое время показа: с учётом «отложить» (snooze), если задано.
  DateTime get effectiveTime => snoozedUntil ?? fireAt;

  bool get repeats => repeatRule != 'none';

  Reminder copyWith({
    int? id,
    int? userId,
    String? ownerType,
    int? ownerId,
    String? title,
    String? body,
    DateTime? fireAt,
    String? repeatRule,
    DateTime? snoozedUntil,
    bool? clearSnooze,
    bool? isEnabled,
  }) {
    return Reminder(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      ownerType: ownerType ?? this.ownerType,
      ownerId: ownerId ?? this.ownerId,
      title: title ?? this.title,
      body: body ?? this.body,
      fireAt: fireAt ?? this.fireAt,
      repeatRule: repeatRule ?? this.repeatRule,
      snoozedUntil:
          clearSnooze == true ? null : (snoozedUntil ?? this.snoozedUntil),
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
