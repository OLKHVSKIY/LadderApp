class GoalModel {
  final String id;
  final String title;
  final List<GoalDate> dates;
  final bool isSaved;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? savedAt;
  final int? dbId;
  // Дедлайн цели (опционально). На его основе считается «темп».
  final DateTime? deadline;
  // Вехи — крупные чекпойнты цели (не привязаны к датам).
  final List<GoalMilestone> milestones;
  // Дни (нормализованные до даты), когда была активность по цели —
  // выполнена задача или веха. Основа для стрика и «первой недели».
  final List<DateTime> activeDays;
  // Какие чекпойнты «первой недели» (3/5/7) уже отпразднованы — чтобы
  // не показывать празднование повторно.
  final List<int> weekWins;
  // Мотивация «зачем мне эта цель» — показывается при открытии.
  final String? motivation;
  // Числовая цель (накопить, прочитать, сбросить вес). null — обычная задачная.
  final GoalMetric? metric;

  GoalModel({
    required this.id,
    required this.title,
    required this.dates,
    required this.isSaved,
    required this.isActive,
    required this.createdAt,
    this.savedAt,
    this.dbId,
    this.deadline,
    this.milestones = const [],
    this.activeDays = const [],
    this.weekWins = const [],
    this.motivation,
    this.metric,
  });

  GoalModel copyWith({
    String? id,
    String? title,
    List<GoalDate>? dates,
    bool? isSaved,
    bool? isActive,
    DateTime? createdAt,
    DateTime? savedAt,
    int? dbId,
    DateTime? deadline,
    bool clearDeadline = false,
    List<GoalMilestone>? milestones,
    List<DateTime>? activeDays,
    List<int>? weekWins,
    String? motivation,
    bool clearMotivation = false,
    GoalMetric? metric,
    bool clearMetric = false,
  }) {
    return GoalModel(
      id: id ?? this.id,
      title: title ?? this.title,
      dates: dates ?? this.dates,
      isSaved: isSaved ?? this.isSaved,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      savedAt: savedAt ?? this.savedAt,
      dbId: dbId ?? this.dbId,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      milestones: milestones ?? this.milestones,
      activeDays: activeDays ?? this.activeDays,
      weekWins: weekWins ?? this.weekWins,
      motivation: clearMotivation ? null : (motivation ?? this.motivation),
      metric: clearMetric ? null : (metric ?? this.metric),
    );
  }

  // --------- Вехи ---------
  int get completedMilestones =>
      milestones.where((m) => m.isCompleted).length;

  // --------- Первая неделя ---------
  // Точка отсчёта «жизни» цели: момент сохранения, иначе создания.
  DateTime get _anchorStart {
    final s = savedAt ?? createdAt;
    return DateTime(s.year, s.month, s.day);
  }

  // Сколько дней с активностью попало в первые 7 дней цели.
  int get firstWeekActiveCount {
    final start = _anchorStart;
    final end = start.add(const Duration(days: 7));
    final set = <int>{};
    for (final d in activeDays) {
      final day = DateTime(d.year, d.month, d.day);
      if (!day.isBefore(start) && day.isBefore(end)) {
        set.add(day.year * 10000 + day.month * 100 + day.day);
      }
    }
    return set.length;
  }

  // Цель ещё в пределах первой недели (показывать полосу прогресса недели).
  bool get isWithinFirstWeek {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(_anchorStart).inDays < 7;
  }

  // --------- Срок цели / режим без дедлайна ---------
  bool get hasDeadline => deadline != null;

  // Всего дней в сроке цели (от старта до дедлайна), минимум 1.
  int? get termTotalDays {
    if (deadline == null) return null;
    final end = DateTime(deadline!.year, deadline!.month, deadline!.day);
    final days = end.difference(_anchorStart).inDays;
    return days < 1 ? 1 : days;
  }

  // Сколько дней с активностью попало в срок цели (до дедлайна включительно).
  int get termActiveCount {
    if (deadline == null) return 0;
    final start = _anchorStart;
    final end = DateTime(deadline!.year, deadline!.month, deadline!.day)
        .add(const Duration(days: 1));
    final set = <int>{};
    for (final d in activeDays) {
      final day = DateTime(d.year, d.month, d.day);
      if (!day.isBefore(start) && day.isBefore(end)) {
        set.add(day.year * 10000 + day.month * 100 + day.day);
      }
    }
    return set.length;
  }

  // --------- Режим без дедлайна: бесконечный счётчик недель ---------
  // Номер текущей недели цели (1, 2, 3, …).
  int get weekNumber {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(_anchorStart).inDays;
    return diff < 0 ? 1 : diff ~/ 7 + 1;
  }

  // Сколько дней с активностью в пределах текущей недели цели.
  int get currentWeekActiveCount {
    final start = _anchorStart.add(Duration(days: (weekNumber - 1) * 7));
    final end = start.add(const Duration(days: 7));
    final set = <int>{};
    for (final d in activeDays) {
      final day = DateTime(d.year, d.month, d.day);
      if (!day.isBefore(start) && day.isBefore(end)) {
        set.add(day.year * 10000 + day.month * 100 + day.day);
      }
    }
    return set.length;
  }

  // --------- Стрик с гибким восстановлением ---------
  GoalStreakInfo get streakInfo {
    final days = <DateTime>{};
    for (final d in activeDays) {
      days.add(DateTime(d.year, d.month, d.day));
    }
    bool has(DateTime d) =>
        days.contains(DateTime(d.year, d.month, d.day));
    // «Заморозки» зарабатываются за каждые 5 активных дней, максимум 2.
    final earned = (days.length ~/ 5).clamp(0, 2);
    var freezesLeft = earned;
    var usedFreeze = 0;

    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    // Сегодня ещё может быть не отмечено — стрик жив, если активность вчера.
    if (!has(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var current = 0;
    while (true) {
      if (has(cursor)) {
        current++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        // Пропущенный день: пробуем «заморозить» (мостим один день).
        final prev = cursor.subtract(const Duration(days: 1));
        if (freezesLeft > 0 && has(prev)) {
          freezesLeft--;
          usedFreeze++;
          cursor = prev;
        } else {
          break;
        }
      }
    }
    return GoalStreakInfo(
      current: current,
      freezeTokensTotal: earned,
      freezeTokensLeft: freezesLeft,
      freezeTokensUsed: usedFreeze,
    );
  }

  int get totalTasks => dates.fold(0, (sum, d) => sum + d.tasks.length);

  int get completedTasks =>
      dates.fold(0, (sum, d) => sum + d.tasks.where((t) => t.isCompleted).length);

  double get progress {
    if (metric != null) return metric!.progress;
    return totalTasks == 0 ? 0 : completedTasks / totalTasks;
  }

  /// Сколько целых дней осталось до дедлайна (отрицательное — просрочено).
  int? get daysLeft {
    if (deadline == null) return null;
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    final d1 = DateTime(deadline!.year, deadline!.month, deadline!.day);
    return d1.difference(d0).inDays;
  }

  /// Темп: разница между фактическим прогрессом и «ожидаемым» по времени.
  /// >0 — опережение, <0 — отставание, null — дедлайн не задан.
  double? get paceDelta {
    if (deadline == null) return null;
    final start = createdAt;
    final total = deadline!.difference(start).inMinutes;
    if (total <= 0) return progress >= 1.0 ? 0.0 : progress - 1.0;
    final elapsed = DateTime.now().difference(start).inMinutes;
    final expected = (elapsed / total).clamp(0.0, 1.0);
    return progress - expected;
  }

  Map<String, dynamic> toMap({bool excludeDbId = false}) => {
        'id': id,
        'title': title,
        'dates': dates.map((d) => d.toMap()).toList(),
        'isSaved': isSaved,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'savedAt': savedAt?.toIso8601String(),
        'deadline': deadline?.toIso8601String(),
        'milestones': milestones.map((m) => m.toMap()).toList(),
        'activeDays': activeDays.map((d) => d.toIso8601String()).toList(),
        'weekWins': weekWins,
        'motivation': motivation,
        'metric': metric?.toMap(),
        if (!excludeDbId) 'dbId': dbId,
      };

  factory GoalModel.fromMap(Map<String, dynamic> map) => GoalModel(
        id: map['id'] as String,
        title: map['title'] as String,
        dates: (map['dates'] as List<dynamic>? ?? [])
            .map((e) => GoalDate.fromMap(e as Map<String, dynamic>))
            .toList(),
        isSaved: map['isSaved'] as bool? ?? false,
        isActive: map['isActive'] as bool? ?? false,
        createdAt: DateTime.parse(map['createdAt'] as String),
        savedAt: map['savedAt'] != null ? DateTime.parse(map['savedAt'] as String) : null,
        deadline: map['deadline'] != null ? DateTime.parse(map['deadline'] as String) : null,
        milestones: (map['milestones'] as List<dynamic>? ?? [])
            .map((e) => GoalMilestone.fromMap(e as Map<String, dynamic>))
            .toList(),
        activeDays: (map['activeDays'] as List<dynamic>? ?? [])
            .map((e) => DateTime.parse(e as String))
            .toList(),
        weekWins: (map['weekWins'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
        motivation: map['motivation'] as String?,
        metric: map['metric'] != null
            ? GoalMetric.fromMap(map['metric'] as Map<String, dynamic>)
            : null,
        dbId: map['dbId'] as int?,
      );

  static GoalModel empty() => GoalModel(
        id: '',
        title: '',
        dates: const [],
        isSaved: false,
        isActive: false,
        createdAt: DateTime.now(),
      );
}

/// Результат расчёта стрика цели (с гибким восстановлением).
class GoalStreakInfo {
  final int current; // длина текущей серии активных дней
  final int freezeTokensTotal; // сколько «заморозок» заработано всего
  final int freezeTokensLeft; // сколько ещё доступно
  final int freezeTokensUsed; // сколько сейчас защищает стрик

  const GoalStreakInfo({
    required this.current,
    required this.freezeTokensTotal,
    required this.freezeTokensLeft,
    required this.freezeTokensUsed,
  });

  bool get freezeActive => freezeTokensUsed > 0;
}

/// Числовая цель: накопить/прочитать/сбросить. Прогресс по значению, а не задачам.
class GoalMetric {
  final double startValue; // стартовое значение (0, текущий вес и т.п.)
  final double targetValue; // целевое значение
  final double currentValue; // текущее значение
  final String unit; // единица: ₽, книг, кг…
  final List<MetricEntry> history; // история изменений для графика

  const GoalMetric({
    required this.startValue,
    required this.targetValue,
    required this.currentValue,
    this.unit = '',
    this.history = const [],
  });

  // Цель «вниз» (например, сбросить вес): целевое меньше стартового.
  bool get isDescending => targetValue < startValue;

  // Прогресс 0..1 от старта к цели (работает для роста и снижения).
  double get progress {
    final span = targetValue - startValue;
    if (span == 0) return currentValue == targetValue ? 1.0 : 0.0;
    return ((currentValue - startValue) / span).clamp(0.0, 1.0);
  }

  GoalMetric copyWith({
    double? startValue,
    double? targetValue,
    double? currentValue,
    String? unit,
    List<MetricEntry>? history,
  }) {
    return GoalMetric(
      startValue: startValue ?? this.startValue,
      targetValue: targetValue ?? this.targetValue,
      currentValue: currentValue ?? this.currentValue,
      unit: unit ?? this.unit,
      history: history ?? this.history,
    );
  }

  Map<String, dynamic> toMap() => {
        'startValue': startValue,
        'targetValue': targetValue,
        'currentValue': currentValue,
        'unit': unit,
        'history': history.map((e) => e.toMap()).toList(),
      };

  factory GoalMetric.fromMap(Map<String, dynamic> map) => GoalMetric(
        startValue: (map['startValue'] as num?)?.toDouble() ?? 0,
        targetValue: (map['targetValue'] as num?)?.toDouble() ?? 0,
        currentValue: (map['currentValue'] as num?)?.toDouble() ?? 0,
        unit: map['unit'] as String? ?? '',
        history: (map['history'] as List<dynamic>? ?? [])
            .map((e) => MetricEntry.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Точка истории числовой цели (дата + значение) — для графика.
class MetricEntry {
  final DateTime date;
  final double value;

  const MetricEntry({required this.date, required this.value});

  Map<String, dynamic> toMap() => {
        'date': date.toIso8601String(),
        'value': value,
      };

  factory MetricEntry.fromMap(Map<String, dynamic> map) => MetricEntry(
        date: DateTime.parse(map['date'] as String),
        value: (map['value'] as num).toDouble(),
      );
}

/// Веха — крупный чекпойнт цели, не привязанный к конкретной дате.
class GoalMilestone {
  final String id;
  final String title;
  final bool isCompleted;
  final DateTime? completedAt;

  GoalMilestone({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.completedAt,
  });

  GoalMilestone copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return GoalMilestone(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
      };

  factory GoalMilestone.fromMap(Map<String, dynamic> map) => GoalMilestone(
        id: map['id'] as String,
        title: map['title'] as String,
        isCompleted: map['isCompleted'] as bool? ?? false,
        completedAt: map['completedAt'] != null
            ? DateTime.parse(map['completedAt'] as String)
            : null,
      );
}

class GoalDate {
  final String id;
  // Дата может отсутствовать — задачи цели без привязки к конкретному дню.
  final DateTime? date;
  final List<GoalTask> tasks;

  GoalDate({
    required this.id,
    required this.date,
    required this.tasks,
  });

  GoalDate copyWith({
    String? id,
    DateTime? date,
    List<GoalTask>? tasks,
  }) {
    return GoalDate(
      id: id ?? this.id,
      date: date ?? this.date,
      tasks: tasks ?? this.tasks,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date?.toIso8601String(),
        'tasks': tasks.map((t) => t.toMap()).toList(),
      };

  factory GoalDate.fromMap(Map<String, dynamic> map) => GoalDate(
        id: map['id'] as String,
        date: map['date'] != null
            ? DateTime.parse(map['date'] as String)
            : null,
        tasks: (map['tasks'] as List<dynamic>? ?? [])
            .map((e) => GoalTask.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
}

class GoalTask {
  final String id;
  final String title;
  final int priority;
  final bool isCompleted;
  // id связанной задачи таймлайна («Список»), если она создана. Позволяет
  // синхронизировать выполнение и удаление между целью и Списком.
  final int? linkedTaskId;

  GoalTask({
    required this.id,
    required this.title,
    this.priority = 2,
    this.isCompleted = false,
    this.linkedTaskId,
  });

  GoalTask copyWith({
    String? id,
    String? title,
    int? priority,
    bool? isCompleted,
    int? linkedTaskId,
    bool clearLinkedTaskId = false,
  }) {
    return GoalTask(
      id: id ?? this.id,
      title: title ?? this.title,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      linkedTaskId:
          clearLinkedTaskId ? null : (linkedTaskId ?? this.linkedTaskId),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'priority': priority,
        'isCompleted': isCompleted,
        'linkedTaskId': linkedTaskId,
      };

  factory GoalTask.fromMap(Map<String, dynamic> map) => GoalTask(
        id: map['id'] as String,
        title: map['title'] as String,
        priority: map['priority'] as int? ?? 2,
        isCompleted: map['isCompleted'] as bool? ?? false,
        linkedTaskId: map['linkedTaskId'] as int?,
      );
}

