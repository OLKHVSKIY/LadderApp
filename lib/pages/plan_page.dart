import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:uuid/uuid.dart';

import '../widgets/main_header.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/sidebar.dart';
import '../widgets/ai_menu_modal.dart';
import 'tasks_page.dart';
import 'gpt_plan_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import 'notes_page.dart';
import '../data/repositories/plan_repository.dart';
import '../data/user_session.dart';
import '../data/database_instance.dart';
import '../widgets/apple_calendar.dart';
import '../widgets/custom_snackbar.dart';
import '../models/goal_model.dart';

// Функция для правильного склонения слова "дата"
String _getDateWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  
  if (mod100 >= 11 && mod100 <= 14) {
    return 'дат';
  } else if (mod10 == 1) {
    return 'дата';
  } else if (mod10 >= 2 && mod10 <= 4) {
    return 'даты';
  } else {
    return 'дат';
  }
}

// Функция для правильного склонения слова "задача"
String _getTaskWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  
  if (mod100 >= 11 && mod100 <= 14) {
    return 'задач';
  } else if (mod10 == 1) {
    return 'задача';
  } else if (mod10 >= 2 && mod10 <= 4) {
    return 'задачи';
  } else {
    return 'задач';
  }
}

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
  bool _isEditMode = false;
  bool _isLoading = true; // Флаг загрузки данных
  final TextEditingController _goalTitleController = TextEditingController();

  GoalModel? get _activeGoal {
    if (_goals.isEmpty) return null;
    return _goals.firstWhere(
      (g) => g.id == _activeGoalId,
      orElse: () => _goals.first,
    );
  }

  Future<void> _loadFromDb() async {
    final userId = UserSession.currentUserId;
    if (userId == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    final items = await _planRepo.loadGoals(userId);
    setState(() {
      _goals
        ..clear()
        ..addAll(items);
      _activeGoalId = null;
      _isLoading = false; // Данные загружены
    });
  }

  @override
  void dispose() {
    _goalInputController.dispose();
    _goalTitleController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _planRepo = PlanRepository(appDatabase);
    // Убеждаемся, что при открытии страницы показывается список планов
    _activeGoalId = null;
    _isEditMode = false;
    _isLoading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromDb());
  }

  void _toggleSidebar() {
    // Скрываем клавиатуру при открытии/закрытии сайдбара
    FocusScope.of(context).unfocus();
    setState(() => _isSidebarOpen = !_isSidebarOpen);
  }
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
    // Если вызывается из формы создания (кнопка "Создать"), создаем план с названием
    final title = _goalInputController.text.trim();
    if (title.isNotEmpty) {
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
        _isEditMode = false; // Режим редактирования выключен для нового плана
        _goalTitleController.text = goal.title;
        _goalInputController.clear();
      });
    } else {
      // Если вызывается из панели навигации (+), создаем пустой план для редактирования
      final userId = UserSession.currentUserId;
      if (userId == null) {
        _showMessage('Нет авторизованного пользователя');
        return;
      }
      final goal = GoalModel(
        id: _uuid.v4(),
        title: '',
        isSaved: false,
        isActive: true,
        dates: [],
        createdAt: DateTime.now(),
        dbId: null,
      );
      setState(() {
        _goals.add(goal);
        _activeGoalId = goal.id;
        _isEditMode = true; // Включаем режим редактирования для ввода названия
        _goalTitleController.text = '';
        _goalInputController.clear();
      });
    }
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
    // Сохраняем текущее название из контроллера
    final currentTitle = _goalTitleController.text.trim();
    final goalToSave = currentTitle.isNotEmpty 
        ? goal.copyWith(title: currentTitle, isSaved: true, isActive: false, savedAt: DateTime.now())
        : goal.copyWith(isSaved: true, isActive: false, savedAt: DateTime.now());
    
    await _persistGoal(goalToSave, userId);
    setState(() {
      final idx = _goals.indexWhere((g) => g.id == goalToSave.id);
      if (idx >= 0) {
        _goals[idx] = goalToSave;
      } else {
        _goals.add(goalToSave);
      }
      // Обновляем контроллер с сохраненным названием
      _goalTitleController.text = goalToSave.title;
      // Не закрываем план - он должен остаться открытым для просмотра
      // _activeGoalId остается установленным
      _isEditMode = false; // Выключаем режим редактирования после сохранения
    });
    _showMessage('План сохранен 🌿');
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
      _isEditMode = false;
      _goalTitleController.text = goal.title;
      for (var g in _goals) {
        final idx = _goals.indexOf(g);
        _goals[idx] = g.copyWith(isActive: g.id == goal.id);
      }
    });
  }

  void _toggleEditMode() {
    final goal = _activeGoal;
    if (goal == null) return;
    
    if (_isEditMode) {
      // Сохраняем изменения
      final newTitle = _goalTitleController.text.trim();
      if (newTitle.isNotEmpty && newTitle != goal.title) {
        final updated = goal.copyWith(title: newTitle);
        _updateActiveGoal(updated);
        if (goal.isSaved) {
          _persistIfSaved(updated);
        }
      }
      setState(() {
        _isEditMode = false;
      });
    } else {
      // Включаем режим редактирования
      setState(() {
        _isEditMode = true;
        _goalTitleController.text = goal.title;
      });
    }
  }

  Future<void> _showDeleteConfirmDialog(String goalId) async {
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
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 40,
            left: 20,
            right: 20,
            top: 40,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Удалить план?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'В случае удаления цели она исчезнет безвозвратно. Вы точно хотите удалить цель?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF666666),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(
                          color: Color(0xFF6D6D6D),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(19),
                        ),
                      ),
                      child: const Text(
                        'Отмена',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _deleteGoal(goalId);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(19),
                        ),
                      ),
                      child: const Text(
                        'Удалить',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
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
    // Вибрация при отметке задачи
    HapticFeedback.mediumImpact();
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
    CustomSnackBar.show(context, msg);
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
              AppleCalendar(
                initialDate: DateTime.now(),
                onDateSelected: (d) {
                  selected = d;
                },
                onClose: () {},
                tasks: const [],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.6,
                child: ElevatedButton(
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
              const SizedBox(height: 24),
              TextField(
                controller: titleCtrl,
                maxLength: 60,
                decoration: InputDecoration(
                  hintText: 'Название задачи',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black, width: 1.5),
                  ),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Приоритет',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [1, 2, 3].map((p) {
                        final isSelected = priority == p;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              priority = p;
                              (ctx as Element).markNeedsBuild();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    p == 1
                                        ? 'assets/icon/thunder-red.png'
                                        : p == 2
                                            ? 'assets/icon/thunder-yellow.png'
                                            : 'assets/icon/thunder-blue.png',
                                    width: 20,
                                    height: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$p',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected
                                          ? Colors.black
                                          : const Color(0xFF666666),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(19),
                    ),
                  ),
                  onPressed: () {
                    if (titleCtrl.text.trim().isEmpty) return;
                    Navigator.of(ctx).pop();
                    _addTaskToDate(dateId, titleCtrl.text.trim(), priority);
                    // Скрываем клавиатуру после добавления задачи
                    FocusScope.of(ctx).unfocus();
                  },
                  child: const Text(
                    'Добавить',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
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
    final activeGoal = _activeGoal;
    final savedGoals = _goals.where((g) => g.isSaved).toList();
    final showConstructor = activeGoal != null && _activeGoalId != null;
    // Блок создания показывается только если данные загружены И нет сохраненных планов
    final showCreation = !_isLoading && savedGoals.isEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top - 10),
            child: Column(
              children: [
                MainHeader(
                  title: 'Цели',
                  onMenuTap: _toggleSidebar,
                  onSearchTap: null,
                  onSettingsTap: () {
                    _navigateTo(const SettingsPage(), slideFromRight: true);
                  },
                  hideSearchAndSettings: false,
                  showBackButton: _activeGoalId != null,
                  onBack: () {
                    // Если открыт план, закрыть его и показать список планов
                    setState(() {
                      _activeGoalId = null;
                      _isEditMode = false;
                      // Удаляем несохраненные планы при возврате к списку
                      _goals.removeWhere((g) => !g.isSaved);
                    });
                  },
                  onGreetingToggle: null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 120),
                    child: _isLoading
                        ? const SizedBox.shrink() // Показываем пустой виджет во время загрузки
                        : showConstructor
                            ? _buildConstructor(activeGoal!)
                            : savedGoals.isNotEmpty
                                ? _buildSavedList(savedGoals)
                                : _buildCreation(),
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
            onAddTask: _activeGoalId == null ? _createGoal : null,
            isSidebarOpen: _isSidebarOpen,
            onGptTap: _openAiMenu,
            onPlanTap: () {
              // При нажатии на "План" всегда показываем список планов
              setState(() {
                _activeGoalId = null;
                _isEditMode = false;
                _goals.removeWhere((g) => !g.isSaved);
                _isLoading = true; // Устанавливаем флаг загрузки перед перезагрузкой
              });
              // Перезагружаем данные из БД
              _loadFromDb();
            },
            onNotesTap: () {
              _navigateTo(const NotesPage());
            },
            onTasksTap: () => _navigateTo(const TasksPage()),
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
                  Flexible(
                    flex: 3,
                    child: (!goal.isSaved || _isEditMode)
                        ? TextField(
                            controller: _goalTitleController,
                            autofocus: !goal.isSaved && goal.title.isEmpty,
                            maxLines: 2,
                            minLines: 1,
                            maxLength: 40,
                            cursorHeight: 20,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Введите название цели',
                              hintStyle: const TextStyle(
                                color: Color(0xFF999999),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black, width: 1),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black, width: 1),
                              ),
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              isDense: false,
                              counterText: '',
                            ),
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              goal.title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      // Кнопка редактирования показывается только для сохраненных планов
                      if (goal.isSaved) ...[
                        _iconButton(
                          _isEditMode ? Icons.check : Icons.edit,
                          onTap: _toggleEditMode,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _iconButton(Icons.delete_outline, onTap: () => _showDeleteConfirmDialog(goal.id), iconSize: 22),
                    ],
                  ),
                ],
              ),
              // Прогресс бар показывается только для сохраненных планов не в режиме редактирования
              if (goal.isSaved && !_isEditMode) ...[
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
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeInOut,
                                width: constraints.maxWidth * progress,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC3545),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            );
                          },
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
                  isEditMode: !goal.isSaved || _isEditMode,
                ),
              )
              .toList(),
        ),
        // Для несохраненных планов показываем кнопки "Добавить дату" и "Сохранить"
        // Для сохраненных планов показываем кнопки только в режиме редактирования
        if (!goal.isSaved || _isEditMode) ...[
          const SizedBox(height: 12),
          _addDateButton(),
          // Кнопка "Сохранить" показывается только для несохраненных планов
          if (!goal.isSaved) ...[
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
            const SizedBox(height: 30),
            AnimatedOpacity(
              opacity: goal.dates.any((d) => d.tasks.isNotEmpty) ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: const Text(
                'Добавьте название вашей цели, выберите дни и создайте задачи',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
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
          child: const Text(
            'Список целей',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
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
                  onDelete: () => _showDeleteConfirmDialog(g.id),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _iconButton(IconData icon, {required VoidCallback onTap, double iconSize = 20}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: iconSize, color: Colors.black),
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
  final bool isEditMode;

  const _DateCard({
    required this.date,
    required this.onAddTask,
    required this.onDeleteDate,
    required this.onToggleTask,
    required this.onDeleteTask,
    this.isEditMode = true,
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
                if (isEditMode)
                  Row(
                    children: [
                      _smallIcon(Icons.delete_outline, onTap: onDeleteDate, iconSize: 18),
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
            if (isEditMode) ...[
              const SizedBox(height: 8),
              _addTaskButton(),
            ],
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

  Widget _smallIcon(IconData icon, {required VoidCallback onTap, double iconSize = 18}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: iconSize, color: Colors.black),
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
        borderColor = const Color(0xFFDC3545); // Красный (thunder-red.png)
        break;
      case 2:
        borderColor = const Color(0xFFFFC107); // Желтый (thunder-yellow.png)
        break;
      case 3:
      default:
        borderColor = const Color(0xFF007AFF); // Синий (thunder-blue.png)
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
          color: Colors.white,
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
                child: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF666666)),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.visible,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${goal.dates.length} ${_getDateWord(goal.dates.length)} • ${goal.totalTasks} ${_getTaskWord(goal.totalTasks)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      _smallIcon(Icons.delete_outline, onTap: onDelete, iconSize: 18),
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
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                              width: constraints.maxWidth * progress,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC3545),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        },
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

  Widget _smallIcon(IconData icon, {required VoidCallback onTap, double iconSize = 18}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: iconSize, color: Colors.black),
      ),
    );
  }
}
