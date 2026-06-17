import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'package:uuid/uuid.dart';

import '../widgets/main_header.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/sidebar.dart';
import '../widgets/ai_menu_modal.dart';
import '../widgets/swipe_back_wrapper.dart';
import '../widgets/spotlight_search.dart';
import 'tasks_page.dart';
import 'gpt_plan_page.dart';
import 'list_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import 'notifications_page.dart';
import '../data/repositories/plan_repository.dart';
import '../data/user_session.dart';
import '../data/database_instance.dart';
import '../widgets/apple_calendar.dart';
import '../widgets/custom_snackbar.dart';
import '../models/goal_model.dart';
import '../widgets/task_sound_player.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

// Функция для правильного склонения слова "дата"
String _getDateWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  
  if (mod100 >= 11 && mod100 <= 14) {
    return tr('дат');
  } else if (mod10 == 1) {
    return tr('дата');
  } else if (mod10 >= 2 && mod10 <= 4) {
    return tr('даты');
  } else {
    return tr('дат');
  }
}

// Функция для правильного склонения слова "задача"
String _getTaskWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  
  if (mod100 >= 11 && mod100 <= 14) {
    return tr('задач');
  } else if (mod10 == 1) {
    return tr('задача');
  } else if (mod10 >= 2 && mod10 <= 4) {
    return tr('задачи');
  } else {
    return tr('задач');
  }
}

class PlanPage extends StatefulWidget {
  final String? initialGoalIdToOpen;
  final String? initialGoalTitle;
  
