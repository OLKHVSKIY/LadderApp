import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/bottom_navigation.dart';
import '../widgets/sidebar.dart';
import '../widgets/swipeable_page_route.dart';
import '../widgets/swipe_down_sheet.dart';
import 'tasks_page.dart';
import 'plan_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import '../data/repositories/task_repository.dart';
import '../data/database_instance.dart';
import '../models/task.dart' as model;
import '../widgets/note_create_modal.dart';
import '../widgets/task_create_modal.dart';
import '../widgets/pomodoro_timer.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/habit_repository.dart';
import '../data/repositories/event_repository.dart';
import '../models/habit.dart';
import '../models/event.dart';
import '../models/note_model.dart';
import '../services/notification_service.dart';
import '../data/user_session.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';
import 'dart:convert';

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

class ListPage extends StatefulWidget {
  const ListPage({super.key});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> with TickerProviderStateMixin {
  bool _isSidebarOpen = false;
  double _previousKeyboardHeight = 0.0;
  
  ListViewType _listViewType = ListViewType.oneDay;
  TimeStep _timeStep = TimeStep.tenMinutes;
  DateTime _selectedDate = DateTime.now();
  DateTime? _previousSelectedDate;
  double _weekSwipeDistance = 0.0; // Для обработки свайпов по заголовку недели
  double _daySwipeDistance = 0.0; // Смещение контента дня/месяца при свайпе
  
  late final ScrollController _dayContentScrollController;
  late final ScrollController _weekScrollController;
  
  DateTime _currentTime = DateTime.now();
  Timer? _timeUpdateTimer;
  double _currentScrollOffset = 0.0;
  // Таймлайн проявляется только после первичного автоскролла к текущему
  // времени — иначе при открытии страницы видно, как контент «дёргается» вверх
  // (сначала рисуется в позиции 00:00, затем прыгает к текущему часу).
  bool _initialScrollDone = false;

  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  // Раскрытие/сворачивание поиска — единый обратимый цикл: одна анимация
  // управляет и шириной поля, и проявлением содержимого, поэтому открытие и
  // закрытие выглядят живо и плавно и могут прерывать друг друга на лету.
  late final AnimationController _searchAnimController;
  late final Animation<double> _searchAnim;
  
  TaskRepository? _taskRepository;
  List<model.Task> _monthTasks = [];
  
  NoteRepository? _noteRepository;
  NoteRepository get noteRepository {
    _noteRepository ??= NoteRepository(appDatabase);
    return _noteRepository!;
  }
  
  // Переменные для режима прикрепления заметки
  bool _isNoteModalOpen = false;
  bool _isAttachingNote = false;
  String? _attachingNoteTitle;
  String? _attachingNoteColor;
  String? _attachingNoteIcon;
  String? _attachingNoteLinkedElementType;
  String? _attachingNoteLinkedElementId;
  DateTime? _attachingNoteStartTime;
  DateTime? _attachingNoteEndTime;
  bool _attachingNoteNotify = true; // Уведомлять о начале события
  double _attachingNoteHeight = 0.0;
  double _attachingNoteWidth = 0.0; // Ширина заметки (от левого края)
  // Экранная Y-позиция верха заметки (относительно верха шкалы) во время
  // перетаскивания: заметка едет за пальцем, а время пересчитывается из неё.
  double _dragNoteScreenY = 0.0;
  double _previousNoteHeight = 0.0; // Для отслеживания изменения размера для вибрации
  Timer? _autoScrollTimer; // Таймер плавного автоскролла у краёв при перетаскивании
  bool _isDraggingNote = false; // Флаг перетаскивания заметки
  
  // Сохраненные заметки списка
  List<Map<String, dynamic>> _timelineNotes = [];
  
  // Состояние для меню заметок при long press
  OverlayEntry? _noteMenuOverlayEntry;
  
  // Состояние для редактирования заметки
  String? _editingNoteId;
  bool _isEditingNote = false;
  
  TaskRepository get taskRepository {
    _taskRepository ??= TaskRepository(appDatabase);
    return _taskRepository!;
  }

  HabitRepository? _habitRepository;
  HabitRepository get habitRepository {
    _habitRepository ??= HabitRepository(appDatabase);
    return _habitRepository!;
  }

  EventRepository? _eventRepository;
  EventRepository get eventRepository {
    _eventRepository ??= EventRepository(appDatabase);
    return _eventRepository!;
  }

  // Шторка создания задачи/привычки/события (как на странице «Задачи»).
  bool _isCreateModalOpen = false;

  // Привычки и события для верхней ленты «на весь день» над таймлайном.
  // Грузятся один раз, фильтруются по выбранному дню в build (isActiveOn /
  // occursOn), поэтому при листании дней перезагрузка не нужна.
  List<HabitWithStats> _habits = [];
  List<Event> _allEvents = [];

  @override
  void initState() {
    super.initState();
    _dayContentScrollController = ScrollController();
    _weekScrollController = ScrollController();
    _searchAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
      reverseDuration: const Duration(milliseconds: 360),
    );
    _searchAnim = CurvedAnimation(
      parent: _searchAnimController,
      // Гладкое раскрытие/закрытие. Живость (лёгкий «pop») добавляем отдельно —
      // масштабом содержимого, чтобы ширина поля не «перелетала» за край.
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _previousSelectedDate = _selectedDate;
    _currentTime = DateTime.now();
    // Загружаем сохраненные настройки
    _loadSettings().then((_) {
      if (mounted && _listViewType == ListViewType.month) {
        _loadMonthTasks();
      }
      _loadTimelineNotes();
      _loadDayExtras();

      // Автоскролл к текущему времени при открытии страницы
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentTime();
      });
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
    final timeStepIndex = prefs.getInt('timeStep') ?? 1; // По умолчанию 10 минут (индекс 1)
    
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

  void _scrollToCurrentTime() {
    if (!mounted) return;
    
    final currentTimePosition = _getCurrentTimePosition(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final targetOffset = (currentTimePosition - screenHeight / 2).clamp(0.0, double.infinity);
    
    if (_listViewType == ListViewType.oneDay && _dayContentScrollController.hasClients) {
      _dayContentScrollController.jumpTo(targetOffset);
    } else if (_listViewType == ListViewType.week && _weekScrollController.hasClients) {
      _weekScrollController.jumpTo(targetOffset);
    }

    // Контент уже спозиционирован — плавно проявляем таймлайн.
    if (mounted && !_initialScrollDone) {
      setState(() {
        _initialScrollDone = true;
      });
    }
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
    _autoScrollTimer?.cancel();
    _searchAnimController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeNoteMenuOverlay();
    super.dispose();
  }

  void _handleNoteLongPress(BuildContext context, String? noteId,
      [Offset? pressPosition]) {
    if (noteId == null) return;

    HapticFeedback.heavyImpact();
    _showNoteMenuOverlay(context, noteId, pressPosition);
  }

  void _showNoteMenuOverlay(BuildContext context, String noteId,
      [Offset? pressPosition]) {
    _removeNoteMenuOverlay();

    final overlay = Overlay.of(context);

    _noteMenuOverlayEntry = OverlayEntry(
      builder: (context) => _NoteMenuOverlay(
        pressPosition: pressPosition,
        onClose: _removeNoteMenuOverlay,
        onEdit: () {
          _removeNoteMenuOverlay();
          _startEditingNote(noteId);
        },
        onPomodoro: () {
          _removeNoteMenuOverlay();
          _showPomodoro(noteId);
        },
        onDelete: () async {
          _removeNoteMenuOverlay();
          final intNoteId = int.tryParse(noteId);
          if (intNoteId == null) return;
          
          HapticFeedback.heavyImpact();
          try {
            await noteRepository.deleteNote(intNoteId);
            await NotificationService.instance.cancelNoteReminder(intNoteId);
            await _loadTimelineNotes();
          } catch (e) {
            debugPrint('Ошибка удаления заметки: $e');
          }
        },
      ),
    );
    
    overlay.insert(_noteMenuOverlayEntry!);
  }

  void _removeNoteMenuOverlay() {
    _noteMenuOverlayEntry?.remove();
    _noteMenuOverlayEntry = null;
  }

  // Открыть Pomodoro-таймер для выбранной заметки.
  void _showPomodoro(String noteId) {
    final note = _timelineNotes.firstWhere(
      (note) => note['id']?.toString() == noteId,
      orElse: () => {},
    );
    if (note.isEmpty) return;
    final title = note['title'] as String? ?? '';
    final color = _getColorFromHex(note['color'] as String? ?? '#FFEB3B');

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, _, _) => PomodoroTimer(
        noteTitle: title,
        accentColor: color,
      ),
    );
  }

  void _startEditingNote(String noteId) {
    final note = _timelineNotes.firstWhere(
      (note) => note['id']?.toString() == noteId,
      orElse: () => {},
    );
    
    if (note.isEmpty) return;
    
    final startTime = note['startTime'] as DateTime?;
    final endTime = note['endTime'] as DateTime?;
    final title = note['title'] as String?;
    final color = note['color'] as String? ?? '#FFEB3B';
    final icon = note['icon'] as String?;
    
    if (startTime == null || endTime == null || title == null) return;
    
    setState(() {
      _editingNoteId = noteId;
      _isEditingNote = true;
      _isAttachingNote = true;
      _attachingNoteTitle = title;
      _attachingNoteColor = color;
      _attachingNoteIcon = icon;
      _attachingNoteStartTime = startTime;
      _attachingNoteEndTime = endTime;
      _attachingNoteNotify = note['notify'] as bool? ?? true;

      // Вычисляем высоту и ширину на основе времени
      final hourHeight = _getHourHeight(context);
      final linesPerHour = _getTimeLinesCount();
      final lineHeight = hourHeight / linesPerHour;
      final minutesPerLine = _getMinutesPerLine();
      final duration = endTime.difference(startTime);
      _attachingNoteHeight = (duration.inMinutes / minutesPerLine) * lineHeight;
      _attachingNoteWidth = MediaQuery.of(context).size.width - 61; // Ширина минус отступ блока времени
    });

    // Переключаемся на день заметки, если он не выбран
    if (!_isSameDay(_selectedDate, startTime)) {
      setState(() {
        _selectedDate = startTime;
      });
    }
    
    // Автоскролл к заметке
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notePosition = _getTimePositionForDateTime(context, startTime, _selectedDate);
      final screenHeight = MediaQuery.of(context).size.height;
      final targetOffset = (notePosition - screenHeight / 2).clamp(0.0, double.infinity);
      
      if (_listViewType == ListViewType.oneDay && _dayContentScrollController.hasClients) {
        _dayContentScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _cancelEditingNote() {
    setState(() {
      _editingNoteId = null;
      _isEditingNote = false;
    });
    _cancelAttachingNote();
  }

  // Тап по блоку заметки на таймлайне → шторка просмотра/редактирования
  // (полный текст, описание, время; смена цвета, иконки, текста).
  void _showTimelineNoteSheet(String? noteId) {
    if (noteId == null) return;
    final note = _timelineNotes.firstWhere(
      (n) => n['id']?.toString() == noteId,
      orElse: () => {},
    );
    if (note.isEmpty) return;
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            24,
      ),
      builder: (ctx) => _TimelineNoteSheet(
        title: note['title'] as String? ?? '',
        description: note['description'] as String? ?? '',
        colorHex: note['color'] as String? ?? '#FFEB3B',
        iconKey: note['icon'] as String?,
        startTime: note['startTime'] as DateTime,
        endTime: note['endTime'] as DateTime,
        onSave: (title, description, colorHex, iconKey) {
          Navigator.of(ctx).pop();
          _updateTimelineNote(
              noteId, title, description, colorHex, iconKey, note);
        },
      ),
    );
  }

  Future<void> _updateTimelineNote(String noteId, String title,
      String description, String colorHex, String? iconKey,
      Map<String, dynamic> note) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final intNoteId = int.tryParse(noteId);
    if (intNoteId == null) return;
    final noteData = {
      'type': 'timeline',
      'startTime': (note['startTime'] as DateTime).toIso8601String(),
      'endTime': (note['endTime'] as DateTime).toIso8601String(),
      'color': colorHex,
      'icon': iconKey,
      'description': description,
      'linkedElementType': note['linkedElementType'],
      'linkedElementId': note['linkedElementId'],
      'notify': note['notify'] ?? true,
      // Сохраняем флаг «на весь день», иначе после редактирования заметка
      // теряет статус и уезжает из верхней ленты в тело таймлайна.
      'allDay': note['allDay'] ?? false,
    };
    try {
      final notes = await noteRepository.loadNotes(userId);
      final existing = notes.firstWhere((n) => n.id == intNoteId,
          orElse: () => throw Exception('Заметка не найдена'));
      final updated = NoteModel(
        id: intNoteId,
        title: title,
        content: jsonEncode(noteData),
        x: existing.x,
        y: existing.y,
        width: existing.width,
        height: existing.height,
        color: colorHex,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
        isLocked: existing.isLocked,
        drawingData: existing.drawingData,
        attachedFiles: existing.attachedFiles,
      );
      await noteRepository.saveNote(updated, userId);
      await _loadTimelineNotes();
    } catch (e) {
      debugPrint('Ошибка обновления заметки: $e');
    }
  }

