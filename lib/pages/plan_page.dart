import 'dart:async';

import 'package:flutter/material.dart';

import 'package:uuid/uuid.dart';

import '../widgets/main_header.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/sidebar.dart';
import '../widgets/ai_menu_modal.dart';
import 'tasks_page.dart';
import 'gpt_plan_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import '../data/repositories/plan_repository.dart';
import '../data/user_session.dart';
import '../data/database_instance.dart';
import '../models/goal_model.dart';

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  bool _isSidebarOpen = false;
  bool _isAiMenuOpen = false;
  final _goalInputController = TextEditingController();
  final _uuid = const Uuid();
  late final PlanRepository _planRepo;
  final ScrollController _scrollController = ScrollController();

  final List<GoalModel> _goals = [];
  String? _activeGoalId;

  GoalModel? get _activeGoal {
    if (_goals.isEmpty) return null;
    return _goals.firstWhere(
      (g) => g.id == _activeGoalId,
      orElse: () => _goals.first,
    );
  }

  Future<void> _loadFromDb() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final items = await _planRepo.loadGoals(userId);
    setState(() {
      _goals
        ..clear()
        ..addAll(items);
      _activeGoalId = null;
    });
  }

  @override
  void dispose() {
    _goalInputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _planRepo = PlanRepository(appDatabase);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromDb());
  }

  void _toggleSidebar() => setState(() => _isSidebarOpen = !_isSidebarOpen);
  void _openAiMenu() => setState(() => _isAiMenuOpen = true);
  void _closeAiMenu() => setState(() => _isAiMenuOpen = false);

  void _openAiChat() {
    _closeAiMenu();
    _navigateTo(const ChatPage(), slideFromRight: true);
  }

  void _openAiPlan() {
    _closeAiMenu();
    _navigateTo(const GptPlanPage(), slideFromRight: true);
  }

  void _navigateTo(Widget page, {bool slideFromRight = false}) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, animation, __) {
          final curve = Curves.easeInOut;
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: curve),
            child: page,
          );
        },
      ),
    );
  }

  // --------- Создание / управление планами ---------
  void _createGoal() {
    final title = _goalInputController.text.trim();
    if (title.isEmpty) return;
    final userId = UserSession.currentUserId;
    if (userId == null) {
      _showMessage('Нет авторизованного пользователя');
      return;
    }
    final goal = GoalModel(
      id: _uuid.v4(),
      title: title,
      isSaved: false,
      isActive: true,
      dates: [],
      createdAt: DateTime.now(),
      dbId: null,
    );
    setState(() {
      _goals.add(goal);
      _activeGoalId = goal.id;
      _goalInputController.clear();
    });
  }

  Future<void> _saveActiveGoal() async {
    final goal = _activeGoal;
    if (goal == null) return;
    final userId = UserSession.currentUserId;
    if (userId == null) {
      _showMessage('Нет авторизованного пользователя');
      return;
    }
    if (goal.dates.isEmpty) {
      _showMessage('Добавьте хотя бы одну дату и задачу');
      return;
    }
    final hasTasks = goal.dates.any((d) => d.tasks.isNotEmpty);
    if (!hasTasks) {
      _showMessage('Добавьте хотя бы одну задачу');
      return;
    }
    final saved = goal.copyWith(isSaved: true, isActive: false, savedAt: DateTime.now());
    await _persistGoal(saved, userId);
    setState(() {
      final idx = _goals.indexWhere((g) => g.id == saved.id);
      if (idx >= 0) {
        _goals[idx] = saved;
      } else {
        _goals.add(saved);
      }
      _activeGoalId = null;
    });
    _showMessage('План сохранен');
  }

  Future<void> _persistGoal(GoalModel goal, int userId) async {
    final id = await _planRepo.saveGoal(goal, userId);
    final updated = goal.copyWith(dbId: id);
    setState(() {
      final idx = _goals.indexWhere((g) => g.id == updated.id);
      if (idx >= 0) {
        _goals[idx] = updated;
      } else {
        _goals.add(updated);
      }
    });
  }

  void _openGoal(GoalModel goal) {
    setState(() {
      _activeGoalId = goal.id;
      for (var g in _goals) {
        final idx = _goals.indexOf(g);
        _goals[idx] = g.copyWith(isActive: g.id == goal.id);
      }
    });
  }

  void _deleteGoal(String goalId) {
    GoalModel? goal;
    for (final g in _goals) {
      if (g.id == goalId) {
        goal = g;
        break;
      }
    }
    setState(() {
      _goals.removeWhere((g) => g.id == goalId);
      if (_activeGoalId == goalId) {
        _activeGoalId = null;
      }
    });
    if (goal?.dbId != null) {
      _planRepo.deleteGoal(goal!.dbId!);
    }
  }

  // --------- Даты и задачи ---------
  void _addDate(DateTime date) {
    final goal = _activeGoal;
    if (goal == null) return;
    final exists = goal.dates.any((d) => _isSameDay(d.date, date));
    if (exists) {
      _showMessage('Такая дата уже есть');
      return;
    }
    final newDateId = _uuid.v4();
    final updatedDates = [...goal.dates, GoalDate(id: newDateId, date: date, tasks: [])];
    final updated = goal.copyWith(dates: updatedDates);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
    // Автоматический скролл к новой дате
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _deleteDate(String dateId) {
    final goal = _activeGoal;
    if (goal == null) return;
    final updatedDates = goal.dates.where((d) => d.id != dateId).toList();
    final updated = goal.copyWith(dates: updatedDates);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  void _addTaskToDate(String dateId, String title, int priority) {
    final goal = _activeGoal;
    if (goal == null) return;
    final dates = goal.dates.map((d) {
      if (d.id != dateId) return d;
      final newTask = GoalTask(
        id: _uuid.v4(),
        title: title,
        priority: priority,
        isCompleted: false,
      );
      return d.copyWith(tasks: [...d.tasks, newTask]);
    }).toList();
    final updated = goal.copyWith(dates: dates);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  void _toggleTask(String dateId, String taskId) {
    final goal = _activeGoal;
    if (goal == null) return;
    final dates = goal.dates.map((d) {
      if (d.id != dateId) return d;
      final tasks = d.tasks
          .map((t) => t.id == taskId ? t.copyWith(isCompleted: !t.isCompleted) : t)
          .toList();
      return d.copyWith(tasks: tasks);
    }).toList();
    final updated = goal.copyWith(dates: dates);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  void _deleteTask(String dateId, String taskId) {
    final goal = _activeGoal;
    if (goal == null) return;
    final dates = goal.dates.map((d) {
      if (d.id != dateId) return d;
      return d.copyWith(tasks: d.tasks.where((t) => t.id != taskId).toList());
    }).toList();
    final updated = goal.copyWith(dates: dates);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  void _updateActiveGoal(GoalModel updated) {
    final idx = _goals.indexWhere((g) => g.id == updated.id);
    if (idx == -1) return;
    setState(() {
      _goals[idx] = updated;
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // --------- UI helpers ---------
  double _progressOf(GoalModel goal) {
    final total = goal.dates.fold<int>(0, (sum, d) => sum + d.tasks.length);
    final done = goal.dates.fold<int>(0, (sum, d) => sum + d.tasks.where((t) => t.isCompleted).length);
    if (total == 0) return 0;
    return done / total;
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _persistIfSaved(GoalModel goal) {
    if (!goal.isSaved) return;
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    _persistGoal(goal, userId);
  }

  Future<void> _showAddDateDialog() async {
    DateTime selected = DateTime.now();
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
                initialDate: DateTime.now(),
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
                  _addDate(selected);
                },
                child: const Text('Добавить'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddTaskDialog(String dateId) async {
    final titleCtrl = TextEditingController();
    int priority = 2;
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
                'Добавить задачу',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  hintText: 'Название задачи',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _priorityChip(1, 'assets/icon/thunder-red.png', priority, () {
                    priority = 1;
                    (ctx as Element).markNeedsBuild();
                  }),
                  const SizedBox(width: 8),
                  _priorityChip(2, 'assets/icon/thunder-yellow.png', priority, () {
                    priority = 2;
                    (ctx as Element).markNeedsBuild();
                  }),
                  const SizedBox(width: 8),
                  _priorityChip(3, 'assets/icon/thunder-blue.png', priority, () {
                    priority = 3;
                    (ctx as Element).markNeedsBuild();
                  }),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  if (titleCtrl.text.trim().isEmpty) return;
                  Navigator.of(ctx).pop();
                  _addTaskToDate(dateId, titleCtrl.text.trim(), priority);
                },
                child: const Text('Добавить'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _priorityChip(int value, String asset, int current, VoidCallback onTap) {
    final isActive = value == current;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
          border: Border.all(
            color: isActive ? Colors.black : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Image.asset(asset, width: 18, height: 18, fit: BoxFit.contain),
            const SizedBox(width: 6),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.black : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------- UI Builders ---------
  @override
  Widget build(BuildContext context) {
    final hasGoals = _goals.isNotEmpty;
    final activeGoal = _activeGoal;
    final savedGoals = _goals.where((g) => g.isSaved).toList();
    final showConstructor = activeGoal != null;
    final showCreation = !hasGoals;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top - 10),
            child: Column(
              children: [
                MainHeader(
                  title: 'План',
                  onMenuTap: _toggleSidebar,
                  onSearchTap: null,
                  onSettingsTap: () {
                    _navigateTo(const SettingsPage(), slideFromRight: true);
                  },
                  hideSearchAndSettings: false,
                  showBackButton: _activeGoalId != null,
                  onBack: () {
                    // Если открыт конструктор, закрыть его и показать список планов
                    if (_activeGoalId != null) {
                      setState(() {
                        _activeGoalId = null;
                      });
                    }
                  },
                  onGreetingToggle: null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 120),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: showConstructor
                          ? _buildConstructor(activeGoal!)
                          : savedGoals.isNotEmpty
                              ? _buildSavedList(savedGoals)
                              : showCreation
                                  ? _buildCreation()
                                  : _buildSavedList(savedGoals),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Sidebar(
            isOpen: _isSidebarOpen,
            onClose: _toggleSidebar,
            onTasksTap: () => _navigateTo(const TasksPage()),
            onChatTap: () => _navigateTo(const ChatPage()),
          ),
          BottomNavigation(
            currentIndex: 2,
            onAddTask: _createGoal,
            isSidebarOpen: _isSidebarOpen,
            onGptTap: _openAiMenu,
            onPlanTap: () {},
            onIndexChanged: (index) {
              if (index == 0) _navigateTo(const TasksPage());
            },
          ),
          if (_isAiMenuOpen)
            AiMenuModal(
              isOpen: _isAiMenuOpen,
              onClose: _closeAiMenu,
              onChat: _openAiChat,
              onPlan: _openAiPlan,
            ),
        ],
      ),
    );
  }

  Widget _buildCreation() {
    return Column(
      key: const ValueKey('creation'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F6F7),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Создайте новую цель',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Введите название цели, чтобы начать планирование',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _goalInputController,
                      decoration: InputDecoration(
                        hintText: 'Например: Подготовка к марафону',
                        hintStyle: const TextStyle(color: Color(0xFF999999)),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: Color.fromRGBO(0, 0, 0, 0.1), width: 2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: Color.fromRGBO(0, 0, 0, 0.1), width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Colors.black, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _createGoal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Создать',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        const Center(
          child: Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Создайте первую цель для начала планирования',
              style: TextStyle(fontSize: 16, color: Color(0xFF666666)),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConstructor(GoalModel goal) {
    final progress = _progressOf(goal);
    return Column(
      key: const ValueKey('constructor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F6F7),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      goal.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _iconButton(Icons.edit, onTap: () => _showRenameDialog(goal)),
                      const SizedBox(width: 8),
                      _iconButton(Icons.delete_outline, onTap: () => _deleteGoal(goal.id)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                          width: MediaQuery.of(context).size.width *
                              progress *
                              0.7,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC3545),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF666666),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Column(
          children: goal.dates
              .map(
                (d) => _DateCard(
                  date: d,
                  onAddTask: () => _showAddTaskDialog(d.id),
                  onDeleteDate: () => _deleteDate(d.id),
                  onToggleTask: (taskId) => _toggleTask(d.id, taskId),
                  onDeleteTask: (taskId) => _deleteTask(d.id, taskId),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        _addDateButton(),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            onPressed: _saveActiveGoal,
            child: const Text(
              'Сохранить',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addDateButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _showAddDateDialog,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: const BorderSide(color: Color.fromRGBO(0, 0, 0, 0.2), width: 2),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 20, color: Colors.black),
            SizedBox(width: 8),
            Text(
              'Добавить дату',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedList(List<GoalModel> saved) {
    return Column(
      key: const ValueKey('saved'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Список планов',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              _iconButton(Icons.add, onTap: () {
                _activeGoalId = null;
                _goals.removeWhere((g) => !g.isSaved);
                _goalInputController.clear();
                setState(() {});
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Column(
          children: saved
              .map(
                (g) => _SavedCard(
                  goal: g,
                  progress: _progressOf(g),
                  onOpen: () => _openGoal(g),
                  onDelete: () => _deleteGoal(g.id),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _iconButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: Colors.black),
      ),
    );
  }

  Future<void> _showRenameDialog(GoalModel goal) async {
    final ctrl = TextEditingController(text: goal.title);
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Переименовать цель',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Название цели',
                  hintStyle: const TextStyle(color: Color(0xFF999999)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color.fromRGBO(0, 0, 0, 0.1), width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color.fromRGBO(0, 0, 0, 0.1), width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: const BorderSide(color: Colors.black, width: 2),
                      ),
                      child: const Text(
                        'Отмена',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final text = ctrl.text.trim();
                        if (text.isNotEmpty) {
                          final updated = goal.copyWith(title: text);
                          _updateActiveGoal(updated);
                          _persistIfSaved(updated);
                        }
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Сохранить',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _DateCard extends StatelessWidget {
  final GoalDate date;
  final VoidCallback onAddTask;
  final VoidCallback onDeleteDate;
  final void Function(String taskId) onToggleTask;
  final void Function(String taskId) onDeleteTask;

  const _DateCard({
    required this.date,
    required this.onAddTask,
    required this.onDeleteDate,
    required this.onToggleTask,
    required this.onDeleteTask,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F6F7),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(date.date),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                Row(
                  children: [
                    _smallIcon(Icons.delete_outline, onTap: onDeleteDate),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              children: date.tasks
                  .map(
                    (t) => _TaskTile(
                      task: t,
                      onToggle: () => onToggleTask(t.id),
                      onDelete: () => onDeleteTask(t.id),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            _addTaskButton(),
          ],
        ),
      ),
    );
  }

  Widget _addTaskButton() {
    return GestureDetector(
      onTap: onAddTask,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.2), width: 2, style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add, size: 16, color: Colors.black),
            SizedBox(width: 8),
            Text(
              'Добавить задачу',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallIcon(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: Colors.black),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _TaskTile extends StatefulWidget {
  final GoalTask task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TaskTile({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile> {
  bool _showDelete = false;
  Timer? _deleteTimer;

  @override
  void dispose() {
    _deleteTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    setState(() {
      _showDelete = true;
    });
    _deleteTimer?.cancel();
    _deleteTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _showDelete = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Color borderColor;
    switch (widget.task.priority) {
      case 1:
        borderColor = const Color(0xFFDC3545);
        break;
      case 2:
        borderColor = const Color(0xFFFFC107);
        break;
      case 3:
      default:
        borderColor = const Color(0xFF28A745);
        break;
    }
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6F7),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: borderColor, width: 4)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: widget.onToggle,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E5E5), width: 2),
                  color: widget.task.isCompleted ? borderColor : Colors.white,
                ),
                child: widget.task.isCompleted
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.task.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: widget.task.isCompleted ? const Color(0xFF999999) : Colors.black,
                  decoration: widget.task.isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedOpacity(
              opacity: _showDelete ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: widget.onDelete,
                child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF666666)),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 20,
              height: 20,
              child: Image.asset(
                widget.task.priority == 1
                    ? 'assets/icon/thunder-red.png'
                    : widget.task.priority == 2
                        ? 'assets/icon/thunder-yellow.png'
                        : 'assets/icon/thunder-blue.png',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  final GoalModel goal;
  final double progress;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _SavedCard({
    required this.goal,
    required this.progress,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6F7),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${goal.dates.length} дат • ${goal.totalTasks} задач',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _smallIcon(Icons.delete_outline, onTap: onDelete),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                          width: MediaQuery.of(context).size.width *
                              progress *
                              0.6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC3545),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF666666),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallIcon(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: Colors.black),
      ),
    );
  }
}
