import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/bottom_navigation.dart';
import '../widgets/sidebar.dart';
import 'tasks_page.dart';
import 'plan_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import 'notes_page.dart';
import '../data/repositories/task_repository.dart';
import '../data/database_instance.dart';
import '../models/task.dart' as model;

enum ListViewType {
  oneDay,
  week,
  month,
}

enum TimeStep {
  fiveMinutes,
  tenMinutes,
  thirtyMinutes,
  oneHour,
}

class GptPlanPage extends StatefulWidget {
  const GptPlanPage({super.key});

  @override
  State<GptPlanPage> createState() => _GptPlanPageState();
}

class _GptPlanPageState extends State<GptPlanPage> with TickerProviderStateMixin {
  bool _isSidebarOpen = false;
  
  ListViewType _listViewType = ListViewType.oneDay;
  TimeStep _timeStep = TimeStep.fiveMinutes;
  DateTime _selectedDate = DateTime.now();
  DateTime? _previousSelectedDate;
  
  late final ScrollController _dayContentScrollController;
  late final ScrollController _weekScrollController;
  
  DateTime _currentTime = DateTime.now();
  Timer? _timeUpdateTimer;
  double _currentScrollOffset = 0.0;
  
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  TaskRepository? _taskRepository;
  List<model.Task> _monthTasks = [];
  
  TaskRepository get taskRepository {
    _taskRepository ??= TaskRepository(appDatabase);
    return _taskRepository!;
  }

