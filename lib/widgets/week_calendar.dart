import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/habit.dart';
import '../models/event.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

class WeekCalendar extends StatefulWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;
  final List<Task> tasks;
  // Привычки и события для меток под днями (квадрат — задача, круг — привычка,
  // звёздочка — событие).
  final List<HabitWithStats> habits;
  final List<Event> events;

  const WeekCalendar({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.tasks = const [],
    this.habits = const [],
    this.events = const [],
  });

  @override
  State<WeekCalendar> createState() => _WeekCalendarState();
}

class _WeekCalendarState extends State<WeekCalendar> {
  // Большое базовое значение, чтобы свайпать недели в обе стороны.
  static const int _basePage = 10000;

  late final PageController _controller;
  // Понедельник недели, содержащей выбранную дату на момент инициализации.
  late DateTime _baseWeekStart;
  // Текущая показанная страница (нужна для синхронизации с PageView).
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _baseWeekStart = _weekStart(widget.selectedDate);
    _currentPage = _basePage;
    _controller = PageController(initialPage: _basePage);
  }

  @override
  void didUpdateWidget(WeekCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если выбранную дату сменили извне (тап по дню, возврат с экрана и т.п.)
    // и она попала в другую неделю — плавно листаем PageView к этой неделе.
    final targetPage = _pageForDate(widget.selectedDate);
    if (targetPage != _currentPage) {
      _currentPage = targetPage;
      if (_controller.hasClients) {
        _controller.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Понедельник недели для произвольной даты (без времени).
  DateTime _weekStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  // Индекс страницы PageView для недели, содержащей дату.
  int _pageForDate(DateTime date) {
    final diffDays = _weekStart(date).difference(_baseWeekStart).inDays;
    return _basePage + (diffDays ~/ 7);
  }

  // Даты недели для конкретной страницы PageView.
  List<DateTime> _weekDatesForPage(int page) {
    final start = _baseWeekStart.add(Duration(days: (page - _basePage) * 7));
    return List.generate(7, (index) => start.add(Duration(days: index)));
  }

  // Свайп сменил неделю — переносим выбор на тот же день новой недели,
  // чтобы родитель подгрузил задачи (и точки) для показанной недели.
  void _onPageChanged(int page) {
    if (page == _currentPage) return;
    _currentPage = page;
    final newStart = _baseWeekStart.add(Duration(days: (page - _basePage) * 7));
    final newDate = newStart.add(Duration(days: widget.selectedDate.weekday - 1));
    widget.onDateSelected(newDate);
  }

  String _getDayName(int weekday) {
    final days = [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')];
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
  // привычки — круг, события — звёздочка.
  Widget _buildDayIndicators(DateTime date) {
    const size = 6.0;

    final markers = <Widget>[];

    // Задачи — скруглённые квадратики (по одному на каждый присутствующий приоритет).
    final priorities = _getPrioritiesForDate(date).toList()..sort();
    for (final p in priorities) {
      markers.add(Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _priorityColor(p),
          borderRadius: BorderRadius.circular(2),
        ),
      ));
    }

    // Привычка — круг.
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

    // Событие — звёздочка (рисуем сами, чтобы она была точно по центру —
    // у иконочного глифа звезды центр смещён вниз).
    if (_hasEventOn(date)) {
      markers.add(SizedBox(
        width: size + 2,
        height: size + 2,
        child: CustomPaint(
          painter: _StarPainter(const Color(0xFFFF2D55)),
        ),
      ));
    }

    // Всегда фиксированная высота для выравнивания дней.
    if (markers.isEmpty) {
      return const SizedBox(height: size + 2, width: double.infinity);
    }

    return SizedBox(
      height: size + 2,
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < markers.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            markers[i],
          ],
        ],
      ),
    );
  }

  // Ряд из 7 дней одной недели (одна страница PageView).
  Widget _buildWeekRow(List<DateTime> weekDates) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: weekDates.map((date) {
        final isActive = _isSameDay(date, widget.selectedDate);
        final isToday = _isSameDay(date, DateTime.now());
        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => widget.onDateSelected(date),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFDC3545)
                        : colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: isToday
                        ? Border.all(
                            color: const Color(0xFFDC3545),
                            width: 2,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _getDayName(date.weekday),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isActive ? Colors.white : colors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _buildDayIndicators(date),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashColor = AppColors.of(context).divider;
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: const EdgeInsets.only(bottom: 0, top: 5),
      // Высота под ряд дней + увеличенный отступ над метками + место под линией.
      child: SizedBox(
        height: 92,
        child: PageView.builder(
          controller: _controller,
          physics: const BouncingScrollPhysics(),
          onPageChanged: _onPageChanged,
          itemBuilder: (context, page) {
            // Пунктирная линия лежит внутри страницы, поэтому при свайпе
            // едет вместе с днями в нужную сторону.
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _buildWeekRow(_weekDatesForPage(page)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: CustomPaint(
                    painter: DashedLinePainter(color: dashColor),
                    size: const Size(double.infinity, 1),
                  ),
                ),
              ],
            );
          },
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

class DashedLinePainter extends CustomPainter {
  final Color color;

  DashedLinePainter({this.color = const Color(0xFFDAD7D7)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
  bool shouldRepaint(covariant DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

