import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../widgets/swipeable_page_route.dart';
import '../widgets/greeting_panel.dart';
import '../widgets/main_header.dart';
import '../widgets/week_calendar.dart';
import '../widgets/spotlight_search.dart';
import '../widgets/task_list.dart';
import '../widgets/bottom_navigation.dart';
import 'dart:ui' as ui;
import '../widgets/task_create_modal.dart';
import '../widgets/sidebar.dart';
import '../widgets/apple_calendar.dart';
import 'plan_page.dart';
import '../services/widget_data_sync.dart';
import '../services/deep_link_handler.dart';
import 'list_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import 'notifications_page.dart';
import 'analytics_page.dart';
import '../services/streak_service.dart';
import '../widgets/streak_celebration.dart';
import '../data/database_instance.dart';
import '../data/app_database.dart' as db;
import '../data/repositories/task_repository.dart';
import '../data/repositories/note_repository.dart';
import 'dart:convert';
import '../data/repositories/habit_repository.dart';
import '../models/habit.dart';
import '../widgets/habits_section.dart';
import '../data/repositories/event_repository.dart';
import '../models/event.dart';
import '../widgets/events_section.dart';
import '../services/notification_service.dart';
import '../data/user_session.dart';
import 'package:drift/drift.dart' as dr;
import '../widgets/custom_snackbar.dart';
import '../widgets/delegate_task_modal.dart';
import '../widgets/delegated_task_accept_modal.dart';
import '../data/repositories/delegated_task_repository.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

class TasksPage extends StatefulWidget {
  final bool animateNavIn;
  final Task? initialTaskToOpen;

  const TasksPage({super.key, this.animateNavIn = false, this.initialTaskToOpen});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _isGreetingPanelOpen = false;
  bool _isSidebarOpen = false;
  bool _isTaskModalOpen = false;
  bool _navHidden = false;
  late DateTime _selectedDate;
  List<Task> _tasks = [];
  List<Task> _weekTasks = []; // Задачи для всей недели
  int _todayTotal = 0;
  int _todayCompleted = 0;
  String? _openMenuTaskId;
  OverlayEntry? _menuOverlayEntry;
  OverlayEntry? _streakCelebrationEntry;
  late final TaskRepository _taskRepository;
  late final DelegatedTaskRepository _delegatedTaskRepository;
  late final HabitRepository _habitRepository;
  List<HabitWithStats> _habits = [];
  late final EventRepository _eventRepository;
  List<Event> _events = []; // события выбранного дня (для секции)
  List<Event> _allEvents = []; // все события (для меток под днями недели)
  bool _loadedUserName = false;
  Task? _editingTask;
  Habit? _editingHabit;
  Event? _editingEvent;
  bool _eventViewMode = false; // открыть событие в режиме просмотра
  double _headerDragDistance = 0.0;
  List<DelegatedTaskInfo> _pendingDelegatedTasks = [];
  bool _isLoadingTasks = false;

