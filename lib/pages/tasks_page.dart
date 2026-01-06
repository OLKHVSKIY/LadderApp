import 'package:flutter/material.dart';
import '../models/task.dart';
import '../widgets/greeting_panel.dart';
import '../widgets/main_header.dart';
import '../widgets/week_calendar.dart';
import '../widgets/task_list.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/task_create_modal.dart';
import '../widgets/sidebar.dart';
import '../widgets/ai_menu_modal.dart';
import 'plan_page.dart';
import 'gpt_plan_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import '../data/database_instance.dart';
import '../data/repositories/task_repository.dart';
import '../data/user_session.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';

class TasksPage extends StatefulWidget {
  final bool animateNavIn;

  const TasksPage({super.key, this.animateNavIn = false});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _isGreetingPanelOpen = false;
  bool _isSidebarOpen = false;
  bool _isTaskModalOpen = false;
  bool _isAiMenuOpen = false;
  bool _navHidden = false;
  DateTime _selectedDate = DateTime.now();
  List<Task> _tasks = [];
  int _todayTotal = 0;
  int _todayCompleted = 0;
  String? _openMenuTaskId;
  OverlayEntry? _menuOverlayEntry;
  late final TaskRepository _taskRepository;
  bool _loadedUserName = false;
  bool _userReady = false;
  Task? _editingTask;

  @override
  void initState() {
    super.initState();
    _taskRepository = TaskRepository(appDatabase);
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
        _loadTasksForDate(_selectedDate);
        _loadTodayCounts();
        _loadUserNameIfNeeded();
      });
    });
  }

  void _toggleGreetingPanel() {
    setState(() {
      _isGreetingPanelOpen = !_isGreetingPanelOpen;
    });
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }

  void _openAiMenu() {
    setState(() {
      _isAiMenuOpen = true;
    });
  }

  void _closeAiMenu() {
    setState(() {
      _isAiMenuOpen = false;
    });
  }

  void _openAiChat() {
    _closeAiMenu();
    _navigateTo(const ChatPage());
  }

  void _openAiPlan() {
    _closeAiMenu();
    _navigateTo(const GptPlanPage());
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
    });
  }

  DateTime _normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  void _addTask(Task task) async {
    final userId = UserSession.currentUserId;
    if (userId == null) {
      _showError('Нет авторизованного пользователя');
      return;
    }
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
        );
        await _taskRepository.addTask(copy);
        counter++;
        day = day.add(const Duration(days: 1));
      }

      _loadTasksForDate(_selectedDate);
      _loadTodayCounts();
      _closeTaskModal();
    } catch (e) {
      _showError('Не удалось создать задачу: $e');
    }
  }

  void _updateTaskCompletion(String taskId, bool isCompleted) {
    final intId = int.tryParse(taskId);
    if (intId == null) return;
    _taskRepository.updateCompletion(intId, isCompleted).then((_) {
      _loadTasksForDate(_selectedDate);
      _loadTodayCounts();
    });
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    _loadTasksForDate(date);
  }

  void _loadTasksForDate(DateTime date) async {
    final tasks = await _taskRepository.tasksForDate(date);
    if (mounted) {
      setState(() {
        _tasks = tasks;
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
      _userReady = true;
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
      _userReady = true;
    } else {
      _showError('Нет сохранённого аккаунта, войдите заново');
      _userReady = false;
    }
  }

  void _deleteTask(String taskId) async {
    final intId = int.tryParse(taskId);
    if (intId == null) return;
    try {
      await _taskRepository.deleteTask(intId);
      _loadTasksForDate(_selectedDate);
      _loadTodayCounts();
    } catch (e) {
      _showError('Не удалось удалить: $e');
    }
  }

  void _editTask(Task newTask) async {
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
      _loadTodayCounts();
      _closeTaskModal();
    } catch (e) {
      _showError('Не удалось обновить: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _navigateTo(Widget page) {
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
        position: Offset(position.dx + size.width - 150, position.dy + size.height + 8),
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
          // TODO: Реализовать поделиться
        },
        onDelete: () async {
          _handleMenuToggle(null, null);
          final intId = int.tryParse(task.id);
          if (intId == null) {
            _showError('Некорректный id задачи');
            return;
          }
          await _taskRepository.deleteTask(intId);
          _loadTasksForDate(_selectedDate);
          _loadTodayCounts();
        },
      ),
    );
    
    overlay.insert(_menuOverlayEntry!);
  }

  void _removeMenuOverlay() {
    _menuOverlayEntry?.remove();
    _menuOverlayEntry = null;
  }

  @override
  void dispose() {
    _removeMenuOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Поиск (в разработке)')),
                      );
                    },
                    onSettingsTap: () {
                      _navigateTo(const SettingsPage());
                    },
                    onGreetingToggle: _toggleGreetingPanel,
                  ),
                  // Контент
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
                              // Выбранная дата
                              _buildSelectedDate(),
                              const SizedBox(height: 20),
                              // Календарь недели
                              WeekCalendar(
                                selectedDate: _selectedDate,
                                onDateSelected: _selectDate,
                              ),
                              const SizedBox(height: 14),
                              // Список задач
                              TaskList(
                                tasks: _tasks,
                                selectedDate: _selectedDate,
                                onTaskToggle: _updateTaskCompletion,
                                openMenuTaskId: _openMenuTaskId,
                                onMenuToggle: _handleMenuToggle,
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
            if (_isGreetingPanelOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleGreetingPanel,
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
              onChatTap: () {
                _navigateTo(const ChatPage());
              },
            ),
            // Нижняя навигация
            BottomNavigation(
              currentIndex: 0,
              onAddTask: () => _openTaskModal(),
              isSidebarOpen: _isSidebarOpen || _navHidden,
              onGptTap: _openAiMenu,
              onPlanTap: () {
                _navigateTo(const PlanPage());
              },
              onIndexChanged: (index) {
                if (index == 2) {
                  _navigateTo(const PlanPage());
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
              ),
            // AI меню
            AiMenuModal(
              isOpen: _isAiMenuOpen,
              onClose: _closeAiMenu,
              onChat: _openAiChat,
              onPlan: _openAiPlan,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCalendarDialog() async {
    DateTime selected = _selectedDate;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              const Text(
                'Выберите дату',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                onDateChanged: (d) => selected = d,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _selectedDate = selected;
                  });
                },
                child: const Text('Выбрать'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
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
            style: const TextStyle(
              fontSize: 43,
              fontWeight: FontWeight.w800,
              color: Colors.black,
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

  String _getMonthName(int month) {
    const months = [
      'янв.',
      'фев.',
      'мар.',
      'апр.',
      'май',
      'июн.',
      'июл.',
      'авг.',
      'сен.',
      'окт.',
      'ноя.',
      'дек.',
    ];
    return months[month - 1];
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
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                left: widget.position.dx,
                top: widget.position.dy,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8,
                  child: GestureDetector(
                    onTap: () {}, // Предотвращаем закрытие при клике на меню
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Container(
                          width: 150,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildMenuItem('Редактировать', widget.onEdit),
                              _buildMenuItem('Поделиться', widget.onShare),
                              _buildMenuItem('Удалить', widget.onDelete),
                            ],
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

  Widget _buildMenuItem(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF333333),
            ),
          ),
        ),
      ),
    );
  }
}
