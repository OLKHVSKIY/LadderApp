import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/habit.dart';
import '../models/event.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

class AppleCalendar extends StatefulWidget {
  final DateTime initialDate;
  final Function(DateTime) onDateSelected;
  final VoidCallback onClose;
  final List<Task> tasks;
  // Привычки и события для меток под днями (квадрат — задача, круг — привычка,
  // звёздочка — событие).
  final List<HabitWithStats> habits;
  final List<Event> events;

  const AppleCalendar({
    super.key,
    required this.initialDate,
    required this.onDateSelected,
    required this.onClose,
    this.tasks = const [],
    this.habits = const [],
    this.events = const [],
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

  Color _priorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.yellow;
      case 3:
        return const Color(0xFF0066FF); // Синий цвет (не голубой)
      default:
        return Colors.grey;
    }
  }

  // Есть ли на дату активная привычка (по расписанию и периоду).
  bool _hasHabitOn(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    for (final h in widget.habits) {
      if (h.habit.isActiveOn(d)) return true;
    }
    return false;
  }

  // Есть ли на дату событие.
  bool _hasEventOn(DateTime date) {
    for (final e in widget.events) {
      if (e.occursOn(date)) return true;
    }
    return false;
  }

  // Метки под днём: задачи — квадраты со скруглёнными краями (по приоритетам),
  // привычки — зелёный круг, события — звёздочка.
  Widget _buildDayMarkers(DateTime date) {
    const size = 5.0;
    final markers = <Widget>[];

    // Задачи — скруглённые квадратики (по приоритетам).
    final priorities = _getPrioritiesForDate(date).toList()..sort();
    for (final p in priorities) {
      markers.add(Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _priorityColor(p),
          borderRadius: BorderRadius.circular(1.5),
        ),
      ));
    }

    // Привычка — зелёный круг.
    if (_hasHabitOn(date)) {
      markers.add(Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF34C759),
          shape: BoxShape.circle,
        ),
      ));
    }

    // Событие — звёздочка (рисуем сами для точного центрирования).
    if (_hasEventOn(date)) {
      markers.add(SizedBox(
        width: size + 2,
        height: size + 2,
        child: CustomPaint(
          painter: _StarPainter(const Color(0xFFFF2D55)),
        ),
      ));
    }

    if (markers.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: size + 2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < markers.length; i++) ...[
            if (i > 0) const SizedBox(width: 1.5),
            markers[i],
          ],
        ],
      ),
    );
  }

  String _getMonthName(DateTime date) {
    final months = [
      tr('Январь'),
      tr('Февраль'),
      tr('Март'),
      tr('Апрель'),
      tr('Май'),
      tr('Июнь'),
      tr('Июль'),
      tr('Август'),
      tr('Сентябрь'),
      tr('Октябрь'),
      tr('Ноябрь'),
      tr('Декабрь'),
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
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
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
                icon: Icon(CupertinoIcons.chevron_back, color: colors.icon),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                '${_getMonthName(_displayedMonth)} ${_displayedMonth.year}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              IconButton(
                onPressed: _nextMonth,
                icon: Icon(CupertinoIcons.chevron_forward, color: colors.icon),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Дни недели
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')]
                .map((day) => SizedBox(
                      width: 36,
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors.textSecondary,
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
                                    ? colors.textPrimary
                                    : colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    if (isCurrentMonth) ...[
                      const SizedBox(height: 2),
                      _buildDayMarkers(date),
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

// Залитая 5-конечная звезда, точно вписанная в центр бокса.
class _StarPainter extends CustomPainter {
  final Color color;
  _StarPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = math.min(size.width, size.height) / 2;
    final inner = outer * 0.46;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.color != color;
}