  @override
  void initState() {
    super.initState();
    // Устанавливаем дату сразу, чтобы не было видимого перехода
    _selectedDate = widget.initialTaskToOpen?.date ?? DateTime.now();
    _taskRepository = TaskRepository(appDatabase);
    _delegatedTaskRepository = DelegatedTaskRepository(appDatabase);
    _habitRepository = HabitRepository(appDatabase);
    _eventRepository = EventRepository(appDatabase);

    // Настраиваем обработчик deep link для открытия шторки создания задачи
    DeepLinkHandler.onOpenAddTaskPanel = () {
      if (mounted) {
        _openTaskModal();
        _toggleGreetingPanel();
      }
    };
    
    if (widget.animateNavIn) {
      _navHidden = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _navHidden = false;
        });
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureUserSession().then((_) {
        setState(() {
          _isLoadingTasks = true;
        });
        _loadTasksForDate(_selectedDate);
        _loadWeekTasks();
        _loadTodayCounts();
        _loadHabits();
        _loadEvents();
        _loadUserNameIfNeeded();
        _checkDelegatedTasks();
        // Открыта из поиска — просто открываем страницу на дне задачи
        // (день уже выставлен в _selectedDate выше). Редактор НЕ открываем.
      });
    });
  }

  void _toggleGreetingPanel() {
    setState(() {
      _isGreetingPanelOpen = !_isGreetingPanelOpen;
    });
  }

  void _handleHeaderPanUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final totalHeight = screenHeight * 0.45; // 45% экрана
    final threshold = totalHeight * 0.2; // 20% от высоты панели
    
    if (_isGreetingPanelOpen) {
      // При открытой панели: разрешаем только перетаскивание вниз (закрытие)
      // delta.dy положительный при перетаскивании вниз
      if (details.delta.dy > 0) {
        _headerDragDistance += details.delta.dy;
        // Если перетащили больше порога, закрываем
        if (_headerDragDistance > threshold) {
          _headerDragDistance = 0.0;
          _toggleGreetingPanel();
        }
      }
    } else {
      // При закрытой панели: разрешаем только перетаскивание вниз (открытие)
      // delta.dy положительный при перетаскивании вниз
      if (details.delta.dy > 0) {
        _headerDragDistance += details.delta.dy;
        // Если перетащили больше порога, открываем
        if (_headerDragDistance > threshold) {
          _headerDragDistance = 0.0;
          _toggleGreetingPanel();
        }
      }
    }
  }

  void _handleHeaderPanEnd(DragEndDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final totalHeight = screenHeight * 0.45;
    final threshold = totalHeight * 0.15; // 15% от высоты панели
    
    // Проверяем скорость перетаскивания
    final velocity = details.velocity.pixelsPerSecond.dy;
    
    if (_isGreetingPanelOpen) {
      // Если перетащили достаточно или скорость высокая вниз - закрываем
      if (_headerDragDistance > threshold || velocity > 300) {
        if (!_isGreetingPanelOpen) return; // Уже закрыта
        _toggleGreetingPanel();
      }
    } else {
      // Если перетащили достаточно или скорость высокая вниз - открываем
      if (_headerDragDistance > threshold || velocity > 200) {
        if (_isGreetingPanelOpen) return; // Уже открыта
        _toggleGreetingPanel();
      }
    }
    
    // Сбрасываем расстояние
    _headerDragDistance = 0.0;
  }

  void _toggleSidebar() {
    // Скрываем клавиатуру при открытии/закрытии сайдбара
    FocusScope.of(context).unfocus();
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }


  void _openTaskModal({Task? task}) {
    setState(() {
      _editingTask = task;
      _isTaskModalOpen = true;
    });
  }

  void _closeTaskModal() {
    setState(() {
      _isTaskModalOpen = false;
      _editingTask = null;
      _editingHabit = null;
      _editingEvent = null;
    });
  }

  // ===== Привычки =====

  void _loadHabits() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final habits =
        await _habitRepository.loadHabitsWithStats(userId, _selectedDate);
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

  void _saveHabit(Habit habit, int? screenId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) {
      _showError(tr('Нет авторизованного пользователя'));
      return;
    }
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
      _showError(tr('Не удалось сохранить привычку: {0}', [e]));
    }
  }

  // Сегодняшний ли это день (привычку можно отмечать только за сегодня).
  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  void _toggleHabit(int habitId) async {
    // Отмечать привычку разрешено только за текущий день.
    if (!_isToday(_selectedDate)) return;
    await _habitRepository.toggleCompletion(habitId, _selectedDate);
    _loadHabits();
  }

  void _deleteHabit(int habitId) async {
    await _habitRepository.deleteHabit(habitId);
    _loadHabits();
  }

  // ===== События =====

  void _loadEvents() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final all = await _eventRepository.loadAllEvents(userId);
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

  void _saveEvent(Event event, int? screenId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) {
      _showError(tr('Нет авторизованного пользователя'));
      return;
    }
    try {
      final int eventId;
      if (event.id == null) {
        eventId = await _eventRepository.addEvent(event, userId,
            screenId: screenId);
      } else {
        await _eventRepository.updateEvent(event);
        eventId = event.id!;
      }
      // Планируем/перепланируем уведомления о событии.
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
      _showError(tr('Не удалось сохранить событие: {0}', [e]));
    }
  }

  void _deleteEvent(int eventId) async {
    await _eventRepository.deleteEvent(eventId);
    await NotificationService.instance.cancelEventReminders(eventId);
    _loadEvents();
  }

  DateTime _normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  void _addTask(Task task, int? screenId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) {
      _showError(tr('Нет авторизованного пользователя'));
      return;
    }

    // Если выбран кастомный экран, создаем задачу в нем
    if (screenId != null) {
      try {
        final start = _normalizeDate(task.date);
        final end = task.endDate != null ? _normalizeDate(task.endDate!) : start;
        final endDate = end.isBefore(start) ? start : end;

        var day = start;
        while (!day.isAfter(endDate)) {
          await appDatabase.into(appDatabase.customTasks).insert(
            db.CustomTasksCompanion(
              screenId: dr.Value(screenId),
              creatorId: dr.Value(userId),
              title: dr.Value(task.title),
              description: dr.Value(task.description),
              date: dr.Value(day),
              endDate: dr.Value(task.endDate),
              priority: dr.Value(task.priority),
              isCompleted: dr.Value(false),
            ),
          );
          day = day.add(const Duration(days: 1));
        }

        _loadTasksForDate(_selectedDate);
        _loadWeekTasks();
        _loadTodayCounts();
        _closeTaskModal();
      } catch (e) {
        _showError(tr('Не удалось создать задачу: {0}', [e]));
      }
      return;
    }

    // Иначе создаем в "Мои задачи"
    final start = _normalizeDate(task.date);
    final end = task.endDate != null ? _normalizeDate(task.endDate!) : start;
    final endDate = end.isBefore(start) ? start : end;

    var day = start;
    var counter = 0;
    try {
      while (!day.isAfter(endDate)) {
        final copy = Task(
          id: '${DateTime.now().microsecondsSinceEpoch}-$counter',
          title: task.title,
          description: task.description,
          priority: task.priority,
          tags: task.tags,
          date: day,
          endDate: null,
          isCompleted: false,
          attachedFiles: task.attachedFiles,
          subtasks: task.subtasks,
        );
        await _taskRepository.addTask(copy);
        counter++;
        day = day.add(const Duration(days: 1));
      }

      _loadTasksForDate(_selectedDate);
      _loadWeekTasks();
      _loadTodayCounts();
      _closeTaskModal();
    } catch (e) {
      _showError(tr('Не удалось создать задачу: {0}', [e]));
    }
  }

  void _updateTaskCompletion(String taskId, bool isCompleted) {
    final intId = int.tryParse(taskId);
    if (intId == null) return;
    // Вибрация при отметке задачи
    HapticFeedback.lightImpact();
    _taskRepository.updateCompletion(intId, isCompleted).then((_) async {
      // Отмечаем выполнение для «серии» (стрик) — только при завершении задачи.
      if (isCompleted) {
        final before = await StreakService.getInfo();
        final after = await StreakService.recordCompletion();
        // Показываем празднование только при первой задаче за сегодня
        // (когда серия реально начинается/продлевается).
        if (!before.completedToday && mounted) {
          _showStreakCelebration(before.current, after.current);
        }
      }
      _loadTasksForDate(_selectedDate);
      _loadWeekTasks();
      _loadTodayCounts();
    });
  }

  // Переключение пункта чек-листа в карточке: оптимистично обновляем список
  // и сохраняем в БД.
  void _updateTaskSubtasks(String taskId, List<SubTask> updated) {
    final intId = int.tryParse(taskId);
    if (intId == null) return;
    final i = _tasks.indexWhere((t) => t.id == taskId);
    final wasCompleted = i != -1 ? _tasks[i].isCompleted : false;
    setState(() {
      if (i != -1) {
        _tasks[i] = _tasks[i].copyWith(subtasks: updated);
      }
    });
    _taskRepository.updateSubtasks(intId, updated);
    // Двусторонняя авто-связь чек-листа и статуса задачи:
    // все пункты выполнены → задача выполнена; сняли пункт → задача открыта.
    if (updated.isNotEmpty) {
      final allDone = updated.every((s) => s.isCompleted);
      if (allDone && !wasCompleted) {
        _updateTaskCompletion(taskId, true);
      } else if (!allDone && wasCompleted) {
        _updateTaskCompletion(taskId, false);
      }
    }
  }

  // Баннер-празднование серии сверху экрана (огонь + перемотка счётчика).
  void _showStreakCelebration(int from, int to) {
    _streakCelebrationEntry?.remove();
    final overlay = Overlay.of(context);
    _streakCelebrationEntry = OverlayEntry(
      builder: (_) => StreakCelebration(
        fromValue: from,
        toValue: to,
        onDismiss: () {
          _streakCelebrationEntry?.remove();
          _streakCelebrationEntry = null;
        },
      ),
    );
    overlay.insert(_streakCelebrationEntry!);
  }

  void _selectDate(DateTime date) {
    // Легкая вибрация при нажатии на день недели
    HapticFeedback.lightImpact();
    setState(() {
      _selectedDate = date;
      _isLoadingTasks = true;
    });
    _loadTasksForDate(date);
    _loadWeekTasks();
    _loadHabits();
    _loadEvents();
    _checkDelegatedTasks();
  }

  void _loadTasksForDate(DateTime date) async {
    final tasks = await _taskRepository.tasksForDate(date);
    if (mounted) {
      setState(() {
        _tasks = tasks;
        _isLoadingTasks = false;
      });
    }
  }

  void _loadWeekTasks() async {
    final startOfWeek = _selectedDate.subtract(
      Duration(days: _selectedDate.weekday - 1),
    );
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final tasks = await _taskRepository.tasksForDateRange(startOfWeek, endOfWeek);
    if (mounted) {
      setState(() {
        _weekTasks = tasks;
      });
    }
  }

  void _loadTodayCounts() async {
    final todayTasks = await _taskRepository.tasksForDate(DateTime.now());
    if (!mounted) return;
    setState(() {
      _todayTotal = todayTasks.length;
      _todayCompleted = todayTasks.where((t) => t.isCompleted).length;
    });
    // Синхронизируем данные для виджета
    WidgetDataSync.syncTodayTasks();
  }

  void _loadUserNameIfNeeded() async {
    if (_loadedUserName) return;
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final user = await (appDatabase.select(appDatabase.users)
          ..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
    if (user != null) {
      UserSession.currentName = user.name;
    }
    _loadedUserName = true;
    if (mounted) setState(() {});
  }

  Future<void> _ensureUserSession() async {
    if (UserSession.currentUserId != null) {
      return;
    }
    final user = await (appDatabase.select(appDatabase.users)
          ..orderBy([(u) => OrderingTerm.asc(u.id)]))
        .getSingleOrNull();
    if (user != null) {
      UserSession.setUser(
        id: user.id,
        email: user.email,
        name: user.name,
      );
    } else {
      _showError(tr('Нет сохранённого аккаунта, войдите заново'));
    }
  }

  void _editTask(Task newTask, int? screenId) async {
    // screenId игнорируется для TasksPage, так как это "Мои задачи"
    if (_editingTask == null) return;
    final intId = int.tryParse(_editingTask!.id);
    if (intId == null) return;
    try {
      // сохраняем текущий статус выполнения
      await _taskRepository.updateTask(
        intId,
        newTask,
        isCompleted: _editingTask!.isCompleted,
      );
      _editingTask = null;
      _loadTasksForDate(_selectedDate);
      _loadWeekTasks();
      _loadTodayCounts();
      _closeTaskModal();
    } catch (e) {
      _showError(tr('Не удалось обновить: {0}', [e]));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    CustomSnackBar.show(context, message);
  }

  void _navigateTo(Widget page) {
    if (page is ChatPage) {
      // Чат — push с CupertinoPageRoute (нативный iOS swipe back).
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

  void _handleMenuToggle(String? taskId, GlobalKey? menuButtonKey) {
    setState(() {
      if (_openMenuTaskId == taskId) {
        // Закрываем меню, если кликнули на то же самое
        _openMenuTaskId = null;
        _removeMenuOverlay();
      } else {
        // Открываем новое меню, закрывая предыдущее
        _openMenuTaskId = taskId;
        if (taskId != null && menuButtonKey != null) {
          _showMenuOverlay(taskId, menuButtonKey);
        } else {
          _removeMenuOverlay();
        }
      }
    });
  }

  void _showMenuOverlay(String taskId, GlobalKey menuButtonKey) {
    _removeMenuOverlay(); // Удаляем предыдущее меню, если есть
    
    final task = _tasks.firstWhere((t) => t.id == taskId);
    final overlay = Overlay.of(context);
    
    // Получаем позицию троеточия
    final RenderBox? renderBox = menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final Offset? position = renderBox?.localToGlobal(Offset.zero);
    final Size? size = renderBox?.size;
    
    if (position == null || size == null) {
      return; // Не можем получить позицию, не показываем меню
    }
    
    _menuOverlayEntry = OverlayEntry(
      builder: (context) => _TaskMenuOverlay(
        position: Offset(position.dx + size.width - 200, position.dy + size.height + 8),
        task: task,
        onClose: () => _handleMenuToggle(null, null),
        onEdit: () {
          _handleMenuToggle(null, null);
          _editingTask = task;
          setState(() {
            _isTaskModalOpen = true;
          });
        },
        onShare: () {
          _handleMenuToggle(null, null);
          _showDelegateModal(task);
        },
        onDelete: () async {
          _handleMenuToggle(null, null);
          // Вибрация при удалении задачи
          HapticFeedback.heavyImpact();
          await _deleteTaskById(task.id);
        },
      ),
    );

    overlay.insert(_menuOverlayEntry!);
  }

  /// Удаляет задачу по строковому id и обновляет списки.
  Future<void> _deleteTaskById(String id) async {
    final intId = int.tryParse(id);
    if (intId == null) {
      _showError(tr('Некорректный id задачи'));
      return;
    }
    // Запоминаем задачу до удаления, чтобы убрать связанный блок на таймлайне.
    Task? deleted;
    for (final t in _tasks) {
      if (t.id == id) {
        deleted = t;
        break;
      }
    }
    await _taskRepository.deleteTask(intId);
    if (deleted != null) {
      await _deleteLinkedTimelineNotes(deleted);
    }
    _loadTasksForDate(_selectedDate);
    _loadWeekTasks();
    _loadTodayCounts();
  }

  /// Удаляет на таймлайне «Списка» блок(и), созданный вместе с этой задачей.
  /// Связь по id ненадёжна (у задачи и заметки разные id), поэтому ищем по
  /// названию и совпадению дня начала.
  Future<void> _deleteLinkedTimelineNotes(Task task) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    try {
      final repo = NoteRepository(appDatabase);
      final notes = await repo.loadNotes(userId);
      for (final note in notes) {
        if (note.id == null) continue;
        try {
          final data = jsonDecode(note.content) as Map<String, dynamic>;
          if (data['type'] != 'timeline') continue;
          if (data['linkedElementType'] != 'task') continue;
          if (note.title != task.title) continue;
          final start = DateTime.parse(data['startTime'] as String);
          if (start.year == task.date.year &&
              start.month == task.date.month &&
              start.day == task.date.day) {
            await repo.deleteNote(note.id!);
          }
        } catch (_) {
          // Некорректная заметка — пропускаем.
        }
      }
    } catch (_) {
      // Ошибки чистки таймлайна не должны блокировать удаление задачи.
    }
  }

  void _removeMenuOverlay() {
    _menuOverlayEntry?.remove();
    _menuOverlayEntry = null;
  }

  void _showDelegateModal(Task task) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.4), // Затемнение сразу видимо
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => DelegateTaskModal(
        task: task,
        onDelegate: (email, deleteFromMe) async {
          try {
            final intId = int.tryParse(task.id);
            if (intId == null) {
              _showError(tr('Некорректный id задачи'));
              return;
            }
            await _delegatedTaskRepository.delegateTask(
              taskId: intId,
              toUserEmail: email,
              deleteFromMe: deleteFromMe,
            );
            if (deleteFromMe) {
              _loadTasksForDate(_selectedDate);
              _loadWeekTasks();
              _loadTodayCounts();
            }
            if (context.mounted) {
              CustomSnackBar.show(context, tr('Задача делегирована пользователю {0}', [email]));
            }
          } catch (e) {
            _showError(tr('Ошибка при делегировании: {0}', [e]));
          }
        },
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        // Затемнение появляется сразу, шторка анимируется снизу
        return FadeTransition(
          opacity: AlwaysStoppedAnimation(1.0), // Затемнение сразу видимо
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

  Future<void> _checkDelegatedTasks() async {
    try {
      final pendingTasks = await _delegatedTaskRepository.getPendingDelegatedTasks();
      if (pendingTasks.isNotEmpty && mounted) {
        setState(() {
          _pendingDelegatedTasks = pendingTasks;
        });
        // Показываем модальное окно
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pendingDelegatedTasks.isNotEmpty) {
            _showAcceptModal();
          }
        });
      }
    } catch (e) {
      debugPrint('Ошибка при проверке делегированных задач: $e');
    }
  }

  void _showAcceptModal() {
    if (_pendingDelegatedTasks.isEmpty) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, // Отключаем закрытие по клику вне шторки
      enableDrag: false, // Отключаем перетаскивание
      builder: (context) => DelegatedTaskAcceptModal(
        tasks: _pendingDelegatedTasks,
        onAccept: (taskId) {
          _acceptDelegatedTask(taskId);
        },
        onDecline: (taskId) {
          _declineDelegatedTask(taskId);
        },
        onClose: () {
          Navigator.of(context).pop();
          setState(() {
            _pendingDelegatedTasks = [];
          });
        },
      ),
    );
  }

  Future<void> _acceptDelegatedTask(int taskId) async {
    final taskInfo = _pendingDelegatedTasks.firstWhere((t) => t.id == taskId);
    final taskDate = taskInfo.taskDate;
    
    try {
      await _delegatedTaskRepository.acceptDelegatedTask(taskId);
      setState(() {
        _pendingDelegatedTasks.removeWhere((t) => t.id == taskId);
      });
      // Переключаемся на дату задачи
      setState(() {
        _selectedDate = taskDate;
      });
      _loadTasksForDate(taskDate);
      _loadWeekTasks();
      _loadTodayCounts();
      if (!mounted) return;
      CustomSnackBar.show(context, tr('Задача принята'));
      // Если задач больше нет, закрываем модальное окно
      if (_pendingDelegatedTasks.isEmpty) {
        Navigator.of(context).pop();
      } else {
        // Обновляем модальное окно, убрав принятую задачу
        Navigator.of(context).pop();
        _showAcceptModal();
      }
    } catch (e) {
      _showError(tr('Ошибка при принятии задачи: {0}', [e]));
    }
  }

  Future<void> _declineDelegatedTask(int taskId) async {
    try {
      await _delegatedTaskRepository.declineDelegatedTask(taskId);
      setState(() {
        _pendingDelegatedTasks.removeWhere((t) => t.id == taskId);
      });
      if (!mounted) return;
      CustomSnackBar.show(context, tr('Задача отклонена'));
      // Если задач больше нет, закрываем модальное окно
      if (_pendingDelegatedTasks.isEmpty) {
        Navigator.of(context).pop();
      } else {
        // Обновляем модальное окно, убрав отклоненную задачу
        Navigator.of(context).pop();
        _showAcceptModal();
      }
    } catch (e) {
      _showError(tr('Ошибка при отклонении задачи: {0}', [e]));
    }
  }

  @override
  void dispose() {
    _removeMenuOverlay();
    _streakCelebrationEntry?.remove();
    _streakCelebrationEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      resizeToAvoidBottomInset: false,
      body: ClipRect(
        clipBehavior: Clip.hardEdge,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Основной контент с отступом для статус бара
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top - 10,
              ),
              child: Column(
                children: [
                  // Хедер
                  MainHeader(
                    onMenuTap: _toggleSidebar,
                    onSearchTap: () {
                      showDialog(
                        context: context,
                        barrierColor: Colors.black.withValues(alpha: 0.9),
                        builder: (context) => SpotlightSearch(
                          onTaskCreated: () {
                            // Обновляем задачи после создания
                            _loadTasksForDate(_selectedDate);
                            _loadWeekTasks();
                            _loadTodayCounts();
                          },
                        ),
                      );
                    },
                    onSettingsTap: () {
                      // Колокольчик в хедере открывает уведомления.
                      Navigator.of(context).push(
                        SwipeablePageRoute(
                            builder: (_) => const NotificationsPage()),
                      );
                    },
                    onGreetingToggle: _toggleGreetingPanel,
                    onGreetingPanUpdate: _handleHeaderPanUpdate,
                    onGreetingPanEnd: _handleHeaderPanEnd,
                    isGreetingPanelOpen: _isGreetingPanelOpen,
                    hideGreetingHandle: _isTaskModalOpen,
                  ),
                  // Контент
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Высота нижней навигации: 65px (высота) + 15px (отступ снизу) + 32px (половина кнопки сверху) = ~112px
                        final bottomNavHeight = 112.0;
                        final bottomPadding = MediaQuery.of(context).padding.bottom;
                        
                        return SingleChildScrollView(
                          // Скроллим только когда контент не помещается на экран:
                          // если всё влезает — скролла (и баунса) нет.
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.only(
                            left: 10,
                            right: 10,
                            bottom: bottomPadding + bottomNavHeight + 30,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 20),
                              // Выбранная дата
                              _buildSelectedDate(),
                              const SizedBox(height: 20),
                              // Календарь недели
                              WeekCalendar(
                                selectedDate: _selectedDate,
                                onDateSelected: _selectDate,
                                tasks: _weekTasks,
                                habits: _habits,
                                events: _allEvents,
                              ),
                              const SizedBox(height: 14),
                              // Секция событий (день рождения и т.п. — не
                              // закрываются галочкой, просто отображаются)
                              EventsSection(
                                events: _events,
                                onView: (e) =>
                                    _openEventModal(e, viewMode: true),
                                onEdit: _openEventModal,
                                onDelete: _deleteEvent,
                              ),
                              // Секция привычек (показывается, если на выбранный
                              // день есть запланированные привычки)
                              HabitsSection(
                                habits: _habits,
                                onToggle: _toggleHabit,
                                onEdit: _openHabitModal,
                                onDelete: _deleteHabit,
                                // Отмечать привычку можно только за сегодня.
                                canToggle: _isToday(_selectedDate),
                              ),
                              // Список задач
                              TaskList(
                                tasks: _tasks,
                                selectedDate: _selectedDate,
                                onTaskToggle: _updateTaskCompletion,
                                openMenuTaskId: _openMenuTaskId,
                                onMenuToggle: _handleMenuToggle,
                                onTaskDelete: _deleteTaskById,
                                onSubtasksChanged: _updateTaskSubtasks,
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
            // Обработчик нажатия вне шторки (закрывает шторку при нажатии на фон)
            // Исключаем область хедера из обработки нажатий
            if (_isGreetingPanelOpen)
              Positioned(
                top: MediaQuery.of(context).padding.top - 10 + 60, // Ниже хедера
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: () {
                    // При нажатии вне шторки закрываем её и скрываем крестики
                    _toggleGreetingPanel();
                  },
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
            // Невидимая область для открытия шторки свайпом вниз (когда закрыта)
            // Используем GestureDetector только в центральной области, чтобы не блокировать кнопки
            if (!_isGreetingPanelOpen)
              Positioned(
                top: MediaQuery.of(context).padding.top - 10, // От самого верха
                left: 80, // Исключаем левую область (кнопка меню)
                right: 80, // Исключаем правую область (кнопки поиска и настроек)
                // Только зона хедера: если зона больше, её pan-распознаватель
                // перехватывает тапы по дате и календарь не открывается.
                height: 70,
                child: GestureDetector(
                  onPanStart: (details) {
                    _headerDragDistance = 0.0;
                  },
                  onPanUpdate: (details) {
                    // Обрабатываем только движение вниз
                    if (details.delta.dy > 0) {
                      _headerDragDistance += details.delta.dy;
                    }
                  },
                  onPanEnd: (details) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    final totalHeight = screenHeight * 0.4;
                    final threshold = totalHeight * 0.2;
                    
                    // Если перетащили достаточно или скорость высокая вниз - открываем
                    if (_headerDragDistance > threshold || details.velocity.pixelsPerSecond.dy > 200) {
                      if (!_isGreetingPanelOpen) {
                        _toggleGreetingPanel();
                      }
                    }
                    _headerDragDistance = 0.0;
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
            // Шторка с приветствием
            GreetingPanel(
              isOpen: _isGreetingPanelOpen,
              onToggle: _toggleGreetingPanel,
              totalTasksToday: _todayTotal,
              completedTasksToday: _todayCompleted,
              userName: UserSession.currentName,
            ),
            // Сайдбар
            Sidebar(
              isOpen: _isSidebarOpen,
              onClose: _toggleSidebar,
              onTasksTap: () {
                // Уже на странице задач, просто закрываем сайдбар
              },
              onAnalyticsTap: () {
                Navigator.of(context).push(
                  SwipeablePageRoute(
                    builder: (_) => const AnalyticsPage(),
                  ),
                );
              },
              onSettingsTap: () {
                Navigator.of(context).push(
                  SwipeablePageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            // Нижняя навигация
            BottomNavigation(
              currentIndex: 0,
              onAddTask: () => _openTaskModal(),
              isSidebarOpen: _isSidebarOpen || _navHidden,
              onGptTap: () {
                _navigateTo(const ListPage());
              },
              onPlanTap: () {
                _navigateTo(const PlanPage());
              },
              onAiTap: () {
                _navigateTo(const ChatPage());
              },
              onIndexChanged: (index) {
                if (index == 1) {
                  _navigateTo(const ListPage());
                } else if (index == 2) {
                  _navigateTo(const PlanPage());
                } else if (index == 3) {
                  _navigateTo(const ChatPage());
                }
              },
            ),
            // Модальное окно создания/редактирования задачи
            if (_isTaskModalOpen)
              TaskCreateModal(
                onClose: _closeTaskModal,
                onSave: _editingTask == null ? _addTask : _editTask,
                initialTask: _editingTask,
                isEdit: _editingTask != null,
                initialDate: _editingTask == null ? _selectedDate : null,
                currentScreenId: null, // "Мои задачи"
                onSaveHabit: _saveHabit,
                initialHabit: _editingHabit,
                onSaveEvent: _saveEvent,
                initialEvent: _editingEvent,
                eventViewMode: _eventViewMode,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCalendarDialog() async {
    // Грузим все задачи пользователя, чтобы точки в календаре показывались
    // на каждый день (любой месяц), а не только за текущую неделю.
    final allTasks = await _taskRepository.searchAllTasks();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
      // Та же мягкая iOS-плавность, что у шторки создания задачи.
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 460),
        reverseDuration: const Duration(milliseconds: 420),
        curve: const Cubic(0.32, 0.72, 0.0, 1.0),
        reverseCurve: Curves.easeInOutCubic,
      ),
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.of(ctx).textPrimary,
                ),
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
                      _loadTasksForDate(_selectedDate);
                      _loadWeekTasks();
                    });
                  }
                },
                onClose: () {
                  if (Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                },
                tasks: allTasks,
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

  Widget _buildSelectedDate() {
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
              color: AppColors.of(context).textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$month $year',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: AppColors.of(context).textTertiary,
            ),
          ),
        ],
      ),
    );
  }

}

// Виджет меню в Overlay
class _TaskMenuOverlay extends StatefulWidget {
  final Offset position;
  final Task task;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _TaskMenuOverlay({
    required this.position,
    required this.task,
    required this.onClose,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  @override
  State<_TaskMenuOverlay> createState() => _TaskMenuOverlayState();
}

class _TaskMenuOverlayState extends State<_TaskMenuOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
      vsync: this,
    );
    // Плавное появление: лёгкий рост от угла-якоря + проявление.
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        reverseCurve: Curves.easeIn,
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _animationController.forward();
  }

  // Плавно сворачиваем меню обратно, затем выполняем действие.
  void _close(VoidCallback then) {
    if (_closing) return;
    _closing = true;
    _animationController.reverse().whenComplete(then);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => _close(widget.onClose),
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                left: widget.position.dx,
                top: widget.position.dy,
                child: Material(
                  color: Colors.transparent,
                  // В светлой теме добавляем тень, чтобы меню отделялось от
                  // белого фона; в тёмной тень не нужна.
                  elevation: colors.isDark ? 0 : 10,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(18),
                  child: GestureDetector(
                    onTap: () {}, // Предотвращаем закрытие при клике на меню
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        alignment: Alignment.topRight,
                        // Стекло на BackdropFilter (стиль iOS 26): рисуется
                        // корректно с первого кадра, без чёрной вспышки.
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.isDark
                                    ? colors.surface.withValues(alpha: 0.72)
                                    : const Color(0xFFF6F7F8)
                                        .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: colors.isDark
                                      ? colors.border.withValues(alpha: 0.6)
                                      : const Color(0xFFD2D4D9),
                                  width: colors.isDark ? 0.5 : 1,
                                ),
                              ),
                              child: SizedBox(
                                width: 200,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildMenuItem(
                                      CupertinoIcons.pencil,
                                      tr('Редактировать'),
                                      () => _close(widget.onEdit),
                                    ),
                                    _buildMenuDivider(),
                                    _buildMenuItem(
                                      CupertinoIcons.share,
                                      tr('Поделиться'),
                                      () => _close(widget.onShare),
                                    ),
                                    _buildMenuDivider(),
                                    _buildMenuItem(
                                      CupertinoIcons.delete,
                                      tr('Удалить'),
                                      () => _close(widget.onDelete),
                                      color: const Color(0xFFFF3B30),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuDivider() {
    final colors = AppColors.of(context);
    return Container(
      height: 0.5,
      color: colors.isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.07),
    );
  }

  Widget _buildMenuItem(IconData icon, String text, VoidCallback onTap,
      {Color? color}) {
    final itemColor = color ?? AppColors.of(context).textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 18, color: itemColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: itemColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