  Future<void> _saveEditingNote() async {
    if (_editingNoteId == null || _attachingNoteTitle == null || 
        _attachingNoteStartTime == null || _attachingNoteEndTime == null) {
      _cancelEditingNote();
      return;
    }

    final userId = UserSession.currentUserId;
    if (userId == null) {
      _cancelEditingNote();
      return;
    }

    final intNoteId = int.tryParse(_editingNoteId!);
    if (intNoteId == null) {
      _cancelEditingNote();
      return;
    }

    try {
      // Создаем JSON структуру для заметки списка
      final noteData = {
        'type': 'timeline',
        'startTime': _attachingNoteStartTime!.toIso8601String(),
        'endTime': _attachingNoteEndTime!.toIso8601String(),
        'color': _attachingNoteColor ?? '#FFEB3B',
        'icon': _attachingNoteIcon,
        'linkedElementType': _attachingNoteLinkedElementType,
        'linkedElementId': _attachingNoteLinkedElementId,
        'notify': _attachingNoteNotify,
      };

      // Загружаем существующую заметку
      final notes = await noteRepository.loadNotes(userId);
      final existingNote = notes.firstWhere(
        (note) => note.id == intNoteId,
        orElse: () => throw Exception('Заметка не найдена'),
      );

      // Обновляем заметку
      final updatedNote = NoteModel(
        id: intNoteId,
        title: _attachingNoteTitle!,
        content: jsonEncode(noteData),
        x: existingNote.x,
        y: existingNote.y,
        width: existingNote.width,
        height: existingNote.height,
        color: _attachingNoteColor ?? '#FFEB3B',
        createdAt: existingNote.createdAt,
        updatedAt: DateTime.now(),
        isLocked: existingNote.isLocked,
        drawingData: existingNote.drawingData,
        attachedFiles: existingNote.attachedFiles,
      );

      await noteRepository.saveNote(updatedNote, userId);
      // Перепланируем уведомление на (новое) время начала заметки, если
      // уведомления включены; иначе отменяем ранее запланированное.
      if (_attachingNoteNotify) {
        await NotificationService.instance.scheduleNoteReminder(
          id: intNoteId,
          title: _attachingNoteTitle!,
          startTime: _attachingNoteStartTime!,
        );
      } else {
        await NotificationService.instance.cancelNoteReminder(intNoteId);
      }
      await _loadTimelineNotes();
    } catch (e) {
      debugPrint('Ошибка сохранения редактируемой заметки: $e');
    }

    _cancelEditingNote();
  }

