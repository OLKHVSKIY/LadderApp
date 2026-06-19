import 'attached_file.dart';

/// Пункт чек-листа внутри задачи (подзадача).
class SubTask {
  final String id;
  final String title;
  final bool isCompleted;

  const SubTask({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  SubTask copyWith({String? id, String? title, bool? isCompleted}) => SubTask(
        id: id ?? this.id,
        title: title ?? this.title,
        isCompleted: isCompleted ?? this.isCompleted,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'done': isCompleted,
      };

  factory SubTask.fromMap(Map<String, dynamic> map) => SubTask(
        id: map['id'] as String,
        title: map['title'] as String? ?? '',
        isCompleted: map['done'] as bool? ?? false,
      );
}

class Task {
  final String id;
  final String title;
  final String? description;
  final int priority; // 1, 2, 3
  final List<String> tags;
  final DateTime date;
  final DateTime? endDate; // для периода
  final bool isCompleted;
  final List<AttachedFile>? attachedFiles;
  final List<SubTask> subtasks; // чек-лист внутри задачи
  final String? creatorName; // Имя создателя задачи (для кастомных экранов)

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.priority,
    this.tags = const [],
    required this.date,
    this.endDate,
    this.isCompleted = false,
    this.attachedFiles,
    this.subtasks = const [],
    this.creatorName,
  });

  Task copyWith({List<SubTask>? subtasks, bool? isCompleted}) => Task(
        id: id,
        title: title,
        description: description,
        priority: priority,
        tags: tags,
        date: date,
        endDate: endDate,
        isCompleted: isCompleted ?? this.isCompleted,
        attachedFiles: attachedFiles,
        subtasks: subtasks ?? this.subtasks,
        creatorName: creatorName,
      );

  // Mock данные для тестирования
  static List<Task> getMockTasks() {
    final now = DateTime.now();
    return [
      Task(
        id: '1',
        title: 'Завершить проект',
        description: 'Доделать все задачи по проекту',
        priority: 1,
        tags: ['#работа', '#срочно'],
        date: now,
        isCompleted: false,
      ),
      Task(
        id: '2',
        title: 'Купить продукты',
        description: 'Молоко, хлеб, яйца',
        priority: 2,
        tags: ['#дом'],
        date: now,
        isCompleted: false,
      ),
      Task(
        id: '3',
        title: 'Позвонить клиенту',
        description: 'Обсудить детали проекта',
        priority: 1,
        tags: ['#работа', '#важно'],
        date: now,
        isCompleted: true,
      ),
      Task(
        id: '4',
        title: 'Встреча с командой',
        description: 'Обсуждение планов на неделю',
        priority: 3,
        tags: ['#работа'],
        date: now.add(const Duration(days: 1)),
        isCompleted: false,
      ),
      Task(
        id: '5',
        title: 'Тренировка',
        priority: 2,
        tags: ['#спорт'],
        date: now.add(const Duration(days: 2)),
        isCompleted: false,
      ),
      Task(
        id: '6',
        title: 'Изучить Flutter',
        description: 'Прочитать документацию',
        priority: 3,
        tags: ['#обучение'],
        date: now,
        isCompleted: false,
      ),
    ];
  }
}