  const PlanPage({super.key, this.initialGoalIdToOpen, this.initialGoalTitle});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> with SingleTickerProviderStateMixin {
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

  late final AnimationController _gptIconController;
  late final Animation<double> _gptIconScale;

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
      // Если есть цель для открытия, устанавливаем её ID, иначе null
      if (widget.initialGoalIdToOpen != null && 
          items.any((g) => g.id == widget.initialGoalIdToOpen)) {
        _activeGoalId = widget.initialGoalIdToOpen;
      } else {
        _activeGoalId = null;
      }
      _isLoading = false; // Данные загружены
    });
  }

  @override
  void dispose() {
    _goalInputController.dispose();
    _goalTitleController.dispose();
    _scrollController.dispose();
    _gptIconController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _planRepo = PlanRepository(appDatabase);
    // Если есть название для нового плана, создаем его
    if (widget.initialGoalTitle != null && widget.initialGoalTitle!.isNotEmpty) {
      _goalTitleController.text = widget.initialGoalTitle!;
      _createGoalFromTitle(widget.initialGoalTitle!);
      _isEditMode = false;
      _isLoading = false;
    } else {
      // Если есть цель для открытия, устанавливаем её ID
      _activeGoalId = widget.initialGoalIdToOpen;
      _isEditMode = false;
      _isLoading = true;
    }
    
    // Инициализация анимации пульсации для иконки GPT
    _gptIconController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat(reverse: true);
    _gptIconScale = Tween<double>(begin: 1.0, end: 1.09).animate(
      CurvedAnimation(parent: _gptIconController, curve: Curves.easeInOut),
    );
    
    if (widget.initialGoalTitle == null || widget.initialGoalTitle!.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromDb());
    }
  }

  void _createGoalFromTitle(String title) {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
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
      _isEditMode = false;
    });
  }

  void _toggleSidebar() {
    // Скрываем клавиатуру при открытии/закрытии сайдбара
    FocusScope.of(context).unfocus();
    setState(() => _isSidebarOpen = !_isSidebarOpen);
  }
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
    if (page is SettingsPage || page is ChatPage) {
      // Для настроек и чата — push с CupertinoPageRoute (нативный iOS swipe back)
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => page,
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (_, animation, _) {
            final curve = Curves.easeInOut;
            return FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: curve),
              child: page,
            );
          },
        ),
      );
    }
  }

  // --------- Создание / управление планами ---------
  void _createGoal() {
    // Если вызывается из формы создания (кнопка "Создать"), создаем план с названием
    final title = _goalInputController.text.trim();
    if (title.isNotEmpty) {
      final userId = UserSession.currentUserId;
      if (userId == null) {
        _showMessage(tr('Нет авторизованного пользователя'));
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
        _showMessage(tr('Нет авторизованного пользователя'));
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
      _showMessage(tr('Нет авторизованного пользователя'));
      return;
    }
    if (goal.dates.isEmpty) {
      _showMessage(tr('Добавьте хотя бы одну дату и задачу'));
      return;
    }
    final hasTasks = goal.dates.any((d) => d.tasks.isNotEmpty);
    if (!hasTasks) {
      _showMessage(tr('Добавьте хотя бы одну задачу'));
      return;
    }
    // Сохраняем текущее название из контроллера
    final currentTitle = _goalTitleController.text.trim();
    final goalToSave = currentTitle.isNotEmpty 
        ? goal.copyWith(title: currentTitle, isSaved: true, isActive: false, savedAt: DateTime.now())
        : goal.copyWith(isSaved: true, isActive: false, savedAt: DateTime.now());
    
    // ВАЖНО: используем результат _persistGoal (с проставленным dbId).
    // Иначе in-memory цель остаётся с dbId == null, и следующее сохранение
    // снова уходит в ветку INSERT — появляется дубликат.
    final savedGoal = await _persistGoal(goalToSave, userId);
    setState(() {
      // Обновляем контроллер с сохраненным названием
      _goalTitleController.text = savedGoal.title;
      // Не закрываем план - он должен остаться открытым для просмотра
      // _activeGoalId остается установленным
      _isEditMode = false; // Выключаем режим редактирования после сохранения
    });
    _showMessage(tr('План сохранен 🌿'));
  }

  Future<GoalModel> _persistGoal(GoalModel goal, int userId) async {
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
    return updated;
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
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final colors = AppColors.of(ctx);
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
              Text(
                tr('Удалить план?'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr('В случае удаления цели она исчезнет безвозвратно. Вы точно хотите удалить цель?'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: colors.textSecondary,
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
                        side: BorderSide(
                          color: colors.border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(19),
                        ),
                      ),
                      child: Text(
                        tr('Отмена'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
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
                        backgroundColor: colors.inverseSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(19),
                        ),
                      ),
                      child: Text(
                        tr('Удалить'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: colors.onInverseSurface,
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
    // Вибрация при удалении цели
    HapticFeedback.heavyImpact();
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
      _showMessage(tr('Такая дата уже есть'));
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
    
    // Находим задачу, чтобы проверить, становится ли она выполненной
    final date = goal.dates.firstWhere((d) => d.id == dateId, orElse: () => goal.dates.first);
    final task = date.tasks.firstWhere((t) => t.id == taskId, orElse: () => date.tasks.first);
    final newCompletedState = !task.isCompleted;
    
    // Воспроизводим звук и вибрацию СРАЗУ при нажатии
    if (newCompletedState) {
      TaskSoundPlayer().playTaskCompleteSound();
      HapticFeedback.lightImpact();
    }
    
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
    // Вибрация при удалении задачи
    HapticFeedback.heavyImpact();
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
                initialDate: DateTime.now(),
                onDateSelected: (d) {
                  if (Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                  if (mounted) {
                    _addDate(d);
                  }
                },
                onClose: () {
                  if (Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                },
                tasks: const [],
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
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final colors = AppColors.of(ctx);
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
                tr('Добавить задачу'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary),
              ),
              const SizedBox(height: 24),
              _buildGoalInputField(
                controller: titleCtrl,
                label: tr('Название задачи'),
                hint: '',
                maxLength: 60,
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Приоритет'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
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
                                color: isSelected ? colors.elevatedSurface : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
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
                                          ? colors.textPrimary
                                          : colors.textSecondary,
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
                    backgroundColor: colors.inverseSurface,
                    foregroundColor: colors.onInverseSurface,
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
                  child: Text(
                    tr('Добавить'),
                    style: const TextStyle(
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

  // Функция для возврата из открытого плана в список планов
  void _goBackToPlanList() {
    setState(() {
      _activeGoalId = null;
      _isEditMode = false;
      // Удаляем несохраненные планы при возврате к списку
      _goals.removeWhere((g) => !g.isSaved);
    });
  }

  // --------- UI Builders ---------
  @override
  Widget build(BuildContext context) {
    final activeGoal = _activeGoal;
    final colors = AppColors.of(context);
    final savedGoals = _goals.where((g) => g.isSaved).toList();
    final showConstructor = activeGoal != null && _activeGoalId != null;
    final scaffold = Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top - 10),
            child: Column(
              children: [
                MainHeader(
                  title: tr('Цели'),
                  onMenuTap: _toggleSidebar,
                  onSearchTap: () {
                    showDialog(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.9),
                      builder: (context) => const SpotlightSearch(),
                    );
                  },
                  onSettingsTap: () {
                    _navigateTo(const NotificationsPage(), slideFromRight: true);
                  },
                  hideSearchAndSettings: false,
                  showBackButton: _activeGoalId != null,
                  onBack: _goBackToPlanList,
                  onGreetingToggle: null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    // Скроллим только когда контент не помещается на экран.
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 120),
                    child: _isLoading
                        ? const SizedBox.shrink() // Показываем пустой виджет во время загрузки
                        : showConstructor
                            ? _buildConstructor(activeGoal)
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
            onSettingsTap: () => _navigateTo(const SettingsPage(), slideFromRight: true),
          ),
          // Фиксированная кнопка GPT справа снизу (только для списка целей)
          if (_activeGoalId == null && savedGoals.isNotEmpty && !_isSidebarOpen)
            Positioned(
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 60, // Выше панели навигации (опущено на 15px)
              child: GestureDetector(
                onTap: _openAiPlan,
                child: AnimatedBuilder(
                  animation: _gptIconScale,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _gptIconScale.value,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: colors.elevatedSurface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.border,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/icon/gpt.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          BottomNavigation(
            currentIndex: 2,
            onAddTask: _activeGoalId == null ? _createGoal : null,
            isSidebarOpen: _isSidebarOpen,
            onGptTap: () {
              _navigateTo(const ListPage(), slideFromRight: true);
            },
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
            onAiTap: () {
              _navigateTo(const ChatPage(), slideFromRight: true);
            },
            onTasksTap: () => _navigateTo(const TasksPage()),
            onIndexChanged: (index) {
              if (index == 0) {
                _navigateTo(const TasksPage());
              } else if (index == 1) {
                _navigateTo(const ListPage(), slideFromRight: true);
              } else if (index == 3) {
                _navigateTo(const ChatPage(), slideFromRight: true);
              }
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

    // Обертываем в SwipeBackWrapper только если открыт план (не список)
    if (_activeGoalId != null) {
      // Создаем виджет списка планов для отображения при свайпе
      final planListWidget = Scaffold(
        backgroundColor: colors.background,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top - 10),
              child: Column(
                children: [
                  MainHeader(
                    title: tr('Цели'),
                    onMenuTap: _toggleSidebar,
                    onSearchTap: () {
                    showDialog(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.9),
                      builder: (context) => const SpotlightSearch(),
                    );
                  },
                    onSettingsTap: () {
                      _navigateTo(const NotificationsPage(), slideFromRight: true);
                    },
                    hideSearchAndSettings: false,
                    showBackButton: false,
                    onBack: null,
                    onGreetingToggle: null,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      // Скроллим только когда контент не помещается на экран.
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 120),
                      child: _isLoading
                          ? const SizedBox.shrink()
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
              onSettingsTap: () => _navigateTo(const SettingsPage(), slideFromRight: true),
            ),
            // Фиксированная кнопка GPT справа снизу (для списка в SwipeBackWrapper)
            if (savedGoals.isNotEmpty && !_isSidebarOpen)
              Positioned(
                right: 20,
                bottom: MediaQuery.of(context).padding.bottom + 60, // Выше панели навигации (опущено на 15px)
                child: GestureDetector(
                  onTap: _openAiPlan,
                  child: AnimatedBuilder(
                    animation: _gptIconScale,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _gptIconScale.value,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFE0E0E0),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Image.asset(
                              'assets/icon/gpt.png',
                              width: 28,
                              height: 28,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            BottomNavigation(
              currentIndex: 2,
              onAddTask: _createGoal,
              isSidebarOpen: _isSidebarOpen,
              onGptTap: () {
              _navigateTo(const ListPage(), slideFromRight: true);
            },
              onPlanTap: () {
                setState(() {
                  _activeGoalId = null;
                  _isEditMode = false;
                  _goals.removeWhere((g) => !g.isSaved);
                  _isLoading = true;
                });
                _loadFromDb();
              },
              onAiTap: () {
                _navigateTo(const ChatPage(), slideFromRight: true);
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

      return SwipeBackWrapper(
        onSwipeBack: _goBackToPlanList,
        previousScreen: planListWidget,
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildCreation() {
    final colors = AppColors.of(context);
    return Column(
      key: const ValueKey('creation'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Создайте новую цель'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('Введите название цели, чтобы начать планирование'),
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGoalInputField(
                      controller: _goalInputController,
                      label: tr('Название цели'),
                      hint: tr('Например: Подготовка к марафону'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.inverseSurface,
                        foregroundColor: colors.onInverseSurface,
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
                        children: [
                          const Icon(Icons.add, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            tr('Создать'),
                            style: const TextStyle(
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
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              tr('Создайте первую цель для начала планирования'),
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConstructor(GoalModel goal) {
    final progress = _progressOf(goal);
    final colors = AppColors.of(context);
    return Column(
      key: const ValueKey('constructor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
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
                        ? Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: TextField(
                            controller: _goalTitleController,
                            autofocus: !goal.isSaved && goal.title.isEmpty,
                            maxLines: 3,
                            minLines: 1,
                            maxLength: 40,
                            cursorHeight: 20,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                              height: 1.0,
                            ),
                            decoration: InputDecoration(
                              hintText: tr('Название цели'),
                              hintStyle: TextStyle(
                                color: colors.textTertiary,
                                height: 1.0,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: colors.border, width: 1),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: colors.border, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: colors.textPrimary, width: 1),
                              ),
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              isDense: true,
                              counterText: '',
                              constraints: const BoxConstraints(
                                minHeight: 40,
                                maxHeight: 88,
                              ),
                            ),
                            textInputAction: TextInputAction.done,
                            buildCounter: (BuildContext context, {required int currentLength, required int? maxLength, required bool isFocused}) => null,
                            ),
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              goal.title,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
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
                        _isEditMode
                            ? _iconButton(
                                Icons.check,
                                onTap: _toggleEditMode,
                              )
                            : _pencilButton(
                                onTap: _toggleEditMode,
                              ),
                        const SizedBox(width: 8),
                      ],
                      _trashIconButton(onTap: () => _showDeleteConfirmDialog(goal.id)),
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
                          color: colors.textPrimary.withValues(alpha: 0.1),
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
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
                  backgroundColor: colors.inverseSurface,
                  foregroundColor: colors.onInverseSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: _saveActiveGoal,
                child: Text(
                  tr('Сохранить'),
                  style: const TextStyle(
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
              child: Text(
                tr('Добавьте название вашей цели, выберите дни и создайте задачи'),
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
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
    final colors = AppColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _showAddDateDialog,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: colors.border, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 20, color: colors.icon),
            const SizedBox(width: 8),
            Text(
              tr('Добавить дату'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool autofocus = false,
    int? maxLines,
    int? minLines,
    int? maxLength,
    double? fontSize,
    FontWeight? fontWeight,
  }) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Лейбл над полем — без подложки, чтобы не было серого блока.
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: colors.border, width: 1),
              color: colors.elevatedSurface,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                maxLines: maxLines,
                minLines: minLines,
                maxLength: maxLength,
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: hint.isNotEmpty ? hint : null,
                  hintStyle: hint.isNotEmpty ? TextStyle(color: colors.textTertiary, fontSize: 16) : null,
                  border: InputBorder.none,
                  counterText: '',
                ),
                style: TextStyle(
                  fontSize: fontSize ?? 18,
                  fontWeight: fontWeight ?? FontWeight.normal,
                  color: colors.textPrimary,
                ),
                cursorColor: colors.textPrimary,
              ),
            ),
          ),
        ],
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
          child: Text(
            tr('Список целей'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.of(context).textPrimary,
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
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: iconSize, color: colors.icon),
      ),
    );
  }

  Widget _pencilButton({required VoidCallback onTap}) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 18,
            height: 18,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                colors.icon,
                BlendMode.srcIn,
              ),
              child: Image.asset(
                'assets/icon/pencil.png',
                cacheWidth: 68,
                cacheHeight: 68,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trashIconButton({required VoidCallback onTap}) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 19,
            height: 19,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                colors.icon,
                BlendMode.srcIn,
              ),
              child: Image.asset(
                'assets/icon/trash.png',
                cacheWidth: 68,
                cacheHeight: 68,
              ),
            ),
          ),
        ),
      ),
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
    final colors = AppColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (isEditMode)
                  Row(
                    children: [
                      _smallTrashIcon(context, onTap: onDeleteDate),
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
              _addTaskButton(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addTaskButton(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onAddTask,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border, width: 2, style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: colors.icon),
            const SizedBox(width: 8),
            Text(
              tr('Добавить задачу'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallTrashIcon(BuildContext context, {required VoidCallback onTap}) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 17,
            height: 17,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                colors.icon,
                BlendMode.srcIn,
              ),
              child: Image.asset(
                'assets/icon/trash.png',
                cacheWidth: 68,
                cacheHeight: 68,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = [
      tr('января'),
      tr('февраля'),
      tr('марта'),
      tr('апреля'),
      tr('мая'),
      tr('июня'),
      tr('июля'),
      tr('августа'),
      tr('сентября'),
      tr('октября'),
      tr('ноября'),
      tr('декабря')
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
  bool _isHovered = false;
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
    final colors = AppColors.of(context);
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
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: borderColor, width: 4)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: widget.onToggle,
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.task.isCompleted
                          ? borderColor
                          : _isHovered
                              ? colors.textTertiary
                              : colors.border,
                      width: 2,
                    ),
                    color: widget.task.isCompleted
                        ? borderColor
                        : Colors.transparent,
                  ),
                  child: widget.task.isCompleted
                      ? const Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.task.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: widget.task.isCompleted ? colors.textTertiary : colors.textPrimary,
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 17,
                    height: 17,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        colors.textSecondary,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        'assets/icon/trash.png',
                        cacheWidth: 68,
                        cacheHeight: 68,
                      ),
                    ),
                  ),
                ),
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
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onOpen,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
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
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.visible,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr('{0} {1} • {2} {3}', [goal.dates.length, _getDateWord(goal.dates.length), goal.totalTasks, _getTaskWord(goal.totalTasks)]),
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      _smallTrashIcon(context, onTap: onDelete),
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
                        color: colors.textPrimary.withValues(alpha: 0.1),
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
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

  Widget _smallTrashIcon(BuildContext context, {required VoidCallback onTap}) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 17,
            height: 17,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                colors.icon,
                BlendMode.srcIn,
              ),
              child: Image.asset(
                'assets/icon/trash.png',
                cacheWidth: 68,
                cacheHeight: 68,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
