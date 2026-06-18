import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' as dr;
import '../data/database_instance.dart';
import '../data/app_database.dart' as db;
import '../data/user_session.dart';
import '../widgets/main_header.dart';
import '../widgets/swipeable_page_route.dart';
import '../widgets/week_calendar.dart';
import '../widgets/task_list.dart';
import '../widgets/habits_section.dart';
import '../data/repositories/habit_repository.dart';
import '../models/habit.dart';
import '../widgets/events_section.dart';
import '../data/repositories/event_repository.dart';
import '../models/event.dart';
import '../services/notification_service.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/task_create_modal.dart';
import '../widgets/sidebar.dart';
import '../widgets/apple_calendar.dart';
import 'tasks_page.dart';
import 'plan_page.dart';
import 'list_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import '../models/task.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

class CustomTasksPage extends StatefulWidget {
  final int screenId;
  final String screenName;

  const CustomTasksPage({
    super.key,
    required this.screenId,
    required this.screenName,
  });

  @override
  State<CustomTasksPage> createState() => _CustomTasksPageState();
}

class _CustomTasksPageState extends State<CustomTasksPage> {
  bool _isSidebarOpen = false;
  bool _isTaskModalOpen = false;
  late DateTime _selectedDate;
  List<Task> _tasks = [];
  List<Task> _weekTasks = [];
  String? _openMenuTaskId;
  bool _isLoadingTasks = false;
  int _screenUsersCount = 1; // Количество пользователей на экране (по умолчанию 1 - создатель)

  late final HabitRepository _habitRepository;
  List<HabitWithStats> _habits = [];
  Habit? _editingHabit;

