import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/main_header.dart';
import '../widgets/swipeable_page_route.dart';
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
import '../models/task.dart';
import '../models/reminder_model.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/reminder_repository.dart';
import '../services/notification_service.dart';
import '../widgets/task_sound_player.dart';
import '../widgets/goal_celebration.dart';
import '../widgets/glass.dart';
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

// Функция для правильного склонения слова "день"
String _getDayWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod100 >= 11 && mod100 <= 14) {
    return tr('дней');
  } else if (mod10 == 1) {
    return tr('день');
  } else if (mod10 >= 2 && mod10 <= 4) {
    return tr('дня');
  } else {
    return tr('дней');
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

// Значение метрики: целое без дробей, иначе один знак.
String _fmtMetricValue(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

// Короткая дата «д месяц» (для подписи дедлайна в списке целей).
String _formatShortGoalDate(DateTime d) {
  const months = [
    'янв.', 'фев.', 'мар.', 'апр.', 'мая', 'июн.',
    'июл.', 'авг.', 'сен.', 'окт.', 'ноя.', 'дек.',
  ];
  return '${d.day} ${tr(months[d.month - 1])}';
}

// Подпись дедлайна под названием цели: «до 12 авг. • осталось 8 дней».
String _deadlineSubtitle(GoalModel goal) {
  if (goal.deadline == null) return '';
  final daysLeft = goal.daysLeft!;
  final date = _formatShortGoalDate(goal.deadline!);
  if (daysLeft < 0) {
    return tr('до {0} • просрочено', [date]);
  } else if (daysLeft == 0) {
    return tr('до {0} • сегодня', [date]);
  }
  return tr('до {0} • {1} {2}', [date, daysLeft, _getDayWord(daysLeft)]);
}

// Компактный бейдж «темпа» для карточки цели в списке.
Widget _goalPaceBadge(BuildContext context, GoalModel goal) {
  if (goal.deadline == null) return const SizedBox.shrink();
  final daysLeft = goal.daysLeft!;
  final delta = goal.paceDelta;
  final done = goal.totalTasks > 0 && goal.progress >= 1.0;
  String label;
  Color color;
  IconData icon;
  if (done) {
    label = tr('Достигнута');
    color = const Color(0xFF34C759);
    icon = Icons.emoji_events_rounded;
  } else if (daysLeft < 0) {
    label = tr('Просрочено');
    color = const Color(0xFFDC3545);
    icon = Icons.warning_amber_rounded;
  } else if (delta != null && delta > 0.07) {
    label = tr('Опережение');
    color = const Color(0xFF34C759);
    icon = Icons.trending_up_rounded;
  } else if (delta != null && delta < -0.07) {
    label = tr('Отставание');
    color = const Color(0xFFFF9500);
    icon = Icons.trending_down_rounded;
  } else {
    label = tr('По графику');
    color = const Color(0xFF007AFF);
    icon = Icons.trending_flat_rounded;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
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
  late final TaskRepository _taskRepo;
  final ScrollController _scrollController = ScrollController();

  final List<GoalModel> _goals = [];
  String? _activeGoalId;
  bool _isEditMode = false;
  bool _isLoading = true; // Флаг загрузки данных
  final TextEditingController _goalTitleController = TextEditingController();
  // Поле «зачем мне эта цель» (мотивация).
  final TextEditingController _motivationController = TextEditingController();
  // Данные текущего празднования (веха / победа первой недели). null — нет.
  _Celebration? _celebration;
  // Контекстное меню цели (по зажатию на карточке в списке).
  String? _openMenuGoalId;
  OverlayEntry? _goalMenuOverlayEntry;
  // Выпадающее меню кнопки «Добавить» (стиль меню блока таймлайна).
  OverlayEntry? _addMenuOverlayEntry;
  final GlobalKey _addButtonKey = GlobalKey();

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
    _removeGoalMenuOverlay();
    _removeAddMenuOverlay();
    _goalInputController.dispose();
    _goalTitleController.dispose();
    _motivationController.dispose();
    _scrollController.dispose();
    _gptIconController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _planRepo = PlanRepository(appDatabase);
    _taskRepo = TaskRepository(appDatabase);
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
        SwipeablePageRoute(
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
        _motivationController.text = goal.motivation ?? '';
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
        _motivationController.text = '';
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
    // Название цели обязательно.
    if (_goalTitleController.text.trim().isEmpty) {
      _showMessage(tr('Введите название цели'));
      return;
    }
    // Числовой цели не нужны даты/задачи — достаточно метрики.
    if (goal.metric == null) {
      if (goal.dates.isEmpty) {
        _showMessage(tr('Добавьте хотя бы одну дату и задачу'));
        return;
      }
      final hasTasks = goal.dates.any((d) => d.tasks.isNotEmpty);
      if (!hasTasks) {
        _showMessage(tr('Добавьте хотя бы одну задачу'));
        return;
      }
    }
    // Сохраняем текущее название и мотивацию из контроллеров
    final currentTitle = _goalTitleController.text.trim();
    final motivation = _motivationController.text.trim();
    var goalToSave = currentTitle.isNotEmpty
        ? goal.copyWith(title: currentTitle, isSaved: true, isActive: false, savedAt: DateTime.now())
        : goal.copyWith(isSaved: true, isActive: false, savedAt: DateTime.now());
    goalToSave = motivation.isNotEmpty
        ? goalToSave.copyWith(motivation: motivation)
        : goalToSave.copyWith(clearMotivation: true);
    
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
      _motivationController.text = goal.motivation ?? '';
      for (var g in _goals) {
        final idx = _goals.indexOf(g);
        _goals[idx] = g.copyWith(isActive: g.id == goal.id);
      }
    });
  }

  // --------- Контекстное меню цели ---------
  // Открывает/закрывает меню по зажатию карточки цели в списке.
  void _handleGoalMenuToggle(GoalModel? goal, Offset? position) {
    if (goal == null || position == null || _openMenuGoalId == goal.id) {
      setState(() => _openMenuGoalId = null);
      _removeGoalMenuOverlay();
      return;
    }
    setState(() => _openMenuGoalId = goal.id);
    _showGoalMenuOverlay(goal, position);
  }

  void _showGoalMenuOverlay(GoalModel goal, Offset position) {
    _removeGoalMenuOverlay();
    final overlay = Overlay.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    const menuWidth = 200.0;
    // Меню появляется чуть правее точки нажатия, не вылезая за край.
    final left = (position.dx - menuWidth + 40).clamp(12.0, screenWidth - menuWidth - 12);
    final top = position.dy + 8;
    _goalMenuOverlayEntry = OverlayEntry(
      builder: (context) => _GoalMenuOverlay(
        position: Offset(left, top),
        onClose: () => _handleGoalMenuToggle(null, null),
        onEdit: () {
          _handleGoalMenuToggle(null, null);
          _editGoal(goal);
        },
        onShare: () {
          _handleGoalMenuToggle(null, null);
          _shareGoal(goal);
        },
        onDelete: () async {
          _handleGoalMenuToggle(null, null);
          final ok = await _confirmDeleteGoal(goal);
          if (ok) {
            HapticFeedback.heavyImpact();
            await _deleteGoal(goal);
          }
        },
      ),
    );
    overlay.insert(_goalMenuOverlayEntry!);
  }

  void _removeGoalMenuOverlay() {
    _goalMenuOverlayEntry?.remove();
    _goalMenuOverlayEntry = null;
  }

  // Открывает цель и включает режим редактирования названия.
  void _editGoal(GoalModel goal) {
    setState(() {
      _activeGoalId = goal.id;
      _isEditMode = true;
      _goalTitleController.text = goal.title;
      _motivationController.text = goal.motivation ?? '';
      for (var g in _goals) {
        final idx = _goals.indexOf(g);
        _goals[idx] = g.copyWith(isActive: g.id == goal.id);
      }
    });
  }

  void _shareGoal(GoalModel goal) {
    final buffer = StringBuffer()
      ..writeln('🎯 ${goal.title}');
    if (goal.deadline != null) {
      buffer.writeln(tr('Дедлайн: {0}', [_formatShareDate(goal.deadline!)]));
    }
    buffer.writeln(tr('Прогресс: {0}%', [(_progressOf(goal) * 100).round()]));
    for (final d in goal.dates) {
      buffer.writeln(
          '\n${d.date != null ? _formatShareDate(d.date!) : tr('Задачи')}');
      for (final t in d.tasks) {
        buffer.writeln('${t.isCompleted ? '✓' : '•'} ${t.title}');
      }
    }
    SharePlus.instance.share(ShareParams(text: buffer.toString().trim()));
  }

  String _formatShareDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  // Подтверждение удаления цели (для свайпа и меню).
  Future<bool> _confirmDeleteGoal(GoalModel goal) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(tr('Удалить цель?')),
        content: Text(tr('«{0}» будет удалена безвозвратно.', [goal.title])),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Отмена')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Удалить')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteGoal(GoalModel goal) async {
    setState(() {
      _goals.removeWhere((g) => g.id == goal.id);
      if (_activeGoalId == goal.id) {
        _activeGoalId = null;
        _isEditMode = false;
      }
    });
    if (goal.dbId != null) {
      await _planRepo.deleteGoal(goal.dbId!);
    }
  }

  // --------- Даты и задачи ---------
  void _addDate(DateTime date) {
    final goal = _activeGoal;
    if (goal == null) return;
    final exists =
        goal.dates.any((d) => d.date != null && _isSameDay(d.date!, date));
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

  // Час по умолчанию для связанной задачи таймлайна (у задач цели нет времени).
  static const int _linkedTaskHour = 9;

  Future<void> _addTaskToDate(
    String dateId,
    String title,
    int priority, {
    bool createTimelineTask = false,
    Duration? reminderOffset,
  }) async {
    final goal = _activeGoal;
    if (goal == null) return;
    final dateEntry = goal.dates.firstWhere(
      (d) => d.id == dateId,
      orElse: () => goal.dates.first,
    );

    int? linkedTaskId;
    // Опционально создаём реальную задачу в «Списке» + напоминание.
    if (createTimelineTask) {
      final userId = UserSession.currentUserId;
      if (userId != null) {
        try {
          // Для задач без даты привязываем напоминание к сегодняшнему дню.
          final base = dateEntry.date ?? DateTime.now();
          final taskDate =
              DateTime(base.year, base.month, base.day, _linkedTaskHour);
          linkedTaskId = await _taskRepo.addTask(Task(
            id: '${DateTime.now().microsecondsSinceEpoch}',
            title: title,
            priority: priority,
            date: taskDate,
            tags: goal.title.trim().isEmpty ? const [] : [goal.title.trim()],
          ));
          if (reminderOffset != null) {
            final fireAt = taskDate.subtract(reminderOffset);
            await _createGoalReminder(
                'task', linkedTaskId, userId, title, fireAt,
                startTime: taskDate);
          }
        } catch (e) {
          debugPrint('Не удалось создать связанную задачу цели: $e');
        }
      }
    }

    final dates = goal.dates.map((d) {
      if (d.id != dateId) return d;
      final newTask = GoalTask(
        id: _uuid.v4(),
        title: title,
        priority: priority,
        isCompleted: false,
        linkedTaskId: linkedTaskId,
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

    // Синхронизируем выполнение со связанной задачей «Списка».
    if (task.linkedTaskId != null) {
      _taskRepo.updateCompletion(task.linkedTaskId!, newCompletedState);
    }

    final dates = goal.dates.map((d) {
      if (d.id != dateId) return d;
      final tasks = d.tasks
          .map((t) => t.id == taskId ? t.copyWith(isCompleted: !t.isCompleted) : t)
          .toList();
      return d.copyWith(tasks: tasks);
    }).toList();
    var updated = goal.copyWith(dates: dates);
    // Выполнение задачи = активность сегодня (стрик + «первая неделя»).
    if (newCompletedState) {
      updated = _registerActivity(updated);
      updated = _markWeekWins(updated, celebrate: true);
    }
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  // Помечает сегодняшний день как активный (если ещё не помечен).
  GoalModel _registerActivity(GoalModel goal) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final already = goal.activeDays.any(
        (d) => d.year == today.year && d.month == today.month && d.day == today.day);
    if (already) return goal;
    return goal.copyWith(activeDays: [...goal.activeDays, today]);
  }

  // Отмечает достигнутые чекпойнты «первой недели» (3/5/7 активных дней)
  // и, при необходимости, показывает празднование один раз на чекпойнт.
  GoalModel _markWeekWins(GoalModel goal, {bool celebrate = true}) {
    if (!goal.isWithinFirstWeek) return goal;
    final count = goal.firstWeekActiveCount;
    final reached = const [3, 5, 7]
        .where((cp) => count >= cp && !goal.weekWins.contains(cp))
        .toList();
    if (reached.isEmpty) return goal;
    final updated = goal.copyWith(weekWins: [...goal.weekWins, ...reached]);
    if (celebrate) {
      final cp = reached.last;
      if (cp >= 7) {
        _celebrate(
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFF34C759),
          title: tr('Неделя силы!'),
          subtitle: tr('7 активных дней в первую неделю — отличный старт'),
        );
      } else {
        _celebrate(
          icon: Icons.bolt_rounded,
          color: const Color(0xFFFF9500),
          title: tr('{0} {1} подряд!', [count, _getDayWord(count)]),
          subtitle: tr('Так держать — первая неделя задаёт темп'),
        );
      }
    }
    return updated;
  }

  // Показывает оверлей-празднование.
  void _celebrate({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
  }) {
    if (!mounted) return;
    setState(() {
      _celebration = _Celebration(
        icon: icon,
        color: color,
        title: title,
        subtitle: subtitle,
      );
    });
  }

  // --------- Вехи ---------
  void _addMilestone(String title) {
    final goal = _activeGoal;
    if (goal == null) return;
    final m = GoalMilestone(id: _uuid.v4(), title: title);
    final updated = goal.copyWith(milestones: [...goal.milestones, m]);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  void _toggleMilestone(String milestoneId) {
    final goal = _activeGoal;
    if (goal == null) return;
    final m = goal.milestones.firstWhere((e) => e.id == milestoneId);
    final newDone = !m.isCompleted;
    if (newDone) {
      TaskSoundPlayer().playTaskCompleteSound();
      HapticFeedback.lightImpact();
    }
    final milestones = goal.milestones
        .map((e) => e.id == milestoneId
            ? e.copyWith(
                isCompleted: newDone,
                completedAt: newDone ? DateTime.now() : null,
                clearCompletedAt: !newDone)
            : e)
        .toList();
    var updated = goal.copyWith(milestones: milestones);
    if (newDone) {
      updated = _registerActivity(updated);
      // Победы недели помечаем тихо — показываем празднование вехи.
      updated = _markWeekWins(updated, celebrate: false);
    }
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
    if (newDone) {
      _celebrate(
        icon: Icons.flag_rounded,
        color: const Color(0xFF34C759),
        title: tr('Веха достигнута!'),
        subtitle: m.title,
      );
    }
  }

  void _deleteMilestone(String milestoneId) {
    HapticFeedback.heavyImpact();
    final goal = _activeGoal;
    if (goal == null) return;
    final updated = goal.copyWith(
        milestones:
            goal.milestones.where((e) => e.id != milestoneId).toList());
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  Future<void> _showAddMilestoneDialog() async {
    final controller = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
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
        final colors = AppColors.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 20,
            right: 20,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHandle(colors),
              Text(
                tr('Новая веха'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border, width: 1),
                  color: colors.elevatedSurface,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 60,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      _addMilestone(v.trim());
                      Navigator.of(ctx).pop();
                    }
                  },
                  style: TextStyle(fontSize: 16, color: colors.textPrimary),
                  cursorColor: colors.textPrimary,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    hintText: tr('Например: Пробежать 10 км'),
                    hintStyle: TextStyle(color: colors.textTertiary),
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.inverseSurface,
                  foregroundColor: colors.onInverseSurface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    _addMilestone(controller.text.trim());
                    Navigator.of(ctx).pop();
                  }
                },
                child: Text(
                  tr('Добавить'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --------- Мотивация («зачем мне это») ---------
  // Сохраняет текст мотивации при потере фокуса / завершении ввода.
  void _commitMotivation() {
    final goal = _activeGoal;
    if (goal == null) return;
    final text = _motivationController.text.trim();
    final current = goal.motivation ?? '';
    if (text == current) return;
    final updated = text.isNotEmpty
        ? goal.copyWith(motivation: text)
        : goal.copyWith(clearMotivation: true);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  // --------- Числовая цель ---------
  // Целое — без дробей, иначе один знак после запятой.
  String _fmtMetric(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  // «Красивый» шаг для кнопок +/− по диапазону цели.
  double _metricStep(GoalMetric m) {
    final span = (m.targetValue - m.startValue).abs();
    if (span <= 0) return 1;
    final raw = span / 20;
    if (raw >= 1000) return (raw / 1000).round() * 1000.0;
    if (raw >= 100) return (raw / 100).round() * 100.0;
    if (raw >= 10) return (raw / 10).round() * 10.0;
    if (raw >= 1) return raw.roundToDouble();
    return 0.5;
  }

  void _setMetric(GoalMetric? metric) {
    final goal = _activeGoal;
    if (goal == null) return;
    final updated = metric != null
        ? goal.copyWith(metric: metric)
        : goal.copyWith(clearMetric: true);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  // Записывает новое текущее значение метрики + точку истории.
  void _commitMetricValue(double value) {
    final goal = _activeGoal;
    final metric = goal?.metric;
    if (goal == null || metric == null) return;
    final wasComplete = metric.progress >= 1.0;
    final m = metric.copyWith(
      currentValue: value,
      history: [
        ...metric.history,
        MetricEntry(date: DateTime.now(), value: value),
      ],
    );
    var updated = goal.copyWith(metric: m);
    final nowComplete = m.progress >= 1.0;
    // Изменение значения = активность сегодня (стрик + «первая неделя»).
    updated = _registerActivity(updated);
    updated = _markWeekWins(updated, celebrate: true);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
    HapticFeedback.lightImpact();
    if (!wasComplete && nowComplete) {
      _celebrate(
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFF34C759),
        title: tr('Цель достигнута!'),
        subtitle: goal.title,
      );
    }
  }

  void _adjustMetric(double delta) {
    final m = _activeGoal?.metric;
    if (m == null) return;
    _commitMetricValue(m.currentValue + delta);
  }

  Future<void> _showMetricSetupDialog({GoalMetric? existing}) async {
    final startCtrl = TextEditingController(
        text: existing != null ? _fmtMetric(existing.startValue) : '');
    final targetCtrl = TextEditingController(
        text: existing != null ? _fmtMetric(existing.targetValue) : '');
    final unitCtrl = TextEditingController(text: existing?.unit ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
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
        final colors = AppColors.of(ctx);
        Widget field(TextEditingController c, String hint, {bool number = true}) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border, width: 1),
              color: colors.elevatedSurface,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: c,
              keyboardType: number
                  ? const TextInputType.numberWithOptions(
                      decimal: true, signed: true)
                  : TextInputType.text,
              maxLength: 12,
              style: TextStyle(fontSize: 16, color: colors.textPrimary),
              cursorColor: colors.textPrimary,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: hint,
                hintStyle: TextStyle(color: colors.textTertiary),
                border: InputBorder.none,
                counterText: '',
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 20,
            right: 20,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHandle(colors),
              Text(
                tr('Числовая цель'),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Например: накопить 100 000 ₽ или −8 кг'),
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              Text(tr('Сейчас'),
                  style: TextStyle(fontSize: 13, color: colors.textSecondary)),
              const SizedBox(height: 6),
              field(startCtrl, tr('Например: 0')),
              const SizedBox(height: 12),
              Text(tr('Целевое значение'),
                  style: TextStyle(fontSize: 13, color: colors.textSecondary)),
              const SizedBox(height: 6),
              field(targetCtrl, tr('Например: 100000')),
              const SizedBox(height: 12),
              Text(tr('Единица'),
                  style: TextStyle(fontSize: 13, color: colors.textSecondary)),
              const SizedBox(height: 6),
              field(unitCtrl, tr('₽, кг, книг…'), number: false),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.inverseSurface,
                  foregroundColor: colors.onInverseSurface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () {
                  final start = double.tryParse(
                      startCtrl.text.trim().replaceAll(',', '.'));
                  final target = double.tryParse(
                      targetCtrl.text.trim().replaceAll(',', '.'));
                  if (start == null || target == null || start == target) {
                    _showMessage(tr('Укажите стартовое и целевое значения'));
                    return;
                  }
                  _setMetric(GoalMetric(
                    startValue: start,
                    targetValue: target,
                    currentValue: existing?.currentValue ?? start,
                    unit: unitCtrl.text.trim(),
                    history: existing?.history ?? const [],
                  ));
                  Navigator.of(ctx).pop();
                },
                child: Text(tr('Готово'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showMetricValueDialog() async {
    final metric = _activeGoal?.metric;
    if (metric == null) return;
    final ctrl = TextEditingController(text: _fmtMetric(metric.currentValue));
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
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
        final colors = AppColors.of(ctx);
        void submit(String v) {
          final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
          if (parsed != null) {
            _commitMetricValue(parsed);
            Navigator.of(ctx).pop();
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 20,
            right: 20,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHandle(colors),
              Text(
                tr('Текущее значение'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border, width: 1),
                  color: colors.elevatedSurface,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  textInputAction: TextInputAction.done,
                  onSubmitted: submit,
                  style: TextStyle(fontSize: 16, color: colors.textPrimary),
                  cursorColor: colors.textPrimary,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    suffixText: metric.unit.isNotEmpty ? metric.unit : null,
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.inverseSurface,
                  foregroundColor: colors.onInverseSurface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () => submit(ctrl.text),
                child: Text(tr('Сохранить'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _deleteTask(String dateId, String taskId) {
    // Вибрация при удалении задачи
    HapticFeedback.heavyImpact();
    final goal = _activeGoal;
    if (goal == null) return;
    // Снимаем связанную задачу таймлайна и её напоминание.
    GoalTask? removed;
    for (final d in goal.dates) {
      if (d.id != dateId) continue;
      for (final t in d.tasks) {
        if (t.id == taskId) removed = t;
      }
    }
    if (removed?.linkedTaskId != null) {
      _deleteLinkedTask(removed!.linkedTaskId!);
    }
    final dates = goal.dates.map((d) {
      if (d.id != dateId) return d;
      return d.copyWith(tasks: d.tasks.where((t) => t.id != taskId).toList());
    }).toList();
    final updated = goal.copyWith(dates: dates);
    _updateActiveGoal(updated);
    _persistIfSaved(updated);
  }

  // Удаляет связанную задачу «Списка» вместе с напоминаниями.
  Future<void> _deleteLinkedTask(int taskId) async {
    try {
      final repo = ReminderRepository(appDatabase);
      final existing = await repo.loadForOwner('task', taskId);
      for (final r in existing) {
        if (r.id != null) {
          await NotificationService.instance.cancelReminder(r.id!);
        }
      }
      await repo.deleteForOwner('task', taskId);
      await _taskRepo.deleteTask(taskId);
    } catch (e) {
      debugPrint('Не удалось удалить связанную задачу цели: $e');
    }
  }

  // Создаёт напоминание для задачи цели и планирует системное уведомление.
  Future<void> _createGoalReminder(String ownerType, int ownerId, int userId,
      String title, DateTime fireAt,
      {DateTime? startTime}) async {
    try {
      final body = _reminderBody(fireAt, startTime);
      final repo = ReminderRepository(appDatabase);
      final id = await repo.addReminder(Reminder(
        userId: userId,
        ownerType: ownerType,
        ownerId: ownerId,
        title: title,
        body: body,
        fireAt: fireAt,
      ));
      await NotificationService.instance.scheduleReminder(
        id: id,
        title: title,
        body: body,
        fireAt: fireAt,
      );
    } catch (e) {
      debugPrint('Не удалось создать напоминание цели: $e');
    }
  }

  String _reminderBody(DateTime fireAt, DateTime? startTime) {
    if (startTime == null) return tr('Скоро начало');
    final hh = startTime.hour.toString().padLeft(2, '0');
    final mm = startTime.minute.toString().padLeft(2, '0');
    final lead = startTime.difference(fireAt);
    if (lead.inMinutes <= 0) return tr('Начинается в {0}', ['$hh:$mm']);
    if (lead.inMinutes >= 1440) {
      return tr('Завтра в {0}', ['$hh:$mm']);
    }
    if (lead.inMinutes >= 60) {
      return tr('Через час, в {0}', ['$hh:$mm']);
    }
    return tr('Через {0} мин, в {1}', ['${lead.inMinutes}', '$hh:$mm']);
  }

  // --------- Дедлайн цели ---------
  // Пикер срока цели: пресеты по дням, свой вариант или «без дедлайна».
  Future<void> _showTermPicker() async {
    final goal = _activeGoal;
    if (goal == null) return;
    final customController = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
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
        final colors = AppColors.of(ctx);
        const presets = [7, 14, 30, 60, 90];
        final currentDays =
            goal.hasDeadline ? goal.termTotalDays : null;
        void apply(int? days) {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          if (mounted) _setGoalTerm(days);
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 44,
            left: 20,
            right: 20,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(colors),
              Text(
                tr('Срок цели'),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Сколько дней закладываете на цель'),
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final d in presets)
                    _termChip(
                      ctx,
                      label: '$d ${_getDayWord(d)}',
                      selected: currentDays == d,
                      onTap: () => apply(d),
                    ),
                  _termChip(
                    ctx,
                    label: tr('Без дедлайна'),
                    selected: !goal.hasDeadline,
                    onTap: () => apply(null),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                tr('Свой срок (дней)'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border, width: 1),
                        color: colors.elevatedSurface,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: customController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 16, color: colors.textPrimary),
                        cursorColor: colors.textPrimary,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          hintText: tr('Например: 21'),
                          hintStyle: TextStyle(color: colors.textTertiary),
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      final n = int.tryParse(customController.text.trim());
                      if (n != null && n > 0) apply(n);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC3545),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        tr('Готово'),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    customController.dispose();
  }

  // Чип пресета срока.
  Widget _termChip(BuildContext context,
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFDC3545).withValues(alpha: 0.14)
              : colors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFDC3545) : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? const Color(0xFFDC3545) : colors.textPrimary,
          ),
        ),
      ),
    );
  }

  // Задаёт срок цели: days==null — без дедлайна, иначе дедлайн = сегодня + days.
  void _setGoalTerm(int? days) {
    final goal = _activeGoal;
    if (goal == null) return;
    if (days == null) {
      _setDeadline(null);
      return;
    }
    final now = DateTime.now();
    final deadline =
        DateTime(now.year, now.month, now.day).add(Duration(days: days));
    _setDeadline(deadline);
  }

  void _setDeadline(DateTime? date) {
    final goal = _activeGoal;
    if (goal == null) return;
    final updated = date == null
        ? goal.copyWith(clearDeadline: true)
        : goal.copyWith(deadline: date);
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
    // Для числовой цели прогресс считается по значению, иначе по задачам.
    if (goal.metric != null) return goal.metric!.progress;
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
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(AppColors.of(ctx)),
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
    bool createTimelineTask = false;
    int reminderIndex = 0;
    const reminderLabels = [
      'Без напоминания',
      'В момент начала',
      'За 15 минут',
      'За 1 час',
      'За день',
    ];
    const reminderOffsets = <Duration?>[
      null,
      Duration.zero,
      Duration(minutes: 15),
      Duration(hours: 1),
      Duration(days: 1),
    ];
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
        final colors = AppColors.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(colors),
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
              const SizedBox(height: 16),
              // Связать с «Списком»: создаёт реальную задачу таймлайна + (опц.) напоминание.
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.playlist_add_check_rounded,
                            size: 20, color: colors.icon),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('Добавить в Список'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        CupertinoSwitch(
                          value: createTimelineTask,
                          activeTrackColor: colors.inverseSurface,
                          onChanged: (v) {
                            createTimelineTask = v;
                            (ctx as Element).markNeedsBuild();
                          },
                        ),
                      ],
                    ),
                    if (createTimelineTask) ...[
                      Divider(height: 1, color: colors.border),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          reminderIndex =
                              (reminderIndex + 1) % reminderLabels.length;
                          (ctx as Element).markNeedsBuild();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_none_rounded,
                                  size: 20, color: colors.icon),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  tr('Напоминание'),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                tr(reminderLabels[reminderIndex]),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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
                    _addTaskToDate(
                      dateId,
                      titleCtrl.text.trim(),
                      priority,
                      createTimelineTask: createTimelineTask,
                      reminderOffset: createTimelineTask
                          ? reminderOffsets[reminderIndex]
                          : null,
                    );
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
          if (_celebration != null)
            GoalCelebration(
              key: ValueKey(_celebration),
              icon: _celebration!.icon,
              color: _celebration!.color,
              title: _celebration!.title,
              subtitle: _celebration!.subtitle,
              onDismiss: () {
                if (mounted) setState(() => _celebration = null);
              },
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
        _glassCard(
          margin: const EdgeInsets.only(bottom: 24),
          child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              (!goal.isSaved || _isEditMode)
                  ? TextField(
                      controller: _goalTitleController,
                      autofocus: !goal.isSaved && goal.title.isEmpty,
                      maxLines: 3,
                      minLines: 1,
                      maxLength: 40,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                        height: 1.3,
                      ),
                      cursorColor: colors.textPrimary,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: tr('Название цели'),
                        hintStyle: TextStyle(color: colors.textTertiary),
                        filled: true,
                        fillColor: colors.surfaceVariant,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
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
                          borderSide:
                              BorderSide(color: colors.textPrimary, width: 1),
                        ),
                      ),
                      buildCounter: (BuildContext context,
                              {required int currentLength,
                              required int? maxLength,
                              required bool isFocused}) =>
                          null,
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
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
                        const SizedBox(width: 8),
                        // На месте кнопок редактирования/удаления — чип стрика.
                        _buildHeaderStreak(goal),
                      ],
                    ),
              _buildMotivationField(goal),
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
              _buildDeadlineBlock(goal),
              if (goal.isSaved && !_isEditMode) _buildStreakWeekBlock(goal),
            ],
          ),
          ),
        ),
        _buildMetricSection(goal),
        _buildMilestonesSection(goal),
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
          _addButton(),
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

  // Карточка в стиле Liquid Glass: матовое стекло + мягкая тень для читаемости.
  // Единая «черточка» для закрытия шторок — как во всём приложении.
  Widget _sheetHandle(AppColors colors) {
    return Center(
      child: Container(
        width: 45,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: colors.isDark ? colors.border : const Color(0xFFC2C1C1),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    double radius = 22,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: GlassPanel(
        borderRadius: radius,
        settings: AppGlass.panel,
        child: child,
      ),
    );
  }

  String _formatGoalDate(DateTime d) {
    final months = [
      tr('января'), tr('февраля'), tr('марта'), tr('апреля'),
      tr('мая'), tr('июня'), tr('июля'), tr('августа'),
      tr('сентября'), tr('октября'), tr('ноября'), tr('декабря'),
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // Блок дедлайна + «темп»: дата, сколько осталось и опережение/отставание.
  Widget _buildDeadlineBlock(GoalModel goal) {
    final colors = AppColors.of(context);
    final hasDeadline = goal.deadline != null;
    final daysLeft = goal.daysLeft;
    final delta = goal.paceDelta;
    final done = goal.totalTasks > 0 && goal.progress >= 1.0;
    final showPace = hasDeadline && goal.isSaved && !_isEditMode;

    final dateLabel =
        hasDeadline ? _formatGoalDate(goal.deadline!) : tr('Без дедлайна');

    String daysLabel = '';
    String? paceLabel;
    Color paceColor = colors.textSecondary;
    IconData paceIcon = Icons.trending_flat_rounded;
    if (hasDeadline) {
      if (daysLeft! < 0) {
        daysLabel =
            tr('Просрочено на {0} {1}', [-daysLeft, _getDayWord(-daysLeft)]);
      } else if (daysLeft == 0) {
        daysLabel = tr('Дедлайн сегодня');
      } else {
        daysLabel = tr('Осталось {0} {1}', [daysLeft, _getDayWord(daysLeft)]);
      }
    } else {
      daysLabel = tr('Срок не ограничен');
    }
    if (showPace) {
      if (done) {
        paceLabel = tr('Цель достигнута');
        paceColor = const Color(0xFF34C759);
        paceIcon = Icons.emoji_events_rounded;
      } else if (daysLeft! < 0) {
        paceLabel = tr('Просрочено');
        paceColor = const Color(0xFFDC3545);
        paceIcon = Icons.warning_amber_rounded;
      } else if (delta != null && delta > 0.07) {
        paceLabel = tr('С опережением');
        paceColor = const Color(0xFF34C759);
        paceIcon = Icons.trending_up_rounded;
      } else if (delta != null && delta < -0.07) {
        paceLabel = tr('С отставанием');
        paceColor = const Color(0xFFFF9500);
        paceIcon = Icons.trending_down_rounded;
      } else {
        paceLabel = tr('По графику');
        paceColor = const Color(0xFF007AFF);
        paceIcon = Icons.trending_flat_rounded;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showTermPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.elevatedSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border, width: 1),
          ),
          child: Row(
            children: [
              Icon(
                Icons.flag_rounded,
                size: 18,
                color: hasDeadline ? colors.textPrimary : colors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: hasDeadline
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                    if (daysLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        daysLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (paceLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: paceColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(paceIcon, size: 14, color: paceColor),
                      const SizedBox(width: 4),
                      Text(
                        paceLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: paceColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // Чип стрика в шапке открытой цели (на месте кнопок ред./удаления).
  Widget _buildHeaderStreak(GoalModel goal) {
    if (!goal.isSaved || _isEditMode) return const SizedBox.shrink();
    final streak = goal.streakInfo;
    if (streak.current == 0) return const SizedBox.shrink();
    return _buildFireChip(streak);
  }

  // Блок прогресса срока (или счётчика недель) + заморозки.
  Widget _buildStreakWeekBlock(GoalModel goal) {
    final streak = goal.streakInfo;
    final showFreeze = streak.freezeTokensTotal > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showFreeze) ...[
            _buildFreezeChip(streak),
            const SizedBox(height: 12),
          ],
          if (goal.hasDeadline)
            _buildTermStrip(goal)
          else
            _buildWeekCounter(goal),
        ],
      ),
    );
  }

  Widget _buildFireChip(GoalStreakInfo streak) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF7A00).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department,
              size: 16, color: Color(0xFFFF7A00)),
          const SizedBox(width: 6),
          Text(
            tr('{0} {1} подряд', [streak.current, _getDayWord(streak.current)]),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF7A00),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreezeChip(GoalStreakInfo streak) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF34AADC).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.ac_unit_rounded,
              size: 15,
              color: streak.freezeActive
                  ? const Color(0xFF34AADC)
                  : const Color(0xFF34AADC).withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Text(
            streak.freezeActive
                ? tr('Серия спасена')
                : tr('Заморозка ×{0}', [streak.freezeTokensLeft]),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF34AADC),
            ),
          ),
        ],
      ),
    );
  }

  // Прогресс по всему сроку цели: полоса активных дней + маркер «сегодня».
  Widget _buildTermStrip(GoalModel goal) {
    final colors = AppColors.of(context);
    final total = goal.termTotalDays ?? 1;
    final count = goal.termActiveCount;
    final daysLeft = goal.daysLeft ?? 0;
    final elapsed = (total - daysLeft).clamp(0, total);
    final activeFrac = (count / total).clamp(0.0, 1.0);
    final elapsedFrac = (elapsed / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr('Активность'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
            Text(
              '$count/$total',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: colors.textPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: activeFrac,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF7A00),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  // Маркер «сегодня» — где мы по времени относительно срока.
                  if (elapsedFrac > 0 && elapsedFrac < 1)
                    Positioned(
                      left: (w * elapsedFrac - 1).clamp(0.0, w - 2),
                      child: Container(
                        width: 2,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors.textPrimary.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // Режим без дедлайна: бесконечный счётчик недель + прогресс текущей недели.
  Widget _buildWeekCounter(GoalModel goal) {
    final colors = AppColors.of(context);
    final week = goal.weekNumber;
    final wc = goal.currentWeekActiveCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 14, color: Color(0xFF007AFF)),
                  const SizedBox(width: 6),
                  Text(
                    tr('Неделя {0}', [week]),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$wc/7',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(7, (i) {
            final filled = (i + 1) <= wc;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 6 ? 0 : 6),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: filled
                        ? const Color(0xFF007AFF)
                        : colors.textPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // Секция «Вехи» — крупные чекпойнты цели.
  // Поле/цитата «зачем мне эта цель».
  Widget _buildMotivationField(GoalModel goal) {
    final colors = AppColors.of(context);
    final editable = !goal.isSaved || _isEditMode;
    if (editable) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: _motivationController,
          maxLines: 3,
          minLines: 1,
          maxLength: 160,
          onTapOutside: (_) => _commitMotivation(),
          onEditingComplete: _commitMotivation,
          style: TextStyle(
              fontSize: 14, color: colors.textPrimary, height: 1.3),
          cursorColor: colors.textPrimary,
          decoration: InputDecoration(
            hintText: tr('Зачем мне эта цель?'),
            hintStyle: TextStyle(color: colors.textTertiary),
            filled: true,
            fillColor: colors.surfaceVariant,
            counterText: '',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          ),
        ),
      );
    }
    final motivation = goal.motivation;
    if (motivation == null || motivation.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: const Border(
              left: BorderSide(color: Color(0xFFFF9500), width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.format_quote_rounded,
                size: 16, color: Color(0xFFFF9500)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                motivation,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: colors.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Секция числовой цели: настройка или карточка с прогрессом и графиком.
  Widget _buildMetricSection(GoalModel goal) {
    final colors = AppColors.of(context);
    final editable = !goal.isSaved || _isEditMode;
    final metric = goal.metric;
    const accent = Color(0xFF34AADC);
    if (metric == null) {
      // Числовую цель предлагаем, пока нет задач по датам.
      if (!editable || goal.dates.any((d) => d.tasks.isNotEmpty)) {
        return const SizedBox.shrink();
      }
      return _glassCard(
        margin: const EdgeInsets.only(bottom: 24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showMetricSetupDialog(),
            child: Row(
              children: [
                Icon(Icons.insights_rounded, size: 22, color: colors.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Сделать числовой целью'),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr('Накопить, прочитать, сбросить…'),
                        style: TextStyle(
                            fontSize: 13, color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textTertiary),
              ],
            ),
          ),
        ),
      );
    }
    final unit = metric.unit.isNotEmpty ? ' ${metric.unit}' : '';
    final pct = (metric.progress * 100).round();
    return _glassCard(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up_rounded, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(
                  tr('Прогресс к цели'),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary),
                ),
                const Spacer(),
                if (editable)
                  GestureDetector(
                    onTap: () => _showMetricSetupDialog(existing: metric),
                    child: Icon(Icons.tune_rounded,
                        size: 18, color: colors.textTertiary),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _fmtMetric(metric.currentValue),
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary),
                ),
                Text(
                  unit,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '/ ${_fmtMetric(metric.targetValue)}$unit',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textTertiary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$pct%',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: accent),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: metric.progress,
                minHeight: 8,
                backgroundColor: colors.textPrimary.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation(accent),
              ),
            ),
            if (metric.history.isNotEmpty || goal.deadline != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 120,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _MetricChart(
                    metric: metric,
                    createdAt: goal.savedAt ?? goal.createdAt,
                    deadline: goal.deadline,
                    lineColor: accent,
                    idealColor: colors.textTertiary,
                    gridColor: colors.textPrimary.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                _metricStepButton(
                    Icons.remove, () => _adjustMetric(-_metricStep(metric))),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _showMetricValueDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border, width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_rounded, size: 15, color: colors.icon),
                          const SizedBox(width: 6),
                          Text(
                            tr('Ввести значение'),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _metricStepButton(
                    Icons.add, () => _adjustMetric(_metricStep(metric))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricStepButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF34AADC).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF34AADC)),
      ),
    );
  }

  Widget _buildMilestonesSection(GoalModel goal) {
    final colors = AppColors.of(context);
    final editable = !goal.isSaved || _isEditMode;
    // Прячем секцию, если вех нет и редактирование выключено.
    if (goal.milestones.isEmpty && !editable) return const SizedBox.shrink();
    return _glassCard(
      margin: const EdgeInsets.only(bottom: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_rounded, size: 22, color: colors.icon),
                const SizedBox(width: 8),
                Text(
                  tr('Вехи'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (goal.milestones.isNotEmpty)
                  Text(
                    '${goal.completedMilestones}/${goal.milestones.length}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
            if (goal.milestones.isEmpty && editable) ...[
              const SizedBox(height: 8),
              Text(
                tr('Отметьте крупные этапы на пути к цели'),
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ],
            if (goal.milestones.isNotEmpty) const SizedBox(height: 14),
            ...goal.milestones.map(
              (m) => _buildMilestoneTile(m, editable),
            ),
            if (editable) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showAddMilestoneDialog,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(
                    color: colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border, width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16, color: colors.icon),
                      const SizedBox(width: 8),
                      Text(
                        tr('Добавить веху'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneTile(GoalMilestone m, bool editable) {
    final colors = AppColors.of(context);
    const accent = Color(0xFF34C759);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _toggleMilestone(m.id),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: m.isCompleted ? accent : colors.border,
                  width: 2,
                ),
                color: m.isCompleted ? accent : Colors.transparent,
              ),
              child: m.isCompleted
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              m.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: m.isCompleted ? colors.textTertiary : colors.textPrimary,
                decoration:
                    m.isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (editable) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _deleteMilestone(m.id),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 17,
                  height: 17,
                  child: ColorFiltered(
                    colorFilter:
                        ColorFilter.mode(colors.textSecondary, BlendMode.srcIn),
                    child: Image.asset(
                      'assets/icon/trash.png',
                      cacheWidth: 68,
                      cacheHeight: 68,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addButton() {
    final colors = AppColors.of(context);
    return SizedBox(
      key: _addButtonKey,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _showAddMenu,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
              tr('Добавить'),
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

  // Выпадающее меню кнопки «Добавить» — тот же стиль, что у меню блока
  // на таймлайне (BackdropFilter + fade/scale, без затемнения фона).
  void _showAddMenu() {
    _removeAddMenuOverlay();
    HapticFeedback.lightImpact();
    final overlay = Overlay.of(context);
    final box =
        _addButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.of(context).size;
    const menuWidth = 220.0;
    const menuHeight = 108.0;
    // Меню «вырастает» вверх от кнопки; если сверху мало места — вниз.
    double left = origin.dx;
    if (left + menuWidth > screen.width - 12) {
      left = screen.width - menuWidth - 12;
    }
    left = left.clamp(12.0, screen.width - menuWidth - 12);
    final hasRoomAbove = origin.dy - menuHeight - 8 > MediaQuery.of(context).padding.top;
    final double top = hasRoomAbove
        ? origin.dy - menuHeight - 8
        : origin.dy + size.height + 8;
    _addMenuOverlayEntry = OverlayEntry(
      builder: (context) => _AddMenuOverlay(
        position: Offset(left, top),
        width: menuWidth,
        alignment: hasRoomAbove ? Alignment.bottomLeft : Alignment.topLeft,
        onClose: _removeAddMenuOverlay,
        onDate: () {
          _removeAddMenuOverlay();
          _showAddDateDialog();
        },
        onTask: () {
          _removeAddMenuOverlay();
          _addTaskWithoutDate();
        },
      ),
    );
    overlay.insert(_addMenuOverlayEntry!);
  }

  void _removeAddMenuOverlay() {
    _addMenuOverlayEntry?.remove();
    _addMenuOverlayEntry = null;
  }

  // Создаёт (при необходимости) контейнер задач без даты и открывает шторку.
  void _addTaskWithoutDate() {
    final goal = _activeGoal;
    if (goal == null) return;
    final dateless = goal.dates.where((d) => d.date == null).toList();
    String dateId;
    if (dateless.isEmpty) {
      dateId = _uuid.v4();
      final updated = goal.copyWith(
          dates: [...goal.dates, GoalDate(id: dateId, date: null, tasks: [])]);
      _updateActiveGoal(updated);
      _persistIfSaved(updated);
    } else {
      dateId = dateless.first.id;
    }
    _showAddTaskDialog(dateId);
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
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border, width: 1),
              color: colors.elevatedSurface,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  onMenu: (pos) => _handleGoalMenuToggle(g, pos),
                  confirmDelete: () => _confirmDeleteGoal(g),
                  onDelete: () => _deleteGoal(g),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

}

// Данные текущего празднования (веха / победа первой недели).
class _Celebration {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  const _Celebration({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
  });
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
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: GlassPanel(
        borderRadius: 18,
        settings: AppGlass.panel,
        child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  date.date != null ? _formatDate(date.date!) : tr('Задачи'),
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
  final void Function(Offset position) onMenu;
  final Future<bool> Function() confirmDelete;
  final VoidCallback onDelete;

  const _SavedCard({
    required this.goal,
    required this.progress,
    required this.onOpen,
    required this.onMenu,
    required this.confirmDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final card = GestureDetector(
      onTap: onOpen,
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        onMenu(details.globalPosition);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: GlassPanel(
        borderRadius: 20,
        settings: AppGlass.panel,
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
                        if (goal.deadline != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.flag_rounded,
                                  size: 13, color: colors.textTertiary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _deadlineSubtitle(goal),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // На месте кнопки удаления — счётчик дат и задач.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        goal.metric != null
                            ? '${_fmtMetricValue(goal.metric!.currentValue)} / ${_fmtMetricValue(goal.metric!.targetValue)}${goal.metric!.unit.isNotEmpty ? ' ${goal.metric!.unit}' : ''}'
                            : tr('{0} {1} • {2} {3}', [goal.dates.length, _getDateWord(goal.dates.length), goal.totalTasks, _getTaskWord(goal.totalTasks)]),
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                      if (goal.deadline != null) ...[
                        const SizedBox(height: 10),
                        _goalPaceBadge(context, goal),
                      ],
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
      ),
    );

    // Свайп справа налево удаляет цель (с подтверждением).
    return Dismissible(
      key: ValueKey('dismiss_goal_${goal.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDelete(),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        onDelete();
      },
      background: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.delete_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
      child: card,
    );
  }
}

// Контекстное меню цели в Overlay (Редактировать / Поделиться / Удалить).
// График числовой цели: пунктирная идеальная линия старт→цель к дедлайну
// и сплошная фактическая полилиния по истории значений.
class _MetricChart extends CustomPainter {
  final GoalMetric metric;
  final DateTime createdAt;
  final DateTime? deadline;
  final Color lineColor;
  final Color idealColor;
  final Color gridColor;

  _MetricChart({
    required this.metric,
    required this.createdAt,
    required this.deadline,
    required this.lineColor,
    required this.idealColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final values = <double>[
      metric.startValue,
      metric.targetValue,
      metric.currentValue,
      ...metric.history.map((e) => e.value),
    ];
    var minV = values.reduce(math.min);
    var maxV = values.reduce(math.max);
    if (minV == maxV) {
      minV -= 1;
      maxV += 1;
    }
    final padV = (maxV - minV) * 0.1;
    minV -= padV;
    maxV += padV;

    final start = DateTime(createdAt.year, createdAt.month, createdAt.day);
    DateTime end;
    if (deadline != null) {
      end = deadline!;
    } else {
      end = metric.history.isNotEmpty
          ? metric.history.last.date
          : start.add(const Duration(days: 1));
    }
    if (!end.isAfter(start)) end = start.add(const Duration(days: 1));
    final totalMs = end.difference(start).inMilliseconds.toDouble();

    double dx(DateTime d) {
      final ms = d
          .difference(start)
          .inMilliseconds
          .toDouble()
          .clamp(0.0, totalMs);
      return totalMs == 0 ? 0 : (ms / totalMs) * size.width;
    }

    double dy(double v) =>
        size.height - ((v - minV) / (maxV - minV)) * size.height;

    // Сетка.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height / 3 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Идеальная линия (пунктир).
    final idealPaint = Paint()
      ..color = idealColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _drawDashedLine(
      canvas,
      Offset(dx(start), dy(metric.startValue)),
      Offset(dx(end), dy(metric.targetValue)),
      idealPaint,
    );

    // Фактическая полилиния.
    final points = <Offset>[Offset(dx(start), dy(metric.startValue))];
    for (final e in metric.history) {
      points.add(Offset(dx(e.date), dy(e.value)));
    }
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (final pt in points) {
      canvas.drawCircle(pt, 3, dotPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * math.min(d + dash, total);
      canvas.drawLine(s, e, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MetricChart old) => true;
}

class _GoalMenuOverlay extends StatefulWidget {
  final Offset position;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _GoalMenuOverlay({
    required this.position,
    required this.onClose,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  @override
  State<_GoalMenuOverlay> createState() => _GoalMenuOverlayState();
}

class _GoalMenuOverlayState extends State<_GoalMenuOverlay>
    with SingleTickerProviderStateMixin {
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
                  elevation: colors.isDark ? 0 : 10,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(18),
                  child: GestureDetector(
                    onTap: () {},
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        alignment: Alignment.topRight,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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

// Выпадающее меню кнопки «Добавить» (Дату / Задачу) — стиль меню таймлайна.
class _AddMenuOverlay extends StatefulWidget {
  final Offset position;
  final double width;
  final Alignment alignment;
  final VoidCallback onClose;
  final VoidCallback onDate;
  final VoidCallback onTask;

  const _AddMenuOverlay({
    required this.position,
    required this.width,
    required this.alignment,
    required this.onClose,
    required this.onDate,
    required this.onTask,
  });

  @override
  State<_AddMenuOverlay> createState() => _AddMenuOverlayState();
}

class _AddMenuOverlayState extends State<_AddMenuOverlay>
    with SingleTickerProviderStateMixin {
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
                  elevation: colors.isDark ? 0 : 10,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(18),
                  child: GestureDetector(
                    onTap: () {},
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        alignment: widget.alignment,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                                width: widget.width,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildMenuItem(
                                      Icons.event_rounded,
                                      tr('Дату'),
                                      () => _close(widget.onDate),
                                    ),
                                    _buildMenuDivider(),
                                    _buildMenuItem(
                                      Icons.check_circle_outline_rounded,
                                      tr('Задачу'),
                                      () => _close(widget.onTask),
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
