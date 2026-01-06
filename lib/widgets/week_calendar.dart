import 'package:flutter/material.dart';
import '../models/task.dart';

class WeekCalendar extends StatelessWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;
  final List<Task> tasks;

  const WeekCalendar({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.tasks = const [],
  });

  List<DateTime> _getWeekDates() {
    final startOfWeek = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );
    return List.generate(7, (index) => startOfWeek.add(Duration(days: index)));
  }

  String _getDayName(int weekday) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[weekday - 1];
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  // Проверяет, попадает ли дата в диапазон задачи
  bool _isDateInTaskRange(DateTime date, Task task) {
    if (task.endDate != null) {
      // Для периода проверяем, попадает ли дата в диапазон
      final normalizedDate = DateTime(date.year, date.month, date.day);
      final normalizedStart = DateTime(task.date.year, task.date.month, task.date.day);
      final normalizedEnd = DateTime(task.endDate!.year, task.endDate!.month, task.endDate!.day);
      return normalizedDate.isAfter(normalizedStart.subtract(const Duration(days: 1))) &&
          normalizedDate.isBefore(normalizedEnd.add(const Duration(days: 1)));
    } else {
      // Для одной даты проверяем точное совпадение
      return _isSameDay(date, task.date);
    }
  }

  // Получает список приоритетов для конкретной даты
  Set<int> _getPrioritiesForDate(DateTime date) {
    final priorities = <int>{};
    for (var task in tasks) {
      if (_isDateInTaskRange(date, task)) {
        priorities.add(task.priority);
      }
    }
    return priorities;
  }

  // Виджет для отображения кружочков приоритетов
  Widget _buildPriorityIndicators(Set<int> priorities) {
    if (priorities.isEmpty) {
      return const SizedBox.shrink();
    }

    // Сортируем приоритеты: 1 (красный), 2 (желтый), 3 (синий)
    final sortedPriorities = priorities.toList()..sort();
    
    // Определяем количество кружочков
    final count = sortedPriorities.length;
    
    // Определяем смещение для наезжания (примерно 1px)
    const overlap = 1.0;
    const circleSize = 7.0;
    
    // Вычисляем общую ширину всех кружочков с учетом наезжания
    final totalWidth = circleSize + (count - 1) * (circleSize - overlap);
    
    return Center(
      child: SizedBox(
        width: totalWidth,
        height: circleSize,
        child: Stack(
          children: List.generate(count, (index) {
            final priority = sortedPriorities[index];
            Color color;
            switch (priority) {
              case 1:
                color = Colors.red;
                break;
              case 2:
                color = Colors.yellow;
                break;
              case 3:
                color = const Color(0xFF0066FF); // Синий цвет (не голубой)
                break;
              default:
                color = Colors.grey;
            }
            
            // Позиционируем кружочки так, чтобы они наезжали друг на друга
            // и вся группа была по центру
            final leftOffset = index * (circleSize - overlap);
            
            return Positioned(
              left: leftOffset,
              child: Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekDates = _getWeekDates();

    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: const EdgeInsets.only(bottom: 0),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 19),
            child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: weekDates.map((date) {
          final isActive = _isSameDay(date, selectedDate);
          final isToday = _isSameDay(date, DateTime.now());
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => onDateSelected(date),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFFDC3545)
                          : const Color(0xFFF7F6F7),
                      borderRadius: BorderRadius.circular(12),
                      border: isToday
                          ? Border.all(
                              color: const Color(0xFFDC3545),
                              width: 1,
                            )
                          : null,
                    ),
                    child: Column(
                      children: [
                        Text(
                          _getDayName(date.weekday),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isActive ? Colors.white : const Color(0xFF999999),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isActive ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _buildPriorityIndicators(_getPrioritiesForDate(date)),
              ],
            ),
          );
        }).toList(),
      ),
          ),
          // Пунктирная линия
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              painter: DashedLinePainter(),
              size: Size(double.infinity, 1),
            ),
          ),
        ],
      ),
    );
  }
}

class DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFDAD7D7)
      ..strokeWidth = 1;

    const dashWidth = 5.0;
    const dashSpace = 3.0;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

