import 'package:flutter/material.dart';
import '../models/task.dart';
import 'task_card.dart';

class TaskList extends StatelessWidget {
  final List<Task> tasks;
  final DateTime selectedDate;
  final Function(String, bool) onTaskToggle;
  final String? openMenuTaskId;
  final Function(String?, GlobalKey?)? onMenuToggle;
  final bool isLoading;

  const TaskList({
    super.key,
    required this.tasks,
    required this.selectedDate,
    required this.onTaskToggle,
    this.openMenuTaskId,
    this.onMenuToggle,
    this.isLoading = false,
  });

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  List<Task> _getFilteredTasks() {
    return tasks.where((task) {
      if (task.endDate != null) {
        // Для периода проверяем, попадает ли выбранная дата в диапазон
        return selectedDate.isAfter(task.date.subtract(const Duration(days: 1))) &&
            selectedDate.isBefore(task.endDate!.add(const Duration(days: 1)));
      } else {
        // Для одной даты проверяем точное совпадение
        return _isSameDay(task.date, selectedDate);
      }
    }).toList();
  }

  Map<int, List<Task>> _groupByPriority(List<Task> tasks) {
    final grouped = <int, List<Task>>{};
    for (var task in tasks) {
      grouped.putIfAbsent(task.priority, () => []).add(task);
    }
    return grouped;
  }

  String _getPriorityIconPath(int priority) {
    switch (priority) {
      case 1:
        return 'assets/icon/thunder-red.png';
      case 2:
        return 'assets/icon/thunder-yellow.png';
      case 3:
        return 'assets/icon/thunder-blue.png';
      default:
        return 'assets/icon/thunder-red.png';
    }
  }

  String _getPriorityText(int priority) {
    return 'Приоритет $priority';
  }

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _getFilteredTasks();

    // Не показываем "Нет задач" во время загрузки, чтобы избежать мерцания
    if (filteredTasks.isEmpty && !isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'Нет задач на выбранную дату',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF999999),
            ),
          ),
        ),
      );
    }

    // Во время загрузки показываем пустой виджет
    if (isLoading && filteredTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final groupedTasks = _groupByPriority(filteredTasks);
    final sortedPriorities = groupedTasks.keys.toList()..sort();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedPriorities.map((priority) {
        final priorityIndex = sortedPriorities.indexOf(priority);
        final priorityTasks = groupedTasks[priority]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок приоритета
            Padding(
              padding: EdgeInsets.only(
                left: 4,
                bottom: 4,
                top: priorityIndex == 0 ? 20 : 0,
              ),
              child: Row(
                children: [
                  // Иконка приоритета
                  Image.asset(
                    _getPriorityIconPath(priority),
                    width: 20,
                    height: 20,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getPriorityText(priority),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            // Задачи этого приоритета
            ...priorityTasks.map((task) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TaskCard(
                    key: ValueKey(task.id),
                    task: task,
                    onToggle: (isCompleted) =>
                        onTaskToggle(task.id, isCompleted),
                    openMenuTaskId: openMenuTaskId,
                    onMenuToggle: onMenuToggle,
                  ),
                )),
          ],
        );
      }).toList(),
    );
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