  @override
  void initState() {
    super.initState();
    _dayContentScrollController = ScrollController();
    _weekScrollController = ScrollController();
    _previousSelectedDate = _selectedDate;
    _currentTime = DateTime.now();
    // Загружаем сохраненные настройки
    _loadSettings().then((_) {
      if (mounted && _listViewType == ListViewType.month) {
        _loadMonthTasks();
      }
    });
    // Обновляем текущее время каждые 30 секунд для плавного движения
    _timeUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final listViewTypeIndex = prefs.getInt('listViewType') ?? 0;
    final timeStepIndex = prefs.getInt('timeStep') ?? 0;
    
    if (mounted) {
      setState(() {
        _listViewType = ListViewType.values[listViewTypeIndex.clamp(0, ListViewType.values.length - 1)];
        _timeStep = TimeStep.values[timeStepIndex.clamp(0, TimeStep.values.length - 1)];
      });
      
      if (_listViewType == ListViewType.month) {
        _loadMonthTasks();
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('listViewType', _listViewType.index);
    await prefs.setInt('timeStep', _timeStep.index);
  }
  
  Future<void> _loadMonthTasks() async {
    final firstDay = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final lastDay = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
    final tasks = await taskRepository.tasksForDateRange(firstDay, lastDay);
    if (mounted) {
      setState(() {
        _monthTasks = tasks;
      });
    }
  }

  @override
  void dispose() {
    _dayContentScrollController.dispose();
    _weekScrollController.dispose();
    _timeUpdateTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }

  void _navigateTo(Widget page, {bool slideFromRight = false}) {
    if (page is SettingsPage) {
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => page,
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: page,
          ),
        ),
      );
    }
  }

  int _getTimeLinesCount() {
    switch (_timeStep) {
      case TimeStep.fiveMinutes:
        return 12; // 12 строк в часе: 00:00 (черная), 00:05, 00:10, ..., 00:55
      case TimeStep.tenMinutes:
        return 6; // 6 строк в часе: 00:00 (черная), 00:10, 00:20, ..., 00:50
      case TimeStep.thirtyMinutes:
        return 2; // 2 строки в часе: 00:00 (черная) и 00:30
      case TimeStep.oneHour:
        return 1; // 1 строка в часе: только 00:00 (черная)
    }
  }

  int _getMinutesPerLine() {
    switch (_timeStep) {
      case TimeStep.fiveMinutes:
        return 5;
      case TimeStep.tenMinutes:
        return 10;
      case TimeStep.thirtyMinutes:
        return 30; // 30 минут между строками
      case TimeStep.oneHour:
        return 60; // 60 минут между строками
    }
  }

  // Количество часов, видимых на экране
  int _getVisibleHours() {
    switch (_timeStep) {
      case TimeStep.fiveMinutes:
        return 5; // 00:00-04:00
      case TimeStep.tenMinutes:
        return 5; // 00:00-05:00
      case TimeStep.thirtyMinutes:
        return 12; // 00:00-12:00
      case TimeStep.oneHour:
        return 12; // 00:00-12:00
    }
  }

  // Высота одного часа (в пикселях) - фиксированная, независимо от количества полос
  double _getHourHeight(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top - 10;
    final sliderHeight = 60.0; // Высота слайдера дней
    final bottomPadding = MediaQuery.of(context).padding.bottom + 75 + 60; // Навигация и кнопки
    final availableHeight = screenHeight - topPadding - sliderHeight - bottomPadding;
    
    final visibleHours = _getVisibleHours();
    final hourHeight = availableHeight / visibleHours;
    // Минимальная высота часа - чтобы время было видно
    // При шаге 5 минут нужно больше места (12 строк в часе), минимум 240px на час
    // Это даст примерно 20px на строку, что достаточно для полного отображения времени
    final minHourHeight = _timeStep == TimeStep.fiveMinutes ? 240.0 : 70.0;
    return hourHeight < minHourHeight ? minHourHeight : hourHeight;
  }

  // Вычисляет позицию текущего времени в пикселях относительно начала списка
  double _getCurrentTimePosition(BuildContext context) {
    final hourHeight = _getHourHeight(context);
    final linesPerHour = _getTimeLinesCount();
    final lineHeight = hourHeight / linesPerHour;
    final minutesPerLine = _getMinutesPerLine();
    
    // Вычисляем общее количество минут с начала дня (00:00)
    final totalMinutes = _currentTime.hour * 60 + _currentTime.minute + _currentTime.second / 60.0;
    
    // Вычисляем позицию в пикселях
    // Учитываем, что каждая строка представляет определенное количество минут
    final lineIndex = (totalMinutes / minutesPerLine).floor();
    final positionInLine = (totalMinutes % minutesPerLine) / minutesPerLine;
    
    // Позиция относительно начала списка (без учета padding)
    return lineIndex * lineHeight + positionInLine * lineHeight;
  }

  // Проверяет, виден ли индикатор текущего времени (для сегодняшнего дня)
  bool _shouldShowCurrentTimeIndicator() {
    if (_listViewType == ListViewType.oneDay) {
      // Показываем индикатор только если выбран сегодняшний день
      return _isSameDay(_selectedDate, DateTime.now());
    } else if (_listViewType == ListViewType.week) {
      // Для недельного вида проверяем, входит ли сегодняшний день в неделю
      final weekDates = _getWeekDates();
      final now = DateTime.now();
      return weekDates.any((date) => _isSameDay(date, now));
    }
    return false;
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  List<DateTime> _getWeekDates() {
    final selectedDay = _selectedDate;
    // Находим понедельник недели, в которую входит выбранный день
    final monday = selectedDay.subtract(Duration(days: selectedDay.weekday - 1));
    return List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  String _getDayName(int weekday) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[weekday - 1];
  }

  Widget _buildWeekDaysHeader() {
    final weekDates = _getWeekDates();
    return Container(
      padding: const EdgeInsets.only(left: 55, right: 16, top: 12, bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: weekDates.map((date) {
          final isSelected = _isSameDay(date, _selectedDate);
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDate = date;
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // День недели
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.black : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getDayName(date.weekday),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF666666),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Дата
                  Text(
                    date.day.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                      color: isSelected ? Colors.black : const Color(0xFF666666),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }


  void _openSearch() {
    setState(() {
      _isSearchOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocusNode.requestFocus();
      });
    });
  }

  void _closeSearch() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearchOpen = false;
      _searchController.clear();
    });
  }

  void _openSettings() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => _buildSettingsModal(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: AlwaysStoppedAnimation(1.0),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildSettingsModal() {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Невидимая область для обработки клика вне шторки
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          // Шторка с контентом
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {}, // Предотвращаем закрытие при клике на контент
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Material(
                  color: const Color(0xFFF5F5F5),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ручка для перетаскивания
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Заголовок "Фильтры Планировщика" (две строки)
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Фильтры',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                                height: 1.2,
                              ),
                            ),
                            Text(
                              'Планировщика',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Секция "Тип"
                        const Text(
                          'Тип',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildListViewTypeButton('Один день', ListViewType.oneDay, 'assets/icon/day-list.png'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildListViewTypeButton('Неделя', ListViewType.week, 'assets/icon/weeks-list.png'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildListViewTypeButton('Месяц', ListViewType.month, 'assets/icon/month-list.png'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // Секция "Шаг времени"
                        const Text(
                          'Шаг времени',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTimeStepButton('5 мин', TimeStep.fiveMinutes),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTimeStepButton('10 мин', TimeStep.tenMinutes),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTimeStepButton('30 мин', TimeStep.thirtyMinutes),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTimeStepButton('1 час', TimeStep.oneHour),
                            ),
                          ],
                        ),
                        SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeStepButton(String label, TimeStep step) {
    final isSelected = _timeStep == step;
    return GestureDetector(
      onTap: () {
        setState(() {
          _timeStep = step;
          if (_dayContentScrollController.hasClients) {
            _dayContentScrollController.jumpTo(0);
          }
          if (_weekScrollController.hasClients) {
            _weekScrollController.jumpTo(0);
          }
        });
        _saveSettings();
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.black : const Color(0xFFE0E0E0),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF666666),
            ),
            softWrap: false,
            overflow: TextOverflow.visible,
          ),
        ),
      ),
    );
  }
  
  Widget _buildListViewTypeButton(String label, ListViewType type, String iconPath) {
    final isSelected = _listViewType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _listViewType = type;
          if (_dayContentScrollController.hasClients) {
            _dayContentScrollController.jumpTo(0);
          }
          if (_weekScrollController.hasClients) {
            _weekScrollController.jumpTo(0);
          }
        });
        if (type == ListViewType.month) {
          _loadMonthTasks();
        }
        _saveSettings();
        Navigator.of(context).pop();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 66,
            decoration: BoxDecoration(
              color: isSelected ? Colors.black : const Color(0xFFEAEAEA),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Center(
              child: Image.asset(
                iconPath,
                width: 65,
                height: 65,
                color: isSelected ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF666666),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const monthNames = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return monthNames[month - 1];
  }
    
  Widget _buildWeekSlider() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _previousSelectedDate = _selectedDate;
              if (_listViewType == ListViewType.oneDay) {
              _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              } else if (_listViewType == ListViewType.week) {
                _selectedDate = _selectedDate.subtract(const Duration(days: 7));
              } else {
                _selectedDate = DateTime(
                  _selectedDate.year,
                  _selectedDate.month - 1,
                  _selectedDate.day,
                );
              }
              if (_dayContentScrollController.hasClients) {
                _dayContentScrollController.jumpTo(0);
              }
              if (_weekScrollController.hasClients) {
                _weekScrollController.jumpTo(0);
              }
              if (_listViewType == ListViewType.month) {
                _loadMonthTasks();
              }
            });
          },
          child: const Icon(Icons.chevron_left, color: Colors.black),
        ),
        Expanded(
          child: Text(
            _listViewType == ListViewType.oneDay
                ? '${_selectedDate.day} ${_getMonthName(_selectedDate.month)}'
                : _listViewType == ListViewType.week
                    ? 'Неделя ${_selectedDate.day.toString().padLeft(2, '0')}.${_selectedDate.month.toString().padLeft(2, '0')}'
                    : '${_getMonthName(_selectedDate.month)} ${_selectedDate.year}',
            textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
              fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
        ),
        GestureDetector(
          onTap: () {
      setState(() {
              _previousSelectedDate = _selectedDate;
              if (_listViewType == ListViewType.oneDay) {
              _selectedDate = _selectedDate.add(const Duration(days: 1));
              } else if (_listViewType == ListViewType.week) {
                _selectedDate = _selectedDate.add(const Duration(days: 7));
              } else {
                _selectedDate = DateTime(
                  _selectedDate.year,
                  _selectedDate.month + 1,
                  _selectedDate.day,
                );
              }
              if (_dayContentScrollController.hasClients) {
                _dayContentScrollController.jumpTo(0);
              }
              if (_weekScrollController.hasClients) {
                _weekScrollController.jumpTo(0);
              }
              if (_listViewType == ListViewType.month) {
                _loadMonthTasks();
              }
            });
          },
          child: const Icon(Icons.chevron_right, color: Colors.black),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top - 10),
            child: Column(
              children: [
                // Слайдер дней/недели/месяца (скрыт для недельного вида)
                if (_listViewType != ListViewType.week)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: _buildWeekSlider(),
                  ),
                // Заголовок дней недели (только для недельного вида)
                if (_listViewType == ListViewType.week)
                  _buildWeekDaysHeader(),
                // Основной контент
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final offsetAnimation = Tween<Offset>(
                        begin: _previousSelectedDate != null && _previousSelectedDate!.isBefore(_selectedDate)
                            ? const Offset(1.0, 0.0)
                            : const Offset(-1.0, 0.0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                      return SlideTransition(
                        position: offsetAnimation,
                        child: child,
                      );
                    },
                    child: _buildTimelineView(),
                  ),
                ),
              ],
            ),
          ),
          // Кнопка поиска с полем ввода (трансформируется из круга в овал)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            left: 22,
            bottom: MediaQuery.of(context).padding.bottom + 75 - 17 + (MediaQuery.of(context).viewInsets.bottom > 0 ? MediaQuery.of(context).viewInsets.bottom - 40 : 0),
            child: GestureDetector(
              onTap: _isSearchOpen ? null : _openSearch,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: _isSearchOpen 
                    ? MediaQuery.of(context).size.width - 22 - 22 - 52 - 12 // Ширина экрана минус левый отступ (22) минус правый отступ (22) минус кнопка фильтра (52) минус промежуток (12)
                    : 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_isSearchOpen ? 26 : 26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: _isSearchOpen ? 16 : 0,
                ),
                child: Row(
                  children: [
                    if (_isSearchOpen)
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            FocusScope.of(context).unfocus();
                            _closeSearch();
                          },
                          decoration: const InputDecoration(
                            hintText: 'Поиск...',
                            border: InputBorder.none,
                            hintStyle: TextStyle(color: Color(0xFF999999)),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      )
                    else
                      Expanded(
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: ClipRect(
                              child: SvgPicture.asset(
                                'assets/icon/glass.svg',
                                width: 24,
                                height: 24,
                                fit: BoxFit.contain,
                                colorFilter: const ColorFilter.mode(
                                  Colors.black,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_isSearchOpen)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: GestureDetector(
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            _closeSearch();
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.close,
                              color: Colors.black,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            right: 22,
            bottom: MediaQuery.of(context).padding.bottom + 75 - 17 + (MediaQuery.of(context).viewInsets.bottom > 0 ? MediaQuery.of(context).viewInsets.bottom - 40 : 0),
            child: GestureDetector(
              onTap: _openSettings,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: ClipRect(
                    child: SvgPicture.asset(
                      'assets/icon/filters.svg',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      colorFilter: const ColorFilter.mode(
                        Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Sidebar(
            isOpen: _isSidebarOpen,
            onClose: _toggleSidebar,
            onTasksTap: () {
              _toggleSidebar();
              _navigateTo(const TasksPage(), slideFromRight: false);
            },
            onChatTap: () {
              _toggleSidebar();
              _navigateTo(const ChatPage(), slideFromRight: true);
            },
          ),
          BottomNavigation(
            currentIndex: 1, // Список
            isSidebarOpen: _isSidebarOpen,
            onAddTask: () {},
            onTasksTap: () {
              _navigateTo(const TasksPage(), slideFromRight: false);
            },
            onPlanTap: () {
              _navigateTo(const PlanPage(), slideFromRight: true);
            },
            onGptTap: () {
              // Уже на странице Список
            },
            onNotesTap: () {
              _navigateTo(const NotesPage());
            },
            onIndexChanged: (index) {
              if (index == 0) {
                _navigateTo(const TasksPage(), slideFromRight: false);
              } else if (index == 2) {
                _navigateTo(const PlanPage(), slideFromRight: true);
              } else if (index == 3) {
                _navigateTo(const NotesPage());
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineView() {
    switch (_listViewType) {
      case ListViewType.oneDay:
        return Container(
          key: ValueKey('oneDay_${_selectedDate.year}_${_selectedDate.month}_${_selectedDate.day}'),
          child: _buildDayView(),
        );
      case ListViewType.week:
        return Container(
          key: ValueKey('week_${_selectedDate.year}_${_selectedDate.month}_${_selectedDate.day}'),
          child: _buildWeekView(),
        );
      case ListViewType.month:
        return Container(
          key: ValueKey('month_${_selectedDate.year}_${_selectedDate.month}'),
          child: _buildMonthView(),
        );
    }
  }

  Widget _buildDayView() {
    const hoursInDay = 24;
    final linesPerHour = _getTimeLinesCount();
    final minutesPerLine = _getMinutesPerLine();
    final totalLines = hoursInDay * linesPerHour;
    final hourHeight = _getHourHeight(context);
    final lineHeight = hourHeight / linesPerHour;
    
    return Container(
      color: Colors.white,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification || notification is ScrollEndNotification) {
            setState(() {
              _currentScrollOffset = notification.metrics.pixels;
            });
          }
          return false;
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ListView.builder(
              controller: _dayContentScrollController,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 75 + 60 + 20,
              ),
              itemCount: totalLines + 1, // +1 для закрывающей полосы внизу
              itemBuilder: (context, index) {
                // Последняя строка - закрывающая полоса для 23:00
                if (index == totalLines) {
                  return SizedBox(
                    height: 1.0,
      child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                        // Столбец времени
          Container(
            width: 70,
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Color(0xFFB0B0B0), width: 1.0),
                            ),
                          ),
                        ),
                        // Вертикальная линия-разделитель
                        Container(
                          width: 1,
                          height: 1.0,
                          color: const Color(0xFFB0B0B0),
                        ),
                        // Основной контент (закрывающая полоса)
                        Expanded(
                          child: Container(
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Color(0xFFB0B0B0), width: 1.0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                
                final totalMinutes = index * minutesPerLine;
                final hour = (totalMinutes ~/ 60) % 24;
                final minute = totalMinutes % 60;
                
                final isHourStart = minute == 0;
                final shouldShowTime = minute == 0;
                
                return Container(
                  height: lineHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Столбец времени (БЕЗ промежуточных горизонтальных линий - только черная на часах)
                      Container(
                        width: 60,
                        decoration: BoxDecoration(
                          // Серая линия ТОЛЬКО на часах (вверху столбца времени)
                          border: isHourStart
                              ? const Border(
                                  top: BorderSide(color: Color(0xFFB0B0B0), width: 1.0),
                                )
                              : null,
                        ),
                  child: Padding(
                          padding: EdgeInsets.only(
                            top: isHourStart ? 4 : 2,
                            right: 8,
                            bottom: 0,
                          ),
                    child: Align(
                      alignment: Alignment.topRight,
                            child: shouldShowTime
                                ? Text(
                                    '${hour.toString().padLeft(2, '0')}:00',
                        style: const TextStyle(
                          fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      height: 1.2,
                        ),
                        overflow: TextOverflow.visible,
                                  )
                                : const SizedBox.shrink(),
                      ),
            ),
          ),
          // Вертикальная линия-разделитель
          Container(
            width: 1,
                        height: lineHeight,
                        color: const Color(0xFFE0E0E0),
          ),
                      // Основной контент (С промежуточными горизонтальными линиями между ВСЕМИ строками)
          Expanded(
            child: Container(
                    decoration: BoxDecoration(
                            color: Colors.white,
                      border: Border(
                              // Темно-серая линия на часах (вверху), серая на промежуточных строках (внизу)
                              // ВКЛЮЧАЯ первую строку после 00:00 (index == 1, minute == 5/10/30, isHourStart == false)
                              top: isHourStart
                                  ? const BorderSide(color: Color(0xFFB0B0B0), width: 1.0)
                                  : const BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                              bottom: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                    ),
                  );
                },
              ),
            // Индикатор текущего времени (черная полоса с кругом)
            // Показываем только для сегодняшнего дня
            // Позиция вычисляется относительно прокрученного контента
            if (_shouldShowCurrentTimeIndicator())
              Positioned(
                top: (_getCurrentTimePosition(context) - _currentScrollOffset).clamp(0.0, double.infinity),
                left: 0,
                right: 0,
                height: 1.0, // Фиксированная высота для Stack
                child: IgnorePointer(
                  child: SizedBox(
                    height: 1.0,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Круг в начале (в столбце времени)
                        Positioned(
                          left: 50, // Позиция круга в столбце времени
                          top: -3, // Центрируем круг на линии
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        // Черная полоска между кругом и вертикальной линией
                        Positioned(
                          left: 56, // 50 (позиция круга) + 6 (ширина круга)
                          top: 0,
                          width: 14, // До вертикальной линии (70 - 56 = 14)
                          child: Container(
                            height: 1.0,
                            color: Colors.black,
                          ),
                        ),
                        // Черная горизонтальная линия справа от вертикальной линии-разделителя
                        Positioned(
                          left: 70, // Начинаем с края столбца времени для непрерывности линии
                          top: 0,
                          right: 0,
                          child: Container(
                            height: 1.0,
                            color: Colors.black,
                          ),
                        ),
        ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekView() {
    const hoursInDay = 24;
    final linesPerHour = _getTimeLinesCount();
    final minutesPerLine = _getMinutesPerLine();
    final totalLines = hoursInDay * linesPerHour;
    final hourHeight = _getHourHeight(context); // Высота одного часа (фиксированная)
    final lineHeight = hourHeight / linesPerHour; // Высота одной строки
    final weekDates = _getWeekDates();
    
    return Container(
      color: Colors.white, // Белый фон
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification || notification is ScrollEndNotification) {
            setState(() {
              _currentScrollOffset = notification.metrics.pixels;
            });
          }
          return false;
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ListView.builder(
              controller: _weekScrollController,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 75 + 60 + 20, // Отступ снизу для навигации
              ),
              itemCount: totalLines + 1, // +1 для закрывающей полосы внизу
              itemBuilder: (context, index) {
                // Последняя строка - закрывающая полоса для 23:00
                if (index == totalLines) {
                  return SizedBox(
                    height: 1.0,
      child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                        // Столбец времени
          Container(
            width: 70,
                            decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Color(0xFFB0B0B0), width: 1.0),
                            ),
            ),
          ),
          // Вертикальная линия-разделитель
          Container(
            width: 1,
                          height: 1.0,
                          color: const Color(0xFFE0E0E0),
          ),
                        // Колонки для дней недели (закрывающая полоса)
          Expanded(
            child: Row(
                            children: weekDates.asMap().entries.map((entry) {
                return Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                                      top: const BorderSide(color: Color(0xFFE0E0E0), width: 1.0),
                                      // Вертикальная граница между днями (кроме последнего дня)
                                      right: entry.key < weekDates.length - 1
                                          ? const BorderSide(
                                              color: Color(0xFFE0E0E0),
                          width: 0.5,
                                            )
                                          : BorderSide.none,
                                    ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

                final totalMinutes = index * minutesPerLine;
                final hour = (totalMinutes ~/ 60) % 24;
                final minute = totalMinutes % 60;
                
                final isHourStart = minute == 0;
                final shouldShowTime = minute == 0;
                
                // ПРОСТАЯ И НАДЕЖНАЯ СТРУКТУРА: каждая строка явно создается
                return SizedBox(
                  height: lineHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                      // Столбец времени (БЕЗ промежуточных горизонтальных линий - только черная на часах)
                      Container(
                        width: 60,
                        decoration: BoxDecoration(
                          // Серая линия ТОЛЬКО на часах (вверху столбца времени)
                          border: isHourStart
                              ? const Border(
                                  top: BorderSide(color: Color(0xFFB0B0B0), width: 1.0),
                                )
                              : null,
                        ),
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: isHourStart ? 4 : 2,
                            right: 8,
                            bottom: 0,
                          ),
                          child: Align(
                            alignment: Alignment.topRight,
                            child: shouldShowTime
                                ? Text(
                                    '${hour.toString().padLeft(2, '0')}:00',
                            style: const TextStyle(
                              fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      height: 1.2,
                                    ),
                            overflow: TextOverflow.visible,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      // Вертикальная линия-разделитель
                      Container(
                        width: 1,
                        height: lineHeight,
                        color: const Color(0xFFE0E0E0),
                      ),
                      // Колонки для дней недели (С промежуточными горизонтальными линиями между ВСЕМИ строками)
                      Expanded(
                        child: Row(
                          children: weekDates.asMap().entries.map((entry) {
                            final dayDate = entry.value;
                            final isTodayColumn = _isSameDay(dayDate, DateTime.now());
                            
                            return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                                  color: isTodayColumn ? const Color(0xFFF5F5F5) : Colors.white,
                                  border: Border(
                                    // Темно-серая линия на часах (вверху), серая на всех промежуточных строках (включая первую после 00:00)
                                    top: isHourStart
                                        ? const BorderSide(color: Color(0xFFB0B0B0), width: 1.0)
                                        : const BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                                    bottom: BorderSide.none,
                                    // Вертикальная граница между днями (кроме последнего дня)
                                    right: entry.key < weekDates.length - 1
                                        ? const BorderSide(
                                            color: Color(0xFFE0E0E0),
                                            width: 0.5,
                                          )
                                        : BorderSide.none,
                        ),
                      ),
                    ),
                  );
                          }).toList(),
              ),
            ),
          ],
                  ),
                );
              },
            ),
            // Индикатор текущего времени (черная полоса с кругом) для недельного вида
            // Показываем только для сегодняшнего дня
            // Позиция вычисляется относительно прокрученного контента
            if (_shouldShowCurrentTimeIndicator())
              Positioned(
                top: (_getCurrentTimePosition(context) - _currentScrollOffset).clamp(0.0, double.infinity),
                left: 0,
                right: 0,
                height: 1.0, // Фиксированная высота для Stack
                child: IgnorePointer(
                  child: SizedBox(
                    height: 1.0,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Круг в начале (в столбце времени)
                        Positioned(
                          left: 50, // Позиция круга в столбце времени
                          top: -3, // Центрируем круг на линии (уменьшен с -4)
        child: Container(
                            width: 6, // Уменьшен с 8 до 6
                            height: 6, // Уменьшен с 8 до 6
                decoration: const BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        // Черная полоска между кругом и вертикальной линией (от правого края круга до вертикальной линии)
                        Positioned(
                          left: 56, // 50 (позиция круга) + 6 (ширина круга)
                          top: 0,
                          width: 15, // До вертикальной линии (71 - 56 = 15, включая саму вертикальную линию)
                          child: Container(
                            height: 1.0,
                        color: Colors.black,
                      ),
                    ),
                        // Черная горизонтальная линия справа от вертикальной линии-разделителя
                        Positioned(
                          left: 71, // 70 (столбец времени) + 1 (вертикальная линия)
                          top: 0,
                          right: 0,
                          child: Container(
                            height: 1.0,
                        color: Colors.black,
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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

  bool _isCurrentMonth(DateTime date, DateTime month) {
    return date.year == month.year && date.month == month.month;
  }

  bool _isDateInTaskRange(DateTime date, model.Task task) {
    if (task.endDate != null) {
      final normalizedDate = DateTime(date.year, date.month, date.day);
      final normalizedStart = DateTime(task.date.year, task.date.month, task.date.day);
      final normalizedEnd = DateTime(task.endDate!.year, task.endDate!.month, task.endDate!.day);
      return normalizedDate.isAfter(normalizedStart.subtract(const Duration(days: 1))) &&
          normalizedDate.isBefore(normalizedEnd.add(const Duration(days: 1)));
    } else {
      return _isSameDay(date, task.date);
    }
  }

  Set<int> _getPrioritiesForDate(DateTime date) {
    final priorities = <int>{};
    for (var task in _monthTasks) {
      if (_isDateInTaskRange(date, task)) {
        priorities.add(task.priority);
      }
    }
    return priorities;
  }

  Widget _buildPriorityIndicators(Set<int> priorities) {
    if (priorities.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedPriorities = priorities.toList()..sort();
    final count = sortedPriorities.length;
    const overlap = 1.0;
    const circleSize = 5.0;
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
                color = const Color(0xFF0066FF);
                break;
              default:
                color = Colors.grey;
            }
            
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

  Widget _buildMonthView() {
    final now = DateTime.now();
    final month = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final days = _getDaysInMonth(month);
    
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 75 + 60 + 20,
      ),
            child: Column(
              children: [
          // Заголовок дней недели (в стиле Apple)
          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
                  .map((day) => SizedBox(
                        width: (MediaQuery.of(context).size.width - 32) / 7,
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
          ),
          const SizedBox(height: 4),
          // Календарная сетка (в стиле Apple)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final date = days[index];
                  final isSelected = _isSameDay(date, _selectedDate);
                  final isCurrentMonth = _isCurrentMonth(date, month);
                  final isToday = _isSameDay(date, now);

                  return GestureDetector(
                        onTap: () {
                      if (isCurrentMonth) {
                          setState(() {
                          _selectedDate = date;
                          _listViewType = ListViewType.oneDay;
                        });
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.black
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
            ),
          ),
        ],
      ),
    );
  }

}

