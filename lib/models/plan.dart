class PlanTask {
  final String id;
  final String title;
  final int priority;
  final bool isCompleted;

  PlanTask({
    required this.id,
    required this.title,
    required this.priority,
    this.isCompleted = false,
  });

  PlanTask copyWith({
    String? id,
    String? title,
    int? priority,
    bool? isCompleted,
  }) {
    return PlanTask(
      id: id ?? this.id,
      title: title ?? this.title,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class PlanDate {
  final String id;
  final DateTime date;
  final List<PlanTask> tasks;

  PlanDate({
    required this.id,
    required this.date,
    required this.tasks,
  });

  PlanDate copyWith({
    String? id,
    DateTime? date,
    List<PlanTask>? tasks,
  }) {
    return PlanDate(
      id: id ?? this.id,
      date: date ?? this.date,
      tasks: tasks ?? this.tasks,
    );
  }
}

class Plan {
  final String id;
  final String title;
  final List<PlanDate> dates;
  final bool isSaved;
  final double progress;

  Plan({
    required this.id,
    required this.title,
    required this.dates,
    this.isSaved = false,
    this.progress = 0.0,
  });

  Plan copyWith({
    String? id,
    String? title,
    List<PlanDate>? dates,
    bool? isSaved,
    double? progress,
  }) {
    return Plan(
      id: id ?? this.id,
      title: title ?? this.title,
      dates: dates ?? this.dates,
      isSaved: isSaved ?? this.isSaved,
      progress: progress ?? this.progress,
    );
  }

  // Mock данные для тестирования
  static List<Plan> getMockPlans() {
    return [
      Plan(
        id: '1',
        title: 'Подготовка к марафону',
        dates: [
          PlanDate(
            id: '1',
            date: DateTime.now().add(const Duration(days: 7)),
            tasks: [
              PlanTask(id: '1', title: 'Тренировка 5 км', priority: 1),
              PlanTask(id: '2', title: 'Растяжка', priority: 3),
            ],
          ),
          PlanDate(
            id: '2',
            date: DateTime.now().add(const Duration(days: 14)),
            tasks: [
              PlanTask(id: '3', title: 'Тренировка 10 км', priority: 1),
            ],
          ),
        ],
        isSaved: true,
        progress: 33.0,
      ),
    ];
  }
}