  late final EventRepository _eventRepository;
  List<Event> _events = []; // события выбранного дня (для секции)
  List<Event> _allEvents = []; // все события (для меток под днями недели)
  Event? _editingEvent;
  bool _eventViewMode = false; // открыть событие в режиме просмотра

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _habitRepository = HabitRepository(appDatabase);
    _eventRepository = EventRepository(appDatabase);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScreenUsersCount();
      _loadTasksForDate(_selectedDate);
      _loadWeekTasks();
      _loadHabits();
      _loadEvents();
    });
  }

  Future<void> _loadScreenUsersCount() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    try {
      // Подсчитываем количество уникальных пользователей на экране
      final screenUsers = await (appDatabase.select(appDatabase.customScreenUsers)
            ..where((csu) => csu.screenId.equals(widget.screenId)))
          .get();
      
      // Добавляем создателя экрана, если его нет в списке
      final screen = await (appDatabase.select(appDatabase.customTaskScreens)
            ..where((cts) => cts.id.equals(widget.screenId)))
          .getSingleOrNull();
      
      final uniqueUserIds = <int>{};
      for (var screenUser in screenUsers) {
        uniqueUserIds.add(screenUser.userId);
      }
      if (screen != null) {
        uniqueUserIds.add(screen.userId);
      }
      
      if (mounted) {
        setState(() {
          _screenUsersCount = uniqueUserIds.length;
          debugPrint('Screen ${widget.screenId}: users count = $_screenUsersCount (uniqueUserIds: $uniqueUserIds)');
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки количества пользователей: $e');
    }
  }

  Future<void> _loadTasksForDate(DateTime date) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    setState(() {
      _isLoadingTasks = true;
    });

    try {
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final customTasks = await (appDatabase.select(appDatabase.customTasks)
            ..where((t) =>
                t.screenId.equals(widget.screenId) &
                t.isDeleted.equals(false) &
                ((t.date.isBiggerOrEqualValue(dayStart) & t.date.isSmallerThanValue(dayEnd)) |
                    (t.endDate.isNotNull() &
                        t.date.isSmallerOrEqualValue(dayEnd) &
                        t.endDate.isBiggerOrEqualValue(dayStart)))))
          .get();

      // Загружаем имена создателей задач
      final creatorIds = customTasks.where((ct) => ct.creatorId != null).map((ct) => ct.creatorId!).toSet();
      final creators = <int, String>{};
      if (creatorIds.isNotEmpty) {
        final users = await (appDatabase.select(appDatabase.users)
              ..where((u) => u.id.isIn(creatorIds)))
            .get();
        for (var user in users) {
          creators[user.id] = user.name ?? tr('Пользователь');
        }
      }

      setState(() {
        _tasks = customTasks.map((ct) {
          // Показываем имя создателя только если больше одного пользователя на экране
          // ВРЕМЕННО: показываем всегда для теста (убрать || true после проверки)
          final shouldShowCreator = _screenUsersCount > 1 || true;
          final creatorName = (shouldShowCreator && ct.creatorId != null) ? creators[ct.creatorId] : null;
          debugPrint('Task ${ct.id}: creatorId=${ct.creatorId}, creatorName=$creatorName, screenUsersCount=$_screenUsersCount, shouldShow=$shouldShowCreator');
          return Task(
            id: ct.id.toString(),
            title: ct.title,
            description: ct.description,
            date: ct.date,
            endDate: ct.endDate,
            priority: ct.priority,
            isCompleted: ct.isCompleted,
            tags: const [],
            attachedFiles: null,
            creatorName: creatorName,
          );
        }).toList();
        _isLoadingTasks = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки задач: $e');
      setState(() {
        _isLoadingTasks = false;
      });
    }
  }

  Future<void> _loadWeekTasks() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    try {
      final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 7));

      final customTasks = await (appDatabase.select(appDatabase.customTasks)
            ..where((t) =>
                t.screenId.equals(widget.screenId) &
                t.isDeleted.equals(false) &
                ((t.date.isBiggerOrEqualValue(weekStart) & t.date.isSmallerThanValue(weekEnd)) |
                    (t.endDate.isNotNull() &
                        t.date.isSmallerOrEqualValue(weekEnd) &
                        t.endDate.isBiggerOrEqualValue(weekStart)))))
          .get();

      // Загружаем имена создателей задач
      final creatorIds = customTasks.where((ct) => ct.creatorId != null).map((ct) => ct.creatorId!).toSet();
      final creators = <int, String>{};
      if (creatorIds.isNotEmpty) {
        final users = await (appDatabase.select(appDatabase.users)
              ..where((u) => u.id.isIn(creatorIds)))
            .get();
        for (var user in users) {
          creators[user.id] = user.name ?? tr('Пользователь');
        }
      }

      setState(() {
        // Показываем имя создателя только если больше одного пользователя на экране
        // ВРЕМЕННО: показываем всегда для теста (убрать || true после проверки)
        final shouldShowCreator = _screenUsersCount > 1 || true;
        _weekTasks = customTasks.map((ct) {
          final creatorName = (shouldShowCreator && ct.creatorId != null) ? creators[ct.creatorId] : null;
          return Task(
            id: ct.id.toString(),
            title: ct.title,
            description: ct.description,
            date: ct.date,
            endDate: ct.endDate,
            priority: ct.priority,
            isCompleted: ct.isCompleted,
            tags: const [],
            attachedFiles: null,
            creatorName: creatorName,
          );
        }).toList();
      });
    } catch (e) {
      debugPrint('Ошибка загрузки задач недели: $e');
    }
  }

  void _selectDate(DateTime date) {
    // Легкая вибрация при нажатии на день недели
    HapticFeedback.lightImpact();
    setState(() {
      _selectedDate = date;
    });
    _loadTasksForDate(date);
    _loadWeekTasks();
    _loadHabits();
    _loadEvents();
  }

  Future<void> _updateTaskCompletion(String taskId, bool isCompleted) async {
    try {
      final taskIdInt = int.parse(taskId);
      await (appDatabase.update(appDatabase.customTasks)
            ..where((t) => t.id.equals(taskIdInt)))
          .write(
        db.CustomTasksCompanion(
          isCompleted: dr.Value(isCompleted),
          updatedAt: dr.Value(DateTime.now()),
        ),
      );
      _loadTasksForDate(_selectedDate);
      _loadWeekTasks();
    } catch (e) {
      debugPrint('Ошибка обновления задачи: $e');
    }
  }

  /// Удаляет задачу экрана свайпом (soft-delete: isDeleted=true).
  Future<void> _deleteTask(String taskId) async {
    try {
      final taskIdInt = int.parse(taskId);
      await (appDatabase.update(appDatabase.customTasks)
            ..where((t) => t.id.equals(taskIdInt)))
          .write(
        db.CustomTasksCompanion(
          isDeleted: const dr.Value(true),
          updatedAt: dr.Value(DateTime.now()),
        ),
      );
      _loadTasksForDate(_selectedDate);
      _loadWeekTasks();
    } catch (e) {
      debugPrint('Ошибка удаления задачи: $e');
    }
  }

  void _handleMenuToggle(String? taskId, GlobalKey? key) {
    setState(() {
      _openMenuTaskId = taskId;
    });
  }

  // ===== Привычки экрана =====

  // Сегодняшний ли это день (привычку можно отмечать только за сегодня).
  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Future<void> _loadHabits() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final habits = await _habitRepository
        .loadHabitsWithStats(userId, _selectedDate, screenId: widget.screenId);
    if (mounted) {
      setState(() {
        _habits = habits;
      });
    }
  }

  void _openHabitModal(Habit habit) {
    setState(() {
      _editingHabit = habit;
      _isTaskModalOpen = true;
    });
  }

  Future<void> _saveHabit(Habit habit, int? screenId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    try {
      if (habit.id == null) {
        await _habitRepository.addHabit(habit, userId, screenId: screenId);
      } else {
        await _habitRepository.updateHabit(habit);
      }
      _editingHabit = null;
      _loadHabits();
      _closeTaskModal();
    } catch (e) {
      debugPrint('Ошибка сохранения привычки: $e');
    }
  }

  Future<void> _toggleHabit(int habitId) async {
    // Отмечать привычку разрешено только за текущий день.
    if (!_isToday(_selectedDate)) return;
    await _habitRepository.toggleCompletion(habitId, _selectedDate);
    _loadHabits();
  }

  Future<void> _deleteHabit(int habitId) async {
    await _habitRepository.deleteHabit(habitId);
    _loadHabits();
  }

  // ===== События экрана =====

  Future<void> _loadEvents() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final all = await _eventRepository
        .loadAllEvents(userId, screenId: widget.screenId);
    if (mounted) {
      setState(() {
        _allEvents = all;
        _events = all.where((e) => e.occursOn(_selectedDate)).toList();
      });
    }
  }

  void _openEventModal(Event event, {bool viewMode = false}) {
    setState(() {
      _editingEvent = event;
      _eventViewMode = viewMode;
      _isTaskModalOpen = true;
    });
  }

  Future<void> _saveEvent(Event event, int? screenId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    try {
      final int eventId;
      if (event.id == null) {
        eventId =
            await _eventRepository.addEvent(event, userId, screenId: screenId);
      } else {
        await _eventRepository.updateEvent(event);
        eventId = event.id!;
      }
      await NotificationService.instance.scheduleEventReminders(
        id: eventId,
        title: event.title,
        date: event.date,
        repeatYearly: event.repeatYearly,
        notifyDayBefore: event.notifyDayBefore,
        notifyOnDay: event.notifyOnDay,
      );
      _editingEvent = null;
      _loadEvents();
      _closeTaskModal();
    } catch (e) {
      debugPrint('Ошибка сохранения события: $e');
    }
  }

  Future<void> _deleteEvent(int eventId) async {
    await _eventRepository.deleteEvent(eventId);
    await NotificationService.instance.cancelEventReminders(eventId);
    _loadEvents();
  }

  void _openTaskModal() {
    setState(() {
      _isTaskModalOpen = true;
    });
  }

  void _closeTaskModal() {
    setState(() {
      _isTaskModalOpen = false;
      _editingHabit = null;
      _editingEvent = null;
    });
  }

  Future<void> _addTask(Task task, int? screenId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    // Используем переданный screenId или текущий экран по умолчанию
    final targetScreenId = screenId ?? widget.screenId;

    try {
      debugPrint('Creating task with userId=$userId, screenId=$targetScreenId');
      final insertedId = await appDatabase.into(appDatabase.customTasks).insert(
        db.CustomTasksCompanion(
          screenId: dr.Value(targetScreenId),
          creatorId: dr.Value(userId),
          title: dr.Value(task.title),
          description: dr.Value(task.description),
          date: dr.Value(task.date),
          endDate: dr.Value(task.endDate),
          priority: dr.Value(task.priority),
          isCompleted: dr.Value(task.isCompleted),
        ),
      );
      debugPrint('Task created with id=$insertedId, creatorId=$userId');

      _loadScreenUsersCount();
      _loadTasksForDate(_selectedDate);
      _loadWeekTasks();
      _closeTaskModal();
    } catch (e) {
      debugPrint('Ошибка добавления задачи: $e');
    }
  }

  void _toggleSidebar() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }

  void _navigateTo(Widget page) {
    if (page is ChatPage || page is SettingsPage) {
      // Чат/Настройки — push со свайп-маршрутом (свайп назад/вперёд).
      Navigator.of(context).push(
        SwipeablePageRoute(
          builder: (_) => page,
        ),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: page,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top - 10,
            ),
            child: Column(
              children: [
                MainHeader(
                  title: widget.screenName,
                  onMenuTap: _toggleSidebar,
                  onSearchTap: null,
                  onSettingsTap: () {
                    // Действие для кнопки совместной работы
                  },
                  hideSearchAndSettings: false,
                  showBackButton: true,
                  onBack: () {
                    _navigateTo(const TasksPage());
                  },
                  settingsIconPath: 'assets/icon/add-user.png',
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Высота нижней навигации: 65px (высота) + 15px (отступ снизу) + 32px (половина кнопки сверху) = ~112px
                      final bottomNavHeight = 112.0;
                      final bottomPadding = MediaQuery.of(context).padding.bottom;
                      
                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(
                          left: 10,
                          right: 10,
                          bottom: bottomPadding + bottomNavHeight + 30,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 20),
                            _buildSelectedDate(),
                            const SizedBox(height: 20),
                            WeekCalendar(
                              selectedDate: _selectedDate,
                              onDateSelected: _selectDate,
                              tasks: _weekTasks,
                              habits: _habits,
                              events: _allEvents,
                            ),
                            const SizedBox(height: 14),
                            EventsSection(
                              events: _events,
                              onView: (e) => _openEventModal(e, viewMode: true),
                              onEdit: _openEventModal,
                              onDelete: _deleteEvent,
                            ),
                            HabitsSection(
                              habits: _habits,
                              onToggle: _toggleHabit,
                              onEdit: _openHabitModal,
                              onDelete: _deleteHabit,
                              canToggle: _isToday(_selectedDate),
                            ),
                            TaskList(
                              tasks: _tasks,
                              selectedDate: _selectedDate,
                              onTaskToggle: _updateTaskCompletion,
                              onTaskDelete: _deleteTask,
                              openMenuTaskId: _openMenuTaskId,
                              onMenuToggle: _handleMenuToggle,
                              isLoading: _isLoadingTasks,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Sidebar(
            isOpen: _isSidebarOpen,
            onClose: _toggleSidebar,
            onTasksTap: () {
              _navigateTo(const TasksPage());
            },
            onSettingsTap: () {
              _navigateTo(const SettingsPage());
            },
          ),
          BottomNavigation(
            currentIndex: 0,
            onAddTask: _openTaskModal,
            isSidebarOpen: _isSidebarOpen,
            onGptTap: () {
              _navigateTo(ListPage());
            },
            onPlanTap: () {
              _navigateTo(const PlanPage());
            },
            onAiTap: () {
              _navigateTo(const ChatPage());
            },
            onIndexChanged: (index) {
              if (index == 1) {
                _navigateTo(ListPage());
              } else if (index == 2) {
                _navigateTo(const PlanPage());
              } else if (index == 3) {
                _navigateTo(const ChatPage());
              }
            },
          ),
          if (_isTaskModalOpen)
            TaskCreateModal(
              onClose: _closeTaskModal,
              onSave: _addTask,
              initialDate: _selectedDate,
              currentScreenId: widget.screenId, // Текущий экран по умолчанию
              onSaveHabit: _saveHabit,
              initialHabit: _editingHabit,
              onSaveEvent: _saveEvent,
              initialEvent: _editingEvent,
              eventViewMode: _eventViewMode,
            ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    final months = [
      tr('янв.'),
      tr('фев.'),
      tr('мар.'),
      tr('апр.'),
      tr('май'),
      tr('июн.'),
      tr('июл.'),
      tr('авг.'),
      tr('сен.'),
      tr('окт.'),
      tr('ноя.'),
      tr('дек.'),
    ];
    return months[month - 1];
  }

  Future<void> _showCalendarDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Выберите дату'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.of(ctx).textPrimary),
              ),
              const SizedBox(height: 12),
              AppleCalendar(
                initialDate: _selectedDate,
                onDateSelected: (d) {
                  if (Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                  if (mounted) {
                    setState(() {
                      _selectedDate = d;
                    });
                    _loadTasksForDate(_selectedDate);
                    _loadWeekTasks();
                  }
                },
                onClose: () {
                  if (Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                },
                tasks: _weekTasks,
                habits: _habits,
                events: _allEvents,
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectedDate() {
    final colors = AppColors.of(context);
    final day = _selectedDate.day;
    final month = _getMonthName(_selectedDate.month);
    final year = _selectedDate.year;

    return GestureDetector(
      onTap: _showCalendarDialog,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$day',
            style: TextStyle(
              fontSize: 43,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$month $year',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: Color(0xFFD1CBD1),
            ),
          ),
        ],
      ),
    );
  }
}
