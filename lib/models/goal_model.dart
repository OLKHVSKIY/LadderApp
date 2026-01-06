class GoalModel {
  final String id;
  final String title;
  final List<GoalDate> dates;
  final bool isSaved;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? savedAt;
  final int? dbId;

  GoalModel({
    required this.id,
    required this.title,
    required this.dates,
    required this.isSaved,
    required this.isActive,
    required this.createdAt,
    this.savedAt,
    this.dbId,
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
    );
  }

  int get totalTasks => dates.fold(0, (sum, d) => sum + d.tasks.length);

  Map<String, dynamic> toMap({bool excludeDbId = false}) => {
        'id': id,
        'title': title,
        'dates': dates.map((d) => d.toMap()).toList(),
        'isSaved': isSaved,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'savedAt': savedAt?.toIso8601String(),
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

class GoalDate {
  final String id;
  final DateTime date;
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
        'date': date.toIso8601String(),
        'tasks': tasks.map((t) => t.toMap()).toList(),
      };

  factory GoalDate.fromMap(Map<String, dynamic> map) => GoalDate(
        id: map['id'] as String,
        date: DateTime.parse(map['date'] as String),
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

  GoalTask({
    required this.id,
    required this.title,
    this.priority = 2,
    this.isCompleted = false,
  });

  GoalTask copyWith({
    String? id,
    String? title,
    int? priority,
    bool? isCompleted,
  }) {
    return GoalTask(
      id: id ?? this.id,
      title: title ?? this.title,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'priority': priority,
        'isCompleted': isCompleted,
      };

  factory GoalTask.fromMap(Map<String, dynamic> map) => GoalTask(
        id: map['id'] as String,
        title: map['title'] as String,
        priority: map['priority'] as int? ?? 2,
        isCompleted: map['isCompleted'] as bool? ?? false,
      );
}