  void _toggleSidebar() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }

  void _navigateTo(Widget page, {bool slideFromRight = false}) {
    if (page is SettingsPage || page is ChatPage) {
      // Нативный iOS-переход (свайп-назад без артефактов).
      Navigator.of(context).push(
        SwipeablePageRoute(
          builder: (_) => page,
        ),
      );
    } else {
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
  // Цвет часовых полос шкалы. На светлой теме чуть темнее colors.border,
  // чтобы расчерченные линии лучше читались.
  Color _gridHourLineColor(AppColors colors) =>
      colors.isDark ? colors.border : const Color(0xFFD6D6D6);

  // Цвет промежуточных полос и вертикальных разделителей шкалы.
  // На светлой теме чуть темнее colors.divider.
  Color _gridLineColor(AppColors colors) =>
      colors.isDark ? colors.divider : const Color(0xFFDCDCDC);

  double _getHourHeight(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    // viewPadding (не padding) — не меняется при открытии клавиатуры, иначе
    // высота часа «прыгала» при фокусе поиска и индикатор времени уезжал.
    final topPadding = MediaQuery.of(context).viewPadding.top - 10;
    final sliderHeight = 60.0; // Высота слайдера дней
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom + 75 + 60; // Навигация и кнопки
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

  // Индикатор текущего времени: красная линия + красная метка с текущим
  // временем слева (как в календаре iOS). Красный одинаков в обеих темах.
  Widget _buildCurrentTimeIndicator() {
    const redColor = Color(0xFFFF3B30);
    final timeText =
        '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      height: 1.0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Метка + линия в Row → линия ровно по центру овала и в упор к нему.
          // Овал центрируется по линии текущего времени (top: -высота/2).
          Positioned(
            left: 11,
            right: 0,
            top: -8.5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: redColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    timeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1.5,
                    color: redColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    final days = [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')];
    return days[weekday - 1];
  }

  Widget _buildWeekDaysHeader() {
    final weekDates = _getWeekDates();
    final screenWidth = MediaQuery.of(context).size.width;
    // Ограничиваем смещение, чтобы не было слишком сильного сдвига
    final clampedSwipeDistance = _weekSwipeDistance.clamp(-screenWidth * 0.3, screenWidth * 0.3);
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutQuart,
      transform: Matrix4.translationValues(clampedSwipeDistance, 0, 0),
      child: Container(
          padding: const EdgeInsets.only(left: 55, right: 16, top: 12, bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekDates.map((date) {
              // Выделяем только текущий день (сегодня), а не выбранный день
              final isSelected = _isSameDay(date, DateTime.now());
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
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.of(context).inverseSurface : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getDayName(date.weekday),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? AppColors.of(context).onInverseSurface : AppColors.of(context).textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Дата
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                          color: isSelected ? AppColors.of(context).textPrimary : AppColors.of(context).textSecondary,
                        ),
                        child: Text(
                          date.day.toString().padLeft(2, '0'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
    );
  }


  void _openSearch() {
    setState(() {
      _isSearchOpen = true;
    });
    _searchAnimController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    FocusScope.of(context).unfocus();
    // Сворачиваем поле обратной анимацией; флаги сбрасываем, когда она
    // завершилась, чтобы закрытие тоже было плавным, а не мгновенным.
    _searchAnimController.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _isSearchOpen = false;
        _searchController.clear();
      });
    });
  }

  /// Поиск блока-заметки на таймлайне по названию. По Enter находим
  /// подходящий блок (ближайший по времени к «сейчас»), переключаемся на его
  /// день и плавно прокручиваем шкалу к нему.
  void _performSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      _closeSearch();
      return;
    }

    final matches = _timelineNotes.where((note) {
      final title = (note['title'] as String?)?.toLowerCase() ?? '';
      return title.contains(q);
    }).toList();

    if (matches.isEmpty) {
      // Ничего не нашли — лёгкая вибрация, поле оставляем открытым.
      HapticFeedback.lightImpact();
      return;
    }

    // Из совпадений берём ближайшее по времени к текущему моменту.
    final now = DateTime.now();
    matches.sort((a, b) {
      final da = (a['startTime'] as DateTime).difference(now).abs();
      final db = (b['startTime'] as DateTime).difference(now).abs();
      return da.compareTo(db);
    });
    final startTime = matches.first['startTime'] as DateTime;

    FocusScope.of(context).unfocus();
    setState(() {
      _previousSelectedDate = _selectedDate;
      _selectedDate = DateTime(startTime.year, startTime.month, startTime.day);
      // Месячный вид не умеет прокручиваться к блоку — переключаемся на день.
      if (_listViewType == ListViewType.month) {
        _listViewType = ListViewType.oneDay;
      }
    });
    // Плавно сворачиваем поле поиска после успешного перехода.
    _searchAnimController.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _isSearchOpen = false;
        _searchController.clear();
      });
    });

    HapticFeedback.lightImpact();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final position =
          _getTimePositionForDateTime(context, startTime, _selectedDate);
      final screenHeight = MediaQuery.of(context).size.height;
      final target = (position - screenHeight / 2).clamp(0.0, double.infinity);
      final controller = _listViewType == ListViewType.week
          ? _weekScrollController
          : _dayContentScrollController;
      if (controller.hasClients) {
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _closeNoteModal() {
    setState(() {
      _isNoteModalOpen = false;
    });
  }

  // ===== Шторка создания задачи/привычки/события (как на «Задачи») =====

  void _openCreateModal() {
    setState(() {
      _isCreateModalOpen = true;
    });
  }

  void _closeCreateModal() {
    setState(() {
      _isCreateModalOpen = false;
    });
  }

  // Грузит привычки и события для верхней ленты «на весь день».
  Future<void> _loadDayExtras() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    try {
      final habits =
          await habitRepository.loadHabitsWithStats(userId, _selectedDate);
      final events = await eventRepository.loadAllEvents(userId);
      if (mounted) {
        setState(() {
          _habits = habits;
          _allEvents = events;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки привычек/событий списка: $e');
    }
  }

  DateTime _normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  // Создание задачи в «Мои задачи». Сама шторка дополнительно создаёт
  // заметку-блок на таймлайне «Списка» (синхронизация), поэтому после
  // сохранения просто перезагружаем таймлайн.
  void _addTask(model.Task task, int? screenId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final start = _normalizeDate(task.date);
    final end =
        task.endDate != null ? _normalizeDate(task.endDate!) : start;
    final endDate = end.isBefore(start) ? start : end;
    var day = start;
    var counter = 0;
    try {
      while (!day.isAfter(endDate)) {
        final copy = model.Task(
          id: '${DateTime.now().microsecondsSinceEpoch}-$counter',
          title: task.title,
          description: task.description,
          priority: task.priority,
          tags: task.tags,
          date: day,
          endDate: null,
          isCompleted: false,
          attachedFiles: task.attachedFiles,
        );
        await taskRepository.addTask(copy);
        counter++;
        day = day.add(const Duration(days: 1));
      }
      _closeCreateModal();
      _loadTimelineNotes();
    } catch (_) {
      _closeCreateModal();
    }
  }

  void _saveHabit(Habit habit, int? screenId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    try {
      await habitRepository.addHabit(habit, userId, screenId: screenId);
    } catch (_) {}
    _closeCreateModal();
    _loadDayExtras();
  }

  void _saveEvent(Event event, int? screenId) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    try {
      final eventId =
          await eventRepository.addEvent(event, userId, screenId: screenId);
      await NotificationService.instance.scheduleEventReminders(
        id: eventId,
        title: event.title,
        date: event.date,
        repeatYearly: event.repeatYearly,
        notifyDayBefore: event.notifyDayBefore,
        notifyOnDay: event.notifyOnDay,
      );
    } catch (_) {}
    _closeCreateModal();
    _loadDayExtras();
  }

  void _startAttachingNote(String title, String color, String? icon, String? linkedElementType, String? linkedElementId, bool notify) {
    // Сохраняем данные о связи для последующего сохранения
    _attachingNoteLinkedElementType = linkedElementType;
    _attachingNoteLinkedElementId = linkedElementId;
    _attachingNoteNotify = notify;
    final now = DateTime.now();
    final hourHeight = _getHourHeight(context);
    final linesPerHour = _getTimeLinesCount();
    final lineHeight = hourHeight / linesPerHour;
    
    // Начальная высота блока зависит от шага времени
    double initialHeight;
    switch (_timeStep) {
      case TimeStep.fiveMinutes:
      case TimeStep.tenMinutes:
        initialHeight = lineHeight * 2; // 2 полосы
        break;
      case TimeStep.thirtyMinutes:
      case TimeStep.oneHour:
        initialHeight = lineHeight; // 1 полоса
        break;
    }
    
    // Начальное время — на ВЫБРАННОМ дне (можно создавать заметки на будущие
    // и прошедшие дни), время суток берём от текущего момента.
    final startTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, now.hour, now.minute);
    final endTime = startTime.add(Duration(minutes: (_timeStep == TimeStep.fiveMinutes || _timeStep == TimeStep.tenMinutes) ? 10 : 30));

    setState(() {
      _isNoteModalOpen = false;
      _isAttachingNote = true;
      _attachingNoteTitle = title;
      _attachingNoteColor = color;
      _attachingNoteIcon = icon;
      _attachingNoteStartTime = startTime;
      _attachingNoteEndTime = endTime;
      _attachingNoteHeight = initialHeight;
      _attachingNoteWidth = MediaQuery.of(context).size.width - 61; // Ширина минус отступ блока времени
      _previousNoteHeight = initialHeight;

      // Месячный вид не показывает блок-превью — переключаемся на дневной,
      // но выбранный день сохраняем.
      if (_listViewType == ListViewType.month) {
        _listViewType = ListViewType.oneDay;
      }
    });

    // Автоскролл к месту заметки на выбранном дне.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notePosition = _getTimePositionForDateTime(context, startTime, _selectedDate);
      final target = (notePosition - MediaQuery.of(context).size.height / 2).clamp(0.0, double.infinity);
      if (_listViewType == ListViewType.oneDay && _dayContentScrollController.hasClients) {
        _dayContentScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else if (_listViewType == ListViewType.week && _weekScrollController.hasClients) {
        _weekScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _cancelAttachingNote() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    setState(() {
      _isAttachingNote = false;
      if (_isEditingNote) {
        _isEditingNote = false;
        _editingNoteId = null;
      }
      _attachingNoteTitle = null;
      _attachingNoteColor = null;
      _attachingNoteIcon = null;
      _attachingNoteLinkedElementType = null;
      _attachingNoteLinkedElementId = null;
      _attachingNoteStartTime = null;
      _attachingNoteEndTime = null;
      _attachingNoteHeight = 0.0;
      _attachingNoteWidth = 0.0;
      _previousNoteHeight = 0.0;
      _dragNoteScreenY = 0.0;
      _isDraggingNote = false;
    });
  }

  Future<void> _confirmAttachingNote() async {
    if (_attachingNoteTitle == null || 
        _attachingNoteStartTime == null || 
        _attachingNoteEndTime == null) {
      _cancelAttachingNote();
      return;
    }

    final userId = UserSession.currentUserId;
    if (userId == null) {
      _cancelAttachingNote();
      return;
    }

    try {
      // Создаем JSON структуру для заметки списка
      final noteData = {
        'type': 'timeline', // Тип заметки - для списка
        'startTime': _attachingNoteStartTime!.toIso8601String(),
        'endTime': _attachingNoteEndTime!.toIso8601String(),
        'color': _attachingNoteColor ?? '#FFEB3B',
        'icon': _attachingNoteIcon,
        'linkedElementType': _attachingNoteLinkedElementType,
        'linkedElementId': _attachingNoteLinkedElementId,
        'notify': _attachingNoteNotify,
      };

      // Создаем NoteModel для сохранения
      // Для заметок списка используем x=0, y=0, width=0, height=0 (они не используются)
      final note = NoteModel(
        title: _attachingNoteTitle!,
        content: jsonEncode(noteData),
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        color: _attachingNoteColor ?? '#FFEB3B',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await noteRepository.saveNote(note, userId);
      // Перезагружаем заметки — _loadTimelineNotes сам планирует уведомления
      // для всех заметок с учётом флага «Уведомлять о начале события».
      await _loadTimelineNotes();
    } catch (e) {
      // Обработка ошибки сохранения
      debugPrint('Ошибка сохранения заметки: $e');
    }
    
    // Закрываем режим прикрепления после сохранения
    _cancelAttachingNote();
  }

  Future<void> _loadTimelineNotes() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    try {
      final notes = await noteRepository.loadNotes(userId);
      final timelineNotes = <Map<String, dynamic>>[];
      
      for (final note in notes) {
        try {
          final contentJson = jsonDecode(note.content) as Map<String, dynamic>;
          if (contentJson['type'] == 'timeline') {
            timelineNotes.add({
              'id': note.id,
              'title': note.title,
              'color': contentJson['color'] ?? note.color,
              'icon': contentJson['icon'],
              'description': contentJson['description'] ?? '',
              'startTime': DateTime.parse(contentJson['startTime']),
              'endTime': DateTime.parse(contentJson['endTime']),
              'linkedElementType': contentJson['linkedElementType'],
              'linkedElementId': contentJson['linkedElementId'],
              'notify': contentJson['notify'] ?? true,
              'allDay': contentJson['allDay'] ?? false,
            });
          }
        } catch (e) {
          // Пропускаем некорректные заметки
          continue;
        }
      }
      
      if (mounted) {
        setState(() {
          _timelineNotes = timelineNotes;
        });
      }

      // На КАЖДУЮ будущую заметку планируем своё системное уведомление (id =
      // id заметки → у каждой своё). zonedSchedule с тем же id идемпотентен,
      // поэтому повторная загрузка не плодит дубли. Так уведомления есть и у
      // ранее созданных заметок, и после перезапуска приложения. Если у заметки
      // уведомления выключены — отменяем ранее запланированное.
      for (final note in timelineNotes) {
        final id = note['id'];
        final start = note['startTime'];
        final title = note['title'];
        final notify = note['notify'] as bool? ?? true;
        if (id is int && start is DateTime && title is String) {
          if (notify) {
            await NotificationService.instance.scheduleNoteReminder(
              id: id,
              title: title,
              startTime: start,
            );
          } else {
            await NotificationService.instance.cancelNoteReminder(id);
          }
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки заметок списка: $e');
    }
  }

  IconData? _getIconData(String? iconKey) {
    if (iconKey == null) return null;
    try {
      // Иконки задач (синхронизация со «Списком») — CupertinoIcons.
      if (iconKey.startsWith('cupertino:')) {
        final codePoint = int.parse(iconKey.substring('cupertino:'.length));
        return IconData(codePoint,
            fontFamily: 'CupertinoIcons', fontPackage: 'cupertino_icons');
      }
      final parts = iconKey.split('_');
      if (parts.length == 2) {
        final codePoint = int.parse(parts[1]);
        return IconData(codePoint, fontFamily: 'MaterialIcons');
      }
    } catch (_) {}
    return null;
  }

  Color _getColorFromHex(String? hex) {
    if (hex == null) return Colors.yellow;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.yellow;
    }
  }

  String _formatDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return tr('{0}ч {1}м', [hours, minutes]);
    }
    return tr('{0}м', [minutes]);
  }

  // Пересчитывает время заметки из её текущей экранной позиции с учётом
  // скролла шкалы. Вызывается при перетаскивании и при автоскролле — поэтому
  // время всегда соответствует тому, где заметка реально находится на шкале.
  void _updateDragNoteTimeFromScreenY(BuildContext context) {
    if (_attachingNoteStartTime == null) return;
    final hourHeight = _getHourHeight(context);
    final linesPerHour = _getTimeLinesCount();
    final lineHeight = hourHeight / linesPerHour;
    final minutesPerLine = _getMinutesPerLine();

    final durationMinutes =
        (_attachingNoteHeight / lineHeight * minutesPerLine).round();
    // Абсолютная позиция верха заметки на шкале (без учёта прокрутки экрана).
    final absoluteY = _dragNoteScreenY + _currentScrollOffset;
    // Не даём заметке выйти за пределы суток.
    final maxStartMinutes = (24 * 60 - durationMinutes).clamp(0, 24 * 60);
    var totalMinutes = (absoluteY / lineHeight) * minutesPerLine;
    totalMinutes = totalMinutes.clamp(0.0, maxStartMinutes.toDouble());

    final hours = totalMinutes ~/ 60;
    final minutes = (totalMinutes % 60).floor();
    final start = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, hours, minutes);
    _attachingNoteStartTime = start;
    _attachingNoteEndTime = start.add(Duration(minutes: durationMinutes));
  }

  // Плавный автоскролл шкалы, когда перетаскиваемая заметка подходит к
  // верхнему/нижнему краю видимой области. Сама заметка остаётся под пальцем
  // (её экранная позиция фиксирована), а под ней «уезжает» шкала — время
  // заметки при этом пересчитывается. Таймер живёт, пока палец у края, поэтому
  // скролл продолжается, даже если палец стоит на месте.
  void _checkAutoScroll(BuildContext context) {
    if (_listViewType != ListViewType.oneDay ||
        !_dayContentScrollController.hasClients) {
      return;
    }
    _autoScrollTimer ??=
        Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted ||
          !_isDraggingNote ||
          !_dayContentScrollController.hasClients) {
        timer.cancel();
        _autoScrollTimer = null;
        return;
      }

      final viewportHeight =
          _dayContentScrollController.position.viewportDimension;
      const edgeZone = 130.0; // Зона у края, где включается автоскролл
      const maxSpeed = 14.0; // Макс. скорость скролла (px/тик) у самого края

      final noteTop = _dragNoteScreenY;
      final noteBottom = noteTop + _attachingNoteHeight;

      double direction = 0.0; // -1 вверх (ранее), +1 вниз (позже)
      double intensity = 0.0; // 0..1 — насколько глубоко в зоне
      if (noteTop < edgeZone) {
        direction = -1.0;
        intensity = ((edgeZone - noteTop) / edgeZone).clamp(0.0, 1.0);
      } else if (noteBottom > viewportHeight - edgeZone) {
        direction = 1.0;
        intensity =
            ((noteBottom - (viewportHeight - edgeZone)) / edgeZone).clamp(0.0, 1.0);
      }

      // Вне зоны — останавливаемся (перезапустится при следующем движении).
      if (direction == 0.0) {
        timer.cancel();
        _autoScrollTimer = null;
        return;
      }

      final currentOffset = _dayContentScrollController.offset;
      final maxScroll = _dayContentScrollController.position.maxScrollExtent;
      // Мягкое ускорение к краю (квадратично).
      final speed = maxSpeed * intensity * intensity;
      final target = (currentOffset + direction * speed).clamp(0.0, maxScroll);
      if (target == currentOffset) return; // Упёрлись в край шкалы

      _dayContentScrollController.jumpTo(target);
      setState(() {
        _currentScrollOffset = target;
        _updateDragNoteTimeFromScreenY(context);
      });
    });
  }

  void _openSettings() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.4),
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
    final colors = AppColors.of(context);
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
              child: SwipeDownSheet(
                onDismiss: () => Navigator.of(context).pop(),
                handleHeight: 110,
                child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Material(
                  color: colors.surfaceVariant,
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
                              color: colors.divider,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Заголовок "Вид"
                        Text(
                          tr('Вид'),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Секция "Тип"
                        Text(
                          tr('Тип'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildListViewTypeButton(tr('Один день'), ListViewType.oneDay, 'assets/icon/day-list.png'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildListViewTypeButton(tr('Неделя'), ListViewType.week, 'assets/icon/weeks-list.png'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildListViewTypeButton(tr('Месяц'), ListViewType.month, 'assets/icon/month-list.png'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // Секция "Шаг времени"
                        Text(
                          tr('Шаг времени'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTimeStepButton(tr('5 мин'), TimeStep.fiveMinutes),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTimeStepButton(tr('10 мин'), TimeStep.tenMinutes),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTimeStepButton(tr('30 мин'), TimeStep.thirtyMinutes),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTimeStepButton(tr('1 час'), TimeStep.oneHour),
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
          ),
        ],
      ),
    );
  }

  Widget _buildTimeStepButton(String label, TimeStep step) {
    final isSelected = _timeStep == step;
    final colors = AppColors.of(context);
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
          color: isSelected ? colors.inverseSurface : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? colors.inverseSurface : colors.border,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected ? colors.onInverseSurface : colors.textSecondary,
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
    final colors = AppColors.of(context);
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
              color: isSelected ? colors.inverseSurface : colors.surfaceVariant,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Center(
              child: Image.asset(
                iconPath,
                width: 65,
                height: 65,
                color: isSelected ? colors.onInverseSurface : colors.icon,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    final monthNames = [
      tr('января'), tr('февраля'), tr('марта'), tr('апреля'), tr('мая'), tr('июня'),
      tr('июля'), tr('августа'), tr('сентября'), tr('октября'), tr('ноября'), tr('декабря')
    ];
    return monthNames[month - 1];
  }
    
  // Переход к предыдущему дню/неделе/месяцу (стрелка влево или свайп вправо).
  void _goToPreviousPeriod() {
    HapticFeedback.lightImpact();
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
  }

  // Переход к следующему дню/неделе/месяцу (стрелка вправо или свайп влево).
  void _goToNextPeriod() {
    HapticFeedback.lightImpact();
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
  }

  Widget _buildWeekSlider() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _goToPreviousPeriod,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Icon(CupertinoIcons.chevron_back, color: AppColors.of(context).icon),
          ),
        ),
        Expanded(
          child: Text(
            _listViewType == ListViewType.oneDay
                ? '${_selectedDate.day} ${_getMonthName(_selectedDate.month)}'
                : _listViewType == ListViewType.week
                    ? tr('Неделя {0}.{1}', [_selectedDate.day.toString().padLeft(2, '0'), _selectedDate.month.toString().padLeft(2, '0')])
                    : '${_getMonthName(_selectedDate.month)} ${_selectedDate.year}',
            textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
              fontWeight: FontWeight.w600,
                color: AppColors.of(context).textPrimary,
              ),
            ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _goToNextPeriod,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Icon(CupertinoIcons.chevron_forward, color: AppColors.of(context).icon),
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    // Обновляем заметки при каждом build, если список пуст или при переключении на недельный вид
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_timelineNotes.isEmpty || _listViewType == ListViewType.week)) {
        _loadTimelineNotes();
      }
    });
    
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Вычисляем позицию: когда клавиатура открыта, поднимаем на keyboardHeight - 40, иначе на стандартную позицию
    // Используем max(0, ...) чтобы избежать отрицательных значений и промежуточных состояний
    final bottomPosition = bottomPadding + 75 - 17 + (keyboardHeight > 0 ? (keyboardHeight - 40).clamp(0, double.infinity) : 0);
    
    // Определяем, закрывается ли клавиатура (была открыта, теперь закрыта)
    final isKeyboardClosing = _previousKeyboardHeight > 0 && keyboardHeight == 0;
    _previousKeyboardHeight = keyboardHeight;
    
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top - 10),
            child: _listViewType == ListViewType.week
                ? GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _weekSwipeDistance = 0.0;
                      });
                    },
                    onPanUpdate: (details) {
                      // Обрабатываем только горизонтальные свайпы
                      if (details.delta.dx.abs() > details.delta.dy.abs()) {
                        setState(() {
                          _weekSwipeDistance += details.delta.dx;
                        });
                      }
                    },
                    onPanEnd: (details) {
                      final threshold = 20.0; // Уменьшен порог для более легкого свайпа
                      final velocity = details.velocity.pixelsPerSecond.dx;
                      final shouldSwitch = _weekSwipeDistance.abs() > threshold || velocity.abs() > 150;
                      final swipeDirection = _weekSwipeDistance > 0 || velocity > 0;
                      
                      if (shouldSwitch) {
                        // Сохраняем направление перед сбросом
                        final direction = swipeDirection;
                        
                        // Плавно сбрасываем смещение
                        setState(() {
                          _weekSwipeDistance = 0.0;
                        });
                        
                        HapticFeedback.lightImpact();
                        // Переключаем неделю после небольшой задержки для плавности
                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (mounted) {
                            setState(() {
                              _previousSelectedDate = _selectedDate;
                              if (direction) {
                                // Свайп вправо - предыдущая неделя
                                _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                              } else {
                                // Свайп влево - следующая неделя
                                _selectedDate = _selectedDate.add(const Duration(days: 7));
                              }
                              if (_weekScrollController.hasClients) {
                                _weekScrollController.jumpTo(0);
                              }
                            });
                          }
                        });
                      } else {
                        // Плавно возвращаем на место, если свайп недостаточный
                        setState(() {
                          _weekSwipeDistance = 0.0;
                        });
                      }
                    },
                    behavior: HitTestBehavior.translucent,
                    child: Column(
                      children: [
                        // Заголовок дней недели (только для недельного вида)
                        _buildWeekDaysHeader(),
                        // Основной контент
                        Expanded(
                          child: _buildTimelineView(),
                        ),
                      ],
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    // Горизонтальный свайп листает дни/месяцы; смену страницы
                    // целиком отрисовывает AnimatedSwitcher — без рывков и
                    // мгновенных сбросов. Дистанцию копим без setState, чтобы
                    // во время жеста не перестраивать тяжёлый таймлайн.
                    onHorizontalDragStart: (_) {
                      _daySwipeDistance = 0.0;
                    },
                    onHorizontalDragUpdate: (details) {
                      _daySwipeDistance += details.delta.dx;
                    },
                    onHorizontalDragEnd: (details) {
                      final velocity = details.velocity.pixelsPerSecond.dx;
                      final shouldSwitch =
                          _daySwipeDistance.abs() > 60 || velocity.abs() > 250;
                      final toPrevious = _daySwipeDistance > 0 || velocity > 0;
                      _daySwipeDistance = 0.0;
                      if (shouldSwitch) {
                        if (toPrevious) {
                          _goToPreviousPeriod();
                        } else {
                          _goToNextPeriod();
                        }
                      }
                    },
                    child: Column(
                    children: [
                      // Слайдер дней/недели/месяца (скрыт для недельного вида)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: _buildWeekSlider(),
                      ),
                      // Лента «на весь день»: задачи на весь день, привычки и
                      // события выбранного дня — над таймлайном.
                      _buildAllDayStrip(),
                      // Основной контент
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          // Парный сдвиг: новая страница входит с одной стороны,
                          // старая синхронно уходит в противоположную; обе мягко
                          // подсвечиваются прозрачностью. Направление — по тому,
                          // вперёд или назад во времени меняется дата.
                          transitionBuilder: (child, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) {
                                final goingForward = _previousSelectedDate == null ||
                                    !_previousSelectedDate!.isAfter(_selectedDate);
                                final dir = goingForward ? 1.0 : -1.0;
                                final incoming = animation.status !=
                                        AnimationStatus.reverse &&
                                    animation.status != AnimationStatus.dismissed;
                                final v = animation.value;
                                // incoming: edge → центр; outgoing (v: 1→0): центр → противоположный край.
                                final dx = incoming ? (1 - v) * dir : (1 - v) * -dir;
                                return Opacity(
                                  opacity: v.clamp(0.0, 1.0),
                                  child: FractionalTranslation(
                                    translation: Offset(dx, 0),
                                    child: child,
                                  ),
                                );
                              },
                            );
                          },
                          child: _buildTimelineView(),
                        ),
                      ),
                    ],
                  ),
                  ),
            ),
          // Кнопка поиска с полем ввода (трансформируется из круга в овал)
          AnimatedPositioned(
            duration: isKeyboardClosing ? Duration.zero : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            left: 22,
            bottom: bottomPosition,
            child: GestureDetector(
              onTap: (_isAttachingNote || _isEditingNote) 
                ? (_isEditingNote ? _cancelEditingNote : _cancelAttachingNote)
                : (_isSearchOpen ? null : _openSearch),
              child: AnimatedBuilder(
                animation: _searchAnim,
                builder: (context, _) {
                  // t — прогресс раскрытия (0 — круг-кнопка, 1 — поле во всю ширину).
                  final t = _searchAnim.value.clamp(0.0, 1.0);
                  final fullWidth = MediaQuery.of(context).size.width - 22 - 22 - 52 - 12;
                  final width = lerpDouble(52, fullWidth, t)!;
                  // Иконка исчезает в первой трети, поле проявляется во второй
                  // половине — содержимое не наслаивается и переход «живой».
                  final iconOpacity = (1 - t * 2.4).clamp(0.0, 1.0);
                  final fieldOpacity = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
                  // Лёгкий «pop» поля при появлении.
                  final fieldScale = 0.9 + 0.1 * fieldOpacity;
                  final fieldVisible = _isSearchOpen || t > 0.001;
                  return Container(
                    width: width,
                    height: 52,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: colors.elevatedSurface,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: colors.border, width: 0.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 16 * t),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Иконка-заглушка (видна в свёрнутом состоянии).
                        if (iconOpacity > 0)
                          Opacity(
                            opacity: iconOpacity,
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: !_isAttachingNote
                                  ? ClipRect(
                                      child: SvgPicture.asset(
                                        'assets/icon/glass.svg',
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.contain,
                                        colorFilter: ColorFilter.mode(
                                          colors.icon,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      CupertinoIcons.xmark,
                                      color: colors.icon,
                                      size: 22,
                                    ),
                            ),
                          ),
                        // Поле ввода (проявляется при раскрытии).
                        if (fieldVisible)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Opacity(
                              opacity: fieldOpacity,
                              child: Transform.scale(
                                scale: fieldScale,
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: (fullWidth - 32).clamp(0.0, double.infinity),
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    textInputAction: TextInputAction.search,
                                    onSubmitted: _performSearch,
                                    decoration: InputDecoration(
                                      hintText: tr('Поиск...'),
                                      border: InputBorder.none,
                                      hintStyle:
                                          TextStyle(color: colors.textTertiary),
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    style: TextStyle(
                                        fontSize: 16, color: colors.textPrimary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          AnimatedPositioned(
            duration: isKeyboardClosing ? Duration.zero : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            right: 22,
            bottom: bottomPosition,
            child: GestureDetector(
              onTap: _isSearchOpen
                ? () {
                    FocusScope.of(context).unfocus();
                    _closeSearch();
                  }
                : (_isAttachingNote
                    ? (_isEditingNote ? _saveEditingNote : _confirmAttachingNote)
                    : _openSettings),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.elevatedSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border, width: 0.5),
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
                  // При раскрытом поиске эта кнопка превращается в крестик закрытия.
                  child: _isSearchOpen
                    ? Icon(
                        CupertinoIcons.xmark,
                        color: colors.icon,
                        size: 22,
                      )
                    : (_isAttachingNote || _isEditingNote)
                      ? Icon(
                          Icons.check,
                          color: colors.icon,
                          size: 24,
                        )
                      : ClipRect(
                          child: SvgPicture.asset(
                            'assets/icon/filters.svg',
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                            colorFilter: ColorFilter.mode(
                              colors.icon,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          // Блок с временем между кнопками в режиме прикрепления
          if ((_isAttachingNote || _isEditingNote) && _attachingNoteStartTime != null && _attachingNoteEndTime != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              left: 0,
              right: 0,
              bottom: bottomPosition,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
                  decoration: BoxDecoration(
                    color: colors.inverseSurface,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_attachingNoteStartTime!.hour.toString().padLeft(2, '0')}:${_attachingNoteStartTime!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: colors.onInverseSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '•',
                        style: TextStyle(color: colors.onInverseSurface, fontSize: 12),
                      ),
                    ),
                    Text(
                      _formatDuration(_attachingNoteStartTime!, _attachingNoteEndTime!),
                      style: TextStyle(
                        color: colors.onInverseSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '•',
                        style: TextStyle(color: colors.onInverseSurface, fontSize: 12),
                      ),
                    ),
                    Text(
                      '${_attachingNoteEndTime!.hour.toString().padLeft(2, '0')}:${_attachingNoteEndTime!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: colors.onInverseSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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
            onSettingsTap: () {
              _navigateTo(const SettingsPage(), slideFromRight: true);
            },
          ),
          BottomNavigation(
            currentIndex: 1, // Список
            isSidebarOpen: _isSidebarOpen,
            onAddTask: _openCreateModal,
            onTasksTap: () {
              _navigateTo(const TasksPage(), slideFromRight: false);
            },
            onPlanTap: () {
              _navigateTo(const PlanPage(), slideFromRight: true);
            },
            onGptTap: () {
              // Уже на странице Список
            },
            onAiTap: () {
              _navigateTo(const ChatPage(), slideFromRight: true);
            },
            onIndexChanged: (index) {
              if (index == 0) {
                _navigateTo(const TasksPage(), slideFromRight: false);
              } else if (index == 2) {
                _navigateTo(const PlanPage(), slideFromRight: true);
              } else if (index == 3) {
                _navigateTo(const ChatPage(), slideFromRight: true);
              }
            },
          ),
          // Модальное окно создания заметки
          if (_isNoteModalOpen)
            NoteCreateModal(
              onClose: _closeNoteModal,
              onSave: (note) {
                // TODO: Сохранение заметки
                _closeNoteModal();
              },
              onAttach: _startAttachingNote,
            ),
          // Шторка создания задачи/привычки/события (как на «Задачи»).
          if (_isCreateModalOpen)
            TaskCreateModal(
              onClose: _closeCreateModal,
              onSave: _addTask,
              initialDate: _selectedDate,
              currentScreenId: null, // "Мои задачи"
              onSaveHabit: _saveHabit,
              onSaveEvent: _saveEvent,
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineView() {
    final Widget content;
    final Key key;
    switch (_listViewType) {
      case ListViewType.oneDay:
        key = ValueKey('oneDay_${_selectedDate.year}_${_selectedDate.month}_${_selectedDate.day}');
        content = _buildDayView();
      case ListViewType.week:
        key = ValueKey('week_${_selectedDate.year}_${_selectedDate.month}_${_selectedDate.day}');
        content = _buildWeekView();
      case ListViewType.month:
        key = ValueKey('month_${_selectedDate.year}_${_selectedDate.month}');
        content = _buildMonthView();
    }
    // Плавно проявляем таймлайн после первичного автоскролла к текущему
    // времени. Ключ держим на AnimatedOpacity, чтобы AnimatedSwitcher
    // (листание дней) по-прежнему распознавал смену страницы.
    return AnimatedOpacity(
      key: key,
      opacity: _initialScrollDone ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: content,
    );
  }

  Widget _buildDayView() {
    const hoursInDay = 24;
    final linesPerHour = _getTimeLinesCount();
    final minutesPerLine = _getMinutesPerLine();
    final totalLines = hoursInDay * linesPerHour;
    final hourHeight = _getHourHeight(context);
    final lineHeight = hourHeight / linesPerHour;
    final colors = AppColors.of(context);

    return Container(
      color: colors.background,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification || notification is ScrollEndNotification) {
            setState(() {
              _currentScrollOffset = notification.metrics.pixels;
            });
          }
          return false;
        },
        child: ClipRect(
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
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: _gridHourLineColor(colors), width: 1.0),
                            ),
                          ),
                        ),
                        // Вертикальная линия-разделитель
                        Container(
                          width: 1,
                          height: 1.0,
                          color: _gridHourLineColor(colors),
                        ),
                        // Основной контент (закрывающая полоса)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: _gridHourLineColor(colors), width: 1.0),
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
                              ? Border(
                                  top: BorderSide(color: _gridHourLineColor(colors), width: 1.0),
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
                        style: TextStyle(
                          fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary,
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
                        color: _gridLineColor(colors),
          ),
                      // Основной контент (С промежуточными горизонтальными линиями между ВСЕМИ строками)
          Expanded(
            child: Container(
                    decoration: BoxDecoration(
                            color: colors.background,
                      border: Border(
                              // Темно-серая линия на часах (вверху), серая на промежуточных строках (внизу)
                              // ВКЛЮЧАЯ первую строку после 00:00 (index == 1, minute == 5/10/30, isHourStart == false)
                              top: isHourStart
                                  ? BorderSide(color: _gridHourLineColor(colors), width: 1.0)
                                  : BorderSide(color: _gridLineColor(colors), width: 0.5),
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
            // Сохраненные заметки на таймлайне
            ..._buildSavedTimelineNotes(context, lineHeight),
            // Блок-превью заметки в режиме прикрепления/редактирования
            if ((_isAttachingNote || _isEditingNote) && _attachingNoteStartTime != null && _listViewType == ListViewType.oneDay && _isSameDay(_selectedDate, _attachingNoteStartTime!))
              _buildAttachingNotePreview(context, lineHeight),
            // Индикатор текущего времени (красная линия с меткой времени) - поверх заметок
            // Показываем только для сегодняшнего дня
            // Позиция вычисляется относительно прокрученного контента
            if (_shouldShowCurrentTimeIndicator())
              Positioned(
                top: (_getCurrentTimePosition(context) - _currentScrollOffset).clamp(0.0, double.infinity),
                left: 0,
                right: 0,
                height: 1.0, // Фиксированная высота для Stack
                child: IgnorePointer(
                  child: _buildCurrentTimeIndicator(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Вычисляет позицию заметки по времени начала
  double _getTimePositionForDateTime(BuildContext context, DateTime dateTime, DateTime selectedDate) {
    final hourHeight = _getHourHeight(context);
    final linesPerHour = _getTimeLinesCount();
    final lineHeight = hourHeight / linesPerHour;
    final minutesPerLine = _getMinutesPerLine();
    
    // Вычисляем общее количество минут с начала дня (00:00)
    final totalMinutes = dateTime.hour * 60 + dateTime.minute + dateTime.second / 60.0;
    
    // Вычисляем позицию в пикселях
    final lineIndex = (totalMinutes / minutesPerLine).floor();
    final positionInLine = (totalMinutes % minutesPerLine) / minutesPerLine;
    
    return lineIndex * lineHeight + positionInLine * lineHeight;
  }

  // Горизонтальная лента «на весь день» над таймлайном: задачи на весь день,
  // привычки и события выбранного дня. Скроллится по ширине, если их много.
  Widget _buildAllDayStrip() {
    if (_listViewType != ListViewType.oneDay) return const SizedBox.shrink();
    final day = _selectedDate;
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final chips = <Widget>[];

    // События дня.
    for (final e in _allEvents.where((e) => e.occursOn(day))) {
      chips.add(_allDayChip(
        color: const Color(0xFFFF2D55),
        icon: CupertinoIcons.gift,
        label: e.title,
        onTap: null,
      ));
    }
    // Привычки дня.
    for (final h in _habits.where((h) => h.habit.isActiveOn(day))) {
      chips.add(_allDayChip(
        color: h.habit.color,
        icon: h.habit.icon,
        label: h.habit.title,
        onTap: null,
      ));
    }
    // Задачи «на весь день» (заметки таймлайна с флагом allDay).
    for (final note in _timelineNotes.where((n) {
      if (n['allDay'] != true) return false;
      final s = n['startTime'] as DateTime;
      final en = n['endTime'] as DateTime;
      return s.isBefore(dayEnd) && en.isAfter(dayStart);
    })) {
      final noteId = note['id']?.toString();
      chips.add(_allDayChip(
        color: _getColorFromHex(note['color'] as String?),
        icon: _getIconData(note['icon'] as String?),
        label: note['title'] as String,
        onTap: noteId == null ? null : () => _showTimelineNoteSheet(noteId),
      ));
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: chips.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (int i = 0; i < chips.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      chips[i],
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _allDayChip({
    required Color color,
    IconData? icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: colors.isDark ? 0.22 : 0.13),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Строит виджеты для сохраненных заметок на таймлайне
  List<Widget> _buildSavedTimelineNotes(BuildContext context, double lineHeight) {
    if (_listViewType != ListViewType.oneDay) return [];
    
    // Границы выбранного дня [dayStart, dayEnd). Заметка показывается на этом
    // дне, если её интервал [startTime, endTime) пересекается с днём — так
    // задача, начатая в 23:00 на 4 часа, рисуется и в этот день (23:00→24:00,
    // обрезана снизу), и в следующий (00:00→03:00, перенос).
    final dayStart = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final notes = _timelineNotes.where((note) {
      if (note['allDay'] == true) return false; // на весь день → в верхнюю ленту
      final startTime = note['startTime'] as DateTime;
      final endTime = note['endTime'] as DateTime;
      return startTime.isBefore(dayEnd) && endTime.isAfter(dayStart);
    }).toList();

    final minutesPerLine = _getMinutesPerLine();
    final hourHeight = _getHourHeight(context);
    final linesPerHour = _getTimeLinesCount();
    final lineHeightCalc = hourHeight / linesPerHour;

    return notes.map((note) {
      final noteId = note['id']?.toString();
      final startTime = note['startTime'] as DateTime;
      final endTime = note['endTime'] as DateTime;
      final title = note['title'] as String;
      final colorHex = note['color'] as String? ?? '#FFEB3B';
      final iconKey = note['icon'] as String?;

      // Полная длительность задачи (для подписи) и видимый сегмент в этом дне.
      final duration = endTime.difference(startTime);
      final segStart = startTime.isBefore(dayStart) ? dayStart : startTime;
      final segEnd = endTime.isAfter(dayEnd) ? dayEnd : endTime;
      // Признак «перенос» — сегмент начинается с начала дня (хвост с прошлых
      // суток). И признак обрезки снизу — задача уходит в следующий день.
      final bool isContinuation = startTime.isBefore(dayStart);
      final bool clippedBottom = endTime.isAfter(dayEnd);

      final startPosition =
          _getTimePositionForDateTime(context, segStart, _selectedDate) -
              _currentScrollOffset;
      final height =
          (segEnd.difference(segStart).inMinutes / minutesPerLine) *
              lineHeightCalc;

      // Скрываем заметку, если она полностью выше или ниже видимой области
      final screenHeight = MediaQuery.of(context).size.height;
      if (startPosition + height < 0 || startPosition > screenHeight) {
        return const SizedBox.shrink();
      }

      final color = _getColorFromHex(colorHex);
      final iconData = _getIconData(iconKey);

      return Positioned(
        top: startPosition,
        left: 61,
        right: 0,
        height: height,
        child: _NoteWidget(
          noteId: noteId,
          title: title,
          color: color,
          iconData: iconData,
          iconSize: 24.0, // Не используется, размер вычисляется динамически на основе noteHeight
          noteHeight: height,
          duration: duration,
          isContinuation: isContinuation,
          clippedBottom: clippedBottom,
          onLongPress: (noteId, pos) =>
              _handleNoteLongPress(context, noteId, pos),
          onTap: () => _showTimelineNoteSheet(noteId),
        ),
      );
    }).toList();
  }

  List<Widget> _buildWeekTimelineNotes(BuildContext context, double lineHeight) {
    if (_listViewType != ListViewType.week) return [];
    
    final weekDates = _getWeekDates();
    final screenWidth = MediaQuery.of(context).size.width;
    final timeColumnWidth = 61.0; // 60 (столбец времени) + 1 (вертикальная линия)
    final availableWidth = screenWidth - timeColumnWidth;
    final dayColumnWidth = availableWidth / 7; // Ширина одного столбика дня
    
    final minutesPerLine = _getMinutesPerLine();
    final hourHeight = _getHourHeight(context);
    final linesPerHour = _getTimeLinesCount();
    final lineHeightCalc = hourHeight / linesPerHour;
    
    final notes = _timelineNotes.where((note) {
      if (note['allDay'] == true) return false; // на весь день → в верхнюю ленту
      final startTime = note['startTime'] as DateTime;
      // Проверяем, попадает ли заметка в неделю
      return weekDates.any((date) => _isSameDay(startTime, date));
    }).toList();
    
    return notes.map((note) {
      final noteId = note['id']?.toString();
      final startTime = note['startTime'] as DateTime;
      final endTime = note['endTime'] as DateTime;
      final title = note['title'] as String;
      final colorHex = note['color'] as String? ?? '#FFEB3B';
      final iconKey = note['icon'] as String?;
      
      // Находим индекс дня недели для этой заметки
      int dayIndex = -1;
      for (int i = 0; i < weekDates.length; i++) {
        if (_isSameDay(startTime, weekDates[i])) {
          dayIndex = i;
          break;
        }
      }
      
      // Если заметка не попадает ни в один день недели, пропускаем
      if (dayIndex == -1) {
        return const SizedBox.shrink();
      }
      
      // Вычисляем позицию заметки относительно начала дня
      final dayStart = DateTime(weekDates[dayIndex].year, weekDates[dayIndex].month, weekDates[dayIndex].day);
      final noteStartInDay = DateTime(dayStart.year, dayStart.month, dayStart.day, startTime.hour, startTime.minute);
      
      final startPosition = _getTimePositionForDateTime(context, noteStartInDay, weekDates[dayIndex]) - _currentScrollOffset;
      final duration = endTime.difference(startTime);
      final height = (duration.inMinutes / minutesPerLine) * lineHeightCalc;
      
      // Вычисляем высоту хедера дней недели для корректного скрытия заметок
      final headerHeight = 60.0; // Примерная высота хедера дней недели
      final topPadding = MediaQuery.of(context).padding.top - 10;
      final totalHeaderHeight = topPadding + headerHeight;
      
      // Скрываем заметку, если она полностью выше хедера или ниже видимой области
      final screenHeight = MediaQuery.of(context).size.height;
      // Заметки не должны заходить на хедер - скрываем, если они выше видимой области с учетом хедера
      if (startPosition + height < 0 || startPosition > screenHeight - totalHeaderHeight) {
        return const SizedBox.shrink();
      }
      
      // Если заметка частично заходит на хедер, обрезаем её верхнюю часть
      final adjustedTop = startPosition < 0 ? 0.0 : startPosition;
      final adjustedHeight = startPosition < 0 
          ? height + startPosition // Уменьшаем высоту на величину, на которую заметка заходит на хедер
          : height;
      
      // Если после обрезки заметка стала невидимой, не показываем её
      if (adjustedHeight <= 0) {
        return const SizedBox.shrink();
      }
      
      final color = _getColorFromHex(colorHex);
      final iconData = _getIconData(iconKey);
      
      // Вычисляем позицию по горизонтали (left) для нужного столбика
      final left = timeColumnWidth + (dayIndex * dayColumnWidth);
      
      return Positioned(
        top: adjustedTop,
        left: left,
        width: dayColumnWidth,
        height: adjustedHeight,
        child: _WeekNoteWidget(
          noteId: noteId,
          title: title,
          color: color,
          iconData: iconData,
          noteHeight: height,
          duration: duration,
          onLongPress: (noteId, pos) =>
              _handleNoteLongPress(context, noteId, pos),
        ),
      );
    }).toList();
  }

  Widget _buildAttachingNotePreview(BuildContext context, double lineHeight) {
    if (_attachingNoteStartTime == null || _attachingNoteEndTime == null) {
      return const SizedBox.shrink();
    }

    // При перетаскивании позиция фиксируется под пальцем (_dragNoteScreenY),
    // иначе вычисляется из времени с учётом текущего скролла шкалы.
    final startPosition = _isDraggingNote
        ? _dragNoteScreenY
        : _getTimePositionForDateTime(context, _attachingNoteStartTime!, _selectedDate) - _currentScrollOffset;
    final color = _getColorFromHex(_attachingNoteColor);
    final iconData = _getIconData(_attachingNoteIcon);

    // Скрываем заметку, если она полностью выше или ниже видимой области
    final screenHeight = MediaQuery.of(context).size.height;
    if (startPosition + _attachingNoteHeight < 0 || startPosition > screenHeight) {
      return const SizedBox.shrink();
    }
    
    return Positioned(
      top: startPosition,
      left: 61,
      width: _attachingNoteWidth.clamp(100.0, MediaQuery.of(context).size.width - 61),
      height: _attachingNoteHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          setState(() {
            _isDraggingNote = true;
            // Фиксируем текущую экранную позицию заметки — дальше она едет за пальцем.
            _dragNoteScreenY = _getTimePositionForDateTime(
                    context, _attachingNoteStartTime!, _selectedDate) -
                _currentScrollOffset;
          });
          HapticFeedback.selectionClick();
        },
        onPanUpdate: (details) {
          if (!_isDraggingNote) return;
          setState(() {
            final viewportHeight = _dayContentScrollController.hasClients
                ? _dayContentScrollController.position.viewportDimension
                : MediaQuery.of(context).size.height;
            final maxTop =
                (viewportHeight - _attachingNoteHeight).clamp(0.0, double.infinity);
            // Заметка следует за пальцем 1:1, оставаясь в пределах видимой шкалы;
            // дальше «вытягивание» к нужному времени делает автоскролл у краёв.
            _dragNoteScreenY =
                (_dragNoteScreenY + details.delta.dy).clamp(0.0, maxTop);
            _updateDragNoteTimeFromScreenY(context);
          });
          // Автоскролл у краёв (продолжается, даже если палец стоит на месте).
          _checkAutoScroll(context);
        },
        onPanEnd: (details) {
          _autoScrollTimer?.cancel();
          _autoScrollTimer = null;
          setState(() {
            _updateDragNoteTimeFromScreenY(context);
            _isDraggingNote = false;
          });
        },
        onPanCancel: () {
          _autoScrollTimer?.cancel();
          _autoScrollTimer = null;
          setState(() {
            _isDraggingNote = false;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
          ),
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // Адаптивные размеры в зависимости от высоты заметки
                  final availableHeight = constraints.maxHeight;
                  final maxPadding = 12.0;
                  final padding = maxPadding; // Одинаковый padding для всех заметок
                  
                  // Вычисляем длительность заметки в минутах
                  final noteDurationMinutes = _attachingNoteStartTime != null && _attachingNoteEndTime != null
                      ? _attachingNoteEndTime!.difference(_attachingNoteStartTime!).inMinutes
                      : 0;
                  
                  // Для заметок 10 минут и меньше - показываем время в одну строку с названием
                  final isSmallNote = noteDurationMinutes <= 10;
                  
                  // Вычисляем высоту 3.5 полос
                  final threeAndHalfLinesHeight = lineHeight * 3.5;
                  // До 3.5 полос по высоте - название и время в одну строку
                  final shouldShowInOneLine = availableHeight <= threeAndHalfLinesHeight;
                  
                  // Размеры подбираем так же, как у отрисованной заметки
                  // (виджет таймлайна), иначе при входе в режим редактирования
                  // иконка/название визуально съезжают вправо.
                  final isSmallByHeight = availableHeight <= 35;
                  final iconSize = isSmallByHeight
                      ? (availableHeight * 0.5).clamp(10.0, 16.0)
                      : (availableHeight * 0.35).clamp(12.0, 24.0);
                  final titleFontSize = isSmallByHeight
                      ? (availableHeight * 0.4).clamp(8.0, 12.0)
                      : (availableHeight * 0.25).clamp(10.0, 14.0);
                  final durationFontSize = isSmallByHeight
                      ? (availableHeight * 0.35).clamp(7.0, 10.0)
                      : (availableHeight * 0.15).clamp(8.0, 12.0);
                  final spacing =
                      isSmallByHeight ? 4.0 : (availableHeight * 0.05).clamp(2.0, 6.0);
                  final durationSpacing = availableHeight > 50 ? 2.0 : (availableHeight <= 35 ? 0.0 : 1.0);
                  
                  final horizontalPadding = 8.0; // Одинаковый отступ слева для всех заметок
                  
                  // Для самых маленьких заметок не поднимаем текст, чтобы иконка центрировалась
                  final isVerySmallNote = availableHeight <= 20;
                  
                  return Padding(
                    padding: EdgeInsets.only(left: horizontalPadding, right: padding, top: padding, bottom: padding),
                    child: isSmallNote || availableHeight <= 35 || shouldShowInOneLine
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (iconData != null) ...[
                                Icon(
                                  iconData,
                                  size: iconSize,
                                  color: Color.lerp(color, Colors.black, 0.5)?.withValues(alpha: 0.7) ?? color.withValues(alpha: 0.7),
                                ),
                                SizedBox(width: spacing),
                              ],
                              if (_attachingNoteTitle != null && _attachingNoteTitle!.isNotEmpty)
                                Flexible(
                                  child: isVerySmallNote
                                      ? Text(
                                          _attachingNoteTitle!,
                                          style: TextStyle(
                                            fontSize: titleFontSize,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        )
                                      : Transform.translate(
                                          offset: const Offset(0, -10),
                                          child: Text(
                                            _attachingNoteTitle!,
                                            style: TextStyle(
                                              fontSize: titleFontSize,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                ),
                              if (_attachingNoteStartTime != null && _attachingNoteEndTime != null) ...[
                                SizedBox(width: spacing),
                                isVerySmallNote
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 2.0),
                                        child: Text(
                                          _formatDuration(_attachingNoteStartTime!, _attachingNoteEndTime!),
                                          style: TextStyle(
                                            fontSize: durationFontSize,
                                            fontWeight: FontWeight.w400,
                                            color: Colors.black87.withValues(alpha: 0.7),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      )
                                    : Transform.translate(
                                        offset: const Offset(0, -10),
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 2.0),
                                          child: Text(
                                            _formatDuration(_attachingNoteStartTime!, _attachingNoteEndTime!),
                                            style: TextStyle(
                                              fontSize: durationFontSize,
                                              fontWeight: FontWeight.w400,
                                              color: Colors.black87.withValues(alpha: 0.7),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                              ],
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (iconData != null) ...[
                                SizedBox(
                                  width: iconSize,
                                  height: iconSize,
                                  child: Icon(
                                    iconData,
                                    size: iconSize,
                                    color: Color.lerp(color, Colors.black, 0.5)?.withValues(alpha: 0.7) ?? color.withValues(alpha: 0.7),
                                  ),
                                ),
                                SizedBox(width: spacing),
                              ],
                              if (_attachingNoteTitle != null && _attachingNoteTitle!.isNotEmpty)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: Text(
                                          _attachingNoteTitle!,
                                          style: TextStyle(
                                            fontSize: titleFontSize,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: availableHeight > 50 ? 2 : 1,
                                        ),
                                      ),
                                      if (_attachingNoteStartTime != null && _attachingNoteEndTime != null) ...[
                                        if (durationSpacing > 0) SizedBox(height: durationSpacing),
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: Text(
                                            _formatDuration(_attachingNoteStartTime!, _attachingNoteEndTime!),
                                            style: TextStyle(
                                              fontSize: durationFontSize,
                                              fontWeight: FontWeight.w400,
                                              color: Colors.black87.withValues(alpha: 0.7),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  );
                },
              ),
              // Черточка для изменения высоты (снизу по центру)
              Positioned(
                left: (_attachingNoteWidth / 2 - 20).clamp(0.0, double.infinity),
                bottom: 0,
                child: GestureDetector(
                  onPanStart: (details) {
                    _previousNoteHeight = _attachingNoteHeight;
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      final hourHeight = _getHourHeight(context);
                      final linesPerHour = _getTimeLinesCount();
                      final lineHeight = hourHeight / linesPerHour;
                      const hoursInDay = 24;
                      final maxHeight = hourHeight * hoursInDay;
                      final minutesPerLine = _getMinutesPerLine();
                      
                      _attachingNoteHeight += details.delta.dy;
                      _attachingNoteHeight = _attachingNoteHeight.clamp(lineHeight, maxHeight);
                      // Пересчитываем время окончания
                      final minutesToAdd = (_attachingNoteHeight / lineHeight * minutesPerLine).round();
                      _attachingNoteEndTime = _attachingNoteStartTime!.add(Duration(minutes: minutesToAdd));
                      
                      // Вибрация при изменении на каждую полоску
                      final currentLine = (_attachingNoteHeight / lineHeight).round();
                      final previousLine = (_previousNoteHeight / lineHeight).round();
                      if (currentLine != previousLine) {
                        HapticFeedback.selectionClick();
                        _previousNoteHeight = _attachingNoteHeight;
                      }
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
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

  Widget _buildWeekView() {
    const hoursInDay = 24;
    final linesPerHour = _getTimeLinesCount();
    final minutesPerLine = _getMinutesPerLine();
    final totalLines = hoursInDay * linesPerHour;
    final hourHeight = _getHourHeight(context); // Высота одного часа (фиксированная)
    final lineHeight = hourHeight / linesPerHour; // Высота одной строки
    final weekDates = _getWeekDates();
    final colors = AppColors.of(context);

    return Container(
      color: colors.background, // Фон таймлайна
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification || notification is ScrollEndNotification) {
            setState(() {
              _currentScrollOffset = notification.metrics.pixels;
            });
          }
          return false;
        },
        child: ClipRect(
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
                            decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: _gridHourLineColor(colors), width: 1.0),
                            ),
            ),
          ),
          // Вертикальная линия-разделитель
          Container(
            width: 1,
                          height: 1.0,
                          color: _gridLineColor(colors),
          ),
                        // Колонки для дней недели (закрывающая полоса)
          Expanded(
            child: Row(
                            children: weekDates.asMap().entries.map((entry) {
                return Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                                      top: BorderSide(color: _gridLineColor(colors), width: 1.0),
                                      // Вертикальная граница между днями (кроме последнего дня)
                                      right: entry.key < weekDates.length - 1
                                          ? BorderSide(
                                              color: _gridLineColor(colors),
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
                              ? Border(
                                  top: BorderSide(color: _gridHourLineColor(colors), width: 1.0),
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
                            style: TextStyle(
                              fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary,
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
                        color: _gridLineColor(colors),
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
                                  color: isTodayColumn ? colors.surfaceVariant : colors.background,
                                  border: Border(
                                    // Темно-серая линия на часах (вверху), серая на всех промежуточных строках (включая первую после 00:00)
                                    top: isHourStart
                                        ? BorderSide(color: _gridHourLineColor(colors), width: 1.0)
                                        : BorderSide(color: _gridLineColor(colors), width: 0.5),
                                    bottom: BorderSide.none,
                                    // Вертикальная граница между днями (кроме последнего дня)
                                    right: entry.key < weekDates.length - 1
                                        ? BorderSide(
                                            color: _gridLineColor(colors),
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
            // Сохраненные заметки для недельного вида
            ..._buildWeekTimelineNotes(context, lineHeight),
            // Блок-превью заметки в режиме прикрепления (для недельного вида)
            if (_isAttachingNote && _attachingNoteStartTime != null && _listViewType == ListViewType.week && _shouldShowCurrentTimeIndicator())
              _buildAttachingNotePreview(context, lineHeight),
            // Индикатор текущего времени (красная линия с меткой времени) для недельного вида - поверх заметок
            // Показываем только для сегодняшнего дня
            // Позиция вычисляется относительно прокрученного контента
            if (_shouldShowCurrentTimeIndicator())
              Positioned(
                top: (_getCurrentTimePosition(context) - _currentScrollOffset).clamp(0.0, double.infinity),
                left: 0,
                right: 0,
                height: 1.0, // Фиксированная высота для Stack
                child: IgnorePointer(
                  child: _buildCurrentTimeIndicator(),
                ),
              ),
          ],
          ),
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
    final colors = AppColors.of(context);

    return Container(
      color: colors.background,
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
              children: [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')]
                  .map((day) => SizedBox(
                        width: (MediaQuery.of(context).size.width - 32) / 7,
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
                                ? colors.inverseSurface
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
                                    ? colors.onInverseSurface
                                    : isCurrentMonth
                                        ? colors.textPrimary
                                        : colors.textTertiary,
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

// Виджет заметки с поддержкой длительного нажатия
class _NoteWidget extends StatefulWidget {
  final String? noteId;
  final String title;
  final Color color;
  final IconData? iconData;
  final double iconSize;
  final double noteHeight;
  final Duration duration;
  // Сегмент задачи, перешедшей через полночь: верх обрезан (продолжение с
  // прошлых суток) / низ обрезан (продолжается в следующие сутки).
  final bool isContinuation;
  final bool clippedBottom;
  final Function(String?, Offset) onLongPress;
  final VoidCallback? onTap;

  const _NoteWidget({
    required this.noteId,
    required this.title,
    required this.color,
    required this.iconData,
    required this.iconSize,
    required this.noteHeight,
    required this.duration,
    this.isContinuation = false,
    this.clippedBottom = false,
    required this.onLongPress,
    this.onTap,
  });

  @override
  State<_NoteWidget> createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<_NoteWidget> {
  Timer? _longPressTimer;
  bool _isPressed = false;
  Offset _pressPosition = Offset.zero;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _isPressed = true;
    _pressPosition = details.globalPosition;
    _longPressTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _isPressed) {
        widget.onLongPress(widget.noteId, _pressPosition);
        _isPressed = false;
      }
    });
  }

  void _handleTapUp(TapUpDetails details) {
    final wasPressed = _isPressed;
    _isPressed = false;
    final timerActive = _longPressTimer?.isActive ?? false;
    _longPressTimer?.cancel();
    // Быстрый тап (long-press не успел сработать) и палец почти не сместился →
    // открываем шторку просмотра/редактирования заметки.
    if (wasPressed && timerActive) {
      final moved = (details.globalPosition - _pressPosition).distance;
      if (moved < 12) widget.onTap?.call();
    }
  }

  void _handleTapCancel() {
    _isPressed = false;
    _longPressTimer?.cancel();
  }

  String _formatDurationWidget(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return tr('{0}ч {1}м', [hours, minutes]);
    }
    return tr('{0}м', [minutes]);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final renderBox = context.findRenderObject() as RenderBox?;
        final localPosition = renderBox != null ? renderBox.globalToLocal(event.position) : event.localPosition;
        _handleTapDown(TapDownDetails(globalPosition: event.position, localPosition: localPosition, kind: PointerDeviceKind.touch));
      },
      onPointerUp: (event) {
        final renderBox = context.findRenderObject() as RenderBox?;
        final localPosition = renderBox != null ? renderBox.globalToLocal(event.position) : event.localPosition;
        _handleTapUp(TapUpDetails(globalPosition: event.position, localPosition: localPosition, kind: PointerDeviceKind.touch));
      },
      onPointerMove: (event) {
        // Палец поехал → это скролл таймлайна, а не тап/лонг-пресс.
        // Снимаем нажатие, чтобы не открыть шторку и не словить лонг-пресс.
        if (_isPressed && (event.position - _pressPosition).distance > 12) {
          _handleTapCancel();
        }
      },
      onPointerCancel: (event) {
        _handleTapCancel();
      },
      // Сама заметка НЕ перехватывает вертикальный скролл: визуал в IgnorePointer,
      // поэтому translucent-Listener не поглощает события и перетаскивание уходит
      // в ListView под заметкой (таймлайн скроллится сквозь блок).
      child: IgnorePointer(
        child: Container(
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.85),
          // У перенесённых через полночь сегментов скругляем только «целый»
          // край: верх обрезан → верхние углы прямые, низ обрезан → нижние.
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(widget.isContinuation ? 0 : 8),
            bottom: Radius.circular(widget.clippedBottom ? 0 : 8),
          ),
          border: Border.all(color: widget.color.withValues(alpha: 0.5), width: 1),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            // Контрастный цвет текста/иконки по яркости фона блока.
            final bg = Color.alphaBlend(
                widget.color.withValues(alpha: 0.85), Colors.white);
            final fg =
                bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
            final padding = h < 26 ? 4.0 : 8.0;
            // Иконка чуть больше прежнего, но ограничена высотой блока.
            final iconSize = (h - padding * 2).clamp(14.0, 30.0);
            final fontSize = h < 30 ? 13.0 : 14.0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.iconData != null) ...[
                    Icon(widget.iconData,
                        size: iconSize, color: fg.withValues(alpha: 0.85)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: widget.title,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                        TextSpan(
                          text: '  ${_formatDurationWidget(widget.duration)}',
                          style: TextStyle(
                            fontSize: fontSize - 2,
                            fontWeight: FontWeight.w400,
                            color: fg.withValues(alpha: 0.6),
                          ),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}

// Шторка просмотра/редактирования заметки таймлайна: название, описание,
// время (только просмотр), смена цвета и иконки.
class _TimelineNoteSheet extends StatefulWidget {
  final String title;
  final String description;
  final String colorHex;
  final String? iconKey;
  final DateTime startTime;
  final DateTime endTime;
  final void Function(
      String title, String description, String colorHex, String? iconKey) onSave;

  const _TimelineNoteSheet({
    required this.title,
    required this.description,
    required this.colorHex,
    required this.iconKey,
    required this.startTime,
    required this.endTime,
    required this.onSave,
  });

  @override
  State<_TimelineNoteSheet> createState() => _TimelineNoteSheetState();
}

class _TimelineNoteSheetState extends State<_TimelineNoteSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late String _colorHex;
  late String? _iconKey;

  static const List<int> _palette = [
    0xFFFFB59A, 0xFFFF3B30, 0xFFFF7A45, 0xFFFF9500, 0xFFFFCC00,
    0xFF34C759, 0xFF30D158, 0xFF00C7BE, 0xFF32ADE6, 0xFF007AFF,
    0xFF5856D6, 0xFFAF52DE, 0xFFFF2D55, 0xFFA2845E, 0xFF8E8E93,
  ];

  static const List<IconData> _icons = [
    CupertinoIcons.check_mark_circled,
    CupertinoIcons.star_fill,
    CupertinoIcons.flag_fill,
    CupertinoIcons.bell_fill,
    CupertinoIcons.heart_fill,
    CupertinoIcons.bolt_fill,
    CupertinoIcons.flame_fill,
    CupertinoIcons.book_fill,
    CupertinoIcons.briefcase_fill,
    CupertinoIcons.cart_fill,
    CupertinoIcons.house_fill,
    CupertinoIcons.airplane,
    CupertinoIcons.car_fill,
    CupertinoIcons.gift_fill,
    CupertinoIcons.money_dollar_circle_fill,
    CupertinoIcons.creditcard_fill,
    CupertinoIcons.phone_fill,
    CupertinoIcons.mail_solid,
    CupertinoIcons.chat_bubble_2_fill,
    CupertinoIcons.calendar,
    CupertinoIcons.clock_fill,
    CupertinoIcons.alarm_fill,
    CupertinoIcons.drop_fill,
    CupertinoIcons.sportscourt_fill,
    CupertinoIcons.sun_max_fill,
    CupertinoIcons.moon_fill,
    CupertinoIcons.bed_double_fill,
    CupertinoIcons.paintbrush_fill,
    CupertinoIcons.music_note,
    CupertinoIcons.camera_fill,
    CupertinoIcons.game_controller_solid,
    CupertinoIcons.bag_fill,
    CupertinoIcons.heart_circle_fill,
    CupertinoIcons.lightbulb_fill,
    CupertinoIcons.pencil,
    CupertinoIcons.doc_text_fill,
    CupertinoIcons.lock_fill,
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _descController = TextEditingController(text: widget.description);
    _colorHex = widget.colorHex;
    _iconKey = widget.iconKey;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  String _hexOf(int c) =>
      '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFFFFB59A);
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accent = _parseColor(_colorHex);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final timeLabel =
        '${_two(widget.startTime.hour)}:${_two(widget.startTime.minute)} – ${_two(widget.endTime.hour)}:${_two(widget.endTime.minute)}';
    final dateLabel =
        '${_two(widget.startTime.day)}.${_two(widget.startTime.month)}.${widget.startTime.year}';
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: colors.isDark
                ? colors.surface.withValues(alpha: 0.92)
                : colors.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: (viewInsets > 0 ? viewInsets : MediaQuery.of(context).padding.bottom) + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Время (только просмотр).
                      Row(
                        children: [
                          Icon(CupertinoIcons.clock,
                              size: 16, color: colors.textTertiary),
                          const SizedBox(width: 6),
                          Text(
                            '$dateLabel · $timeLabel',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Название.
                      TextField(
                        controller: _titleController,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: tr('Название'),
                          hintStyle: TextStyle(color: colors.textTertiary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Описание.
                      TextField(
                        controller: _descController,
                        maxLines: 5,
                        minLines: 1,
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.textSecondary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: tr('Описание'),
                          hintStyle: TextStyle(color: colors.textTertiary),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Цвет.
                      Text(
                        tr('Цвет'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _palette.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final hex = _hexOf(_palette[i]);
                            final selected = hex == _colorHex;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _colorHex = hex);
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Color(_palette[i]),
                                  shape: BoxShape.circle,
                                  border: selected
                                      ? Border.all(
                                          color: colors.textPrimary, width: 2.5)
                                      : null,
                                ),
                                child: selected
                                    ? const Icon(CupertinoIcons.check_mark,
                                        size: 18, color: Colors.white)
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Иконка.
                      Text(
                        tr('Иконка'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Сетка иконок: 5 в ряд, 4 ряда видимы, остальные —
                      // вертикальным скроллом (как в клавиатуре Apple).
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const cols = 5;
                          const spacing = 12.0;
                          const visibleRows = 4;
                          final tile =
                              (constraints.maxWidth - (cols - 1) * spacing) /
                                  cols;
                          final gridHeight =
                              tile * visibleRows + spacing * (visibleRows - 1);
                          return SizedBox(
                            height: gridHeight,
                            child: GridView.builder(
                              padding: EdgeInsets.zero,
                              physics: const BouncingScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: spacing,
                                crossAxisSpacing: spacing,
                                childAspectRatio: 1,
                              ),
                              itemCount: _icons.length,
                              itemBuilder: (context, i) {
                                final icon = _icons[i];
                                final key = 'cupertino:${icon.codePoint}';
                                final selected = key == _iconKey;
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _iconKey = key);
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? accent.withValues(alpha: 0.16)
                                          : colors.surfaceVariant,
                                      borderRadius: BorderRadius.circular(12),
                                      border: selected
                                          ? Border.all(color: accent, width: 1.5)
                                          : null,
                                    ),
                                    child: Icon(
                                      icon,
                                      size: 22,
                                      color: selected
                                          ? accent
                                          : colors.textSecondary,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  final title = _titleController.text.trim();
                  if (title.isEmpty) return;
                  widget.onSave(
                      title, _descController.text.trim(), _colorHex, _iconKey);
                },
                child: Container(
                  width: double.infinity,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.inverseSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    tr('Сохранить'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.onInverseSurface,
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
}

// Упрощенный виджет заметки для недельного вида - только иконка сверху
class _WeekNoteWidget extends StatefulWidget {
  final String? noteId;
  final String? title;
  final Color color;
  final IconData? iconData;
  final double noteHeight;
  final Duration duration;
  final Function(String?, Offset) onLongPress;

  const _WeekNoteWidget({
    required this.noteId,
    this.title,
    required this.color,
    required this.iconData,
    required this.noteHeight,
    required this.duration,
    required this.onLongPress,
  });

  @override
  State<_WeekNoteWidget> createState() => _WeekNoteWidgetState();
}

class _WeekNoteWidgetState extends State<_WeekNoteWidget> {
  Timer? _longPressTimer;
  bool _isPressed = false;
  Offset _pressPosition = Offset.zero;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _isPressed = true;
    _pressPosition = details.globalPosition;
    _longPressTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _isPressed) {
        widget.onLongPress(widget.noteId, _pressPosition);
        _isPressed = false;
      }
    });
  }

  void _handleTapUp(TapUpDetails details) {
    _isPressed = false;
    _longPressTimer?.cancel();
  }

  void _handleTapCancel() {
    _isPressed = false;
    _longPressTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Обрабатываем только tap и long press, не блокируем pan gestures для прокрутки
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPress: () {
        widget.onLongPress(widget.noteId, _pressPosition);
      },
      // Используем translucent, чтобы pan gestures могли проходить сквозь к ListView
      behavior: HitTestBehavior.translucent,
      child: Container(
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.color.withValues(alpha: 0.5), width: 1),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            final availableWidth = constraints.maxWidth;

            // Для очень маленьких заметок - только цветная полоска
            if (availableHeight < 10 || availableWidth < 10) {
              return Container(
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }

            // В недельном виде показываем ТОЛЬКО иконку у верха блока.
            final iconColor =
                Color.lerp(widget.color, Colors.black, 0.5)
                        ?.withValues(alpha: 0.7) ??
                    widget.color.withValues(alpha: 0.7);

            if (widget.iconData == null) {
              // Нет иконки — короткая цветная полоска у верха.
              return Padding(
                padding: const EdgeInsets.only(top: 5, left: 6),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    width: (availableWidth * 0.6).clamp(6.0, 24.0),
                    height: 3,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              );
            }

            final iconSize =
                (availableHeight * 0.5).clamp(10.0, 22.0);
            return Padding(
              padding: const EdgeInsets.only(top: 4, left: 5),
              child: Align(
                alignment: Alignment.topLeft,
                child: Icon(
                  widget.iconData,
                  size: iconSize,
                  color: iconColor,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Меню заметки с backdrop blur
class _NoteMenuOverlay extends StatefulWidget {
  final Offset? pressPosition;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onPomodoro;
  final VoidCallback onDelete;

  const _NoteMenuOverlay({
    this.pressPosition,
    required this.onClose,
    required this.onEdit,
    required this.onPomodoro,
    required this.onDelete,
  });

  @override
  State<_NoteMenuOverlay> createState() => _NoteMenuOverlayState();
}

class _NoteMenuOverlayState extends State<_NoteMenuOverlay> with SingleTickerProviderStateMixin {
  static const double _menuWidth = 200;
  // Примерная высота меню (3 пункта + 2 разделителя) для клампа в экран.
  static const double _menuHeight = 150;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // Те же тайминги и кривые, что у меню задач (стиль iOS 26).
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
    final screen = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    // Якорим меню у точки нажатия (как у меню задач — без затемнения фона).
    // Если позиция не передана, центрируем.
    final press = widget.pressPosition;
    final double left = press == null
        ? (screen.width - _menuWidth) / 2
        : press.dx.clamp(12.0, screen.width - _menuWidth - 12.0);
    final double top = press == null
        ? (screen.height - _menuHeight) / 2
        : press.dy.clamp(
            padding.top + 12.0,
            screen.height - _menuHeight - padding.bottom - 12.0,
          );
    // Выравнивание «роста» меню к ближайшему углу нажатия.
    final bool anchorRight = press != null && press.dx > screen.width / 2;
    final alignment =
        anchorRight ? Alignment.topRight : Alignment.topLeft;

    return Stack(
      children: [
        // Прозрачный слой-перехватчик: тап мимо меню закрывает его,
        // фон не затемняется (как у выпадающего меню задач).
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _close(widget.onClose),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            // В светлой теме тень отделяет меню от белого фона; в тёмной не нужна.
            elevation: colors.isDark ? 0 : 10,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(18),
            child: GestureDetector(
              onTap: () {}, // Предотвращаем закрытие при клике на меню
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  alignment: alignment,
                  // Стекло на BackdropFilter (стиль iOS 26) — единый стиль
                  // со всеми остальными меню приложения.
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
                          width: _menuWidth,
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
                                CupertinoIcons.timer,
                                tr('Запустить таймер'),
                                () => _close(widget.onPomodoro),
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

