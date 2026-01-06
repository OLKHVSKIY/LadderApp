import 'package:flutter/material.dart';
import '../models/task.dart';

class AppleCalendar extends StatefulWidget {
  final DateTime initialDate;
  final Function(DateTime) onDateSelected;
  final VoidCallback onClose;
  final List<Task> tasks;

  const AppleCalendar({
    super.key,
    required this.initialDate,
    required this.onDateSelected,
    required this.onClose,
    this.tasks = const [],
  });

  @override
  State<AppleCalendar> createState() => _AppleCalendarState();
}

class _AppleCalendarState extends State<AppleCalendar> {
  late DateTime _selectedDate;
  late DateTime _currentMonth;
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _currentMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    _displayedMonth = _currentMonth;
  }

  List<DateTime> _getDaysInMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final daysInMonth = lastDay.day;
    
    // Находим первый день недели (понедельник = 1)
    int firstWeekday = firstDay.weekday;
    if (firstWeekday == 7) firstWeekday = 0; // Воскресенье становится 0
    
    final days = <DateTime>[];
    
    // Добавляем дни предыдущего месяца для заполнения первой недели
    final prevMonth = DateTime(month.year, month.month - 1);
    final prevMonthLastDay = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
    for (int i = firstWeekday - 1; i >= 0; i--) {
      days.add(DateTime(prevMonth.year, prevMonth.month, prevMonthLastDay - i));
    }
    
    // Добавляем дни текущего месяца
    for (int i = 1; i <= daysInMonth; i++) {
      days.add(DateTime(month.year, month.month, i));
    }
    
    // Добавляем дни следующего месяца для заполнения последней недели
    final remainingDays = 42 - days.length; // 6 недель * 7 дней = 42
    for (int i = 1; i <= remainingDays; i++) {
      days.add(DateTime(month.year, month.month + 1, i));
    }
    
    return days;
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  bool _isCurrentMonth(DateTime date, DateTime month) {
    return date.year == month.year && date.month == month.month;
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
    for (var task in widget.tasks) {
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
    const circleSize = 5.0;
    
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

  String _getMonthName(DateTime date) {
    const months = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];
    return months[date.month - 1];
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysInMonth(_displayedMonth);
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Заголовок с навигацией
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _previousMonth,
                icon: const Icon(Icons.chevron_left, color: Colors.black),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                '${_getMonthName(_displayedMonth)} ${_displayedMonth.year}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              IconButton(
                onPressed: _nextMonth,
                icon: const Icon(Icons.chevron_right, color: Colors.black),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Дни недели
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
                .map((day) => SizedBox(
                      width: 36,
                      child: Center(
                        child: Text(
                          day,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF666666),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          // Календарная сетка
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final date = days[index];
              final isSelected = _isSameDay(date, _selectedDate);
              final isCurrentMonth = _isCurrentMonth(date, _displayedMonth);
              final isToday = _isSameDay(date, now);

              return GestureDetector(
                onTap: () {
                  if (isCurrentMonth) {
                    setState(() {
                      _selectedDate = date;
                    });
                    widget.onDateSelected(date);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFDC3545)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected || isToday
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? Colors.white
                                : isCurrentMonth
                                    ? Colors.black
                                    : const Color(0xFFCCCCCC),
                          ),
                        ),
                      ),
                    ),
                    if (isCurrentMonth) ...[
                      const SizedBox(height: 2),
                      _buildPriorityIndicators(_getPrioritiesForDate(date)),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
        ),
      ),
    );
  }
}

