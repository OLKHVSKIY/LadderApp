import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
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
import '../widgets/note_create_modal.dart';
import '../data/repositories/note_repository.dart';
import '../models/note_model.dart';
import '../data/user_session.dart';
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
  double _attachingNoteHeight = 0.0;
  double _attachingNoteWidth = 0.0; // Ширина заметки (от левого края)
  double _attachingNoteDragOffsetY = 0.0;
  DateTime? _attachingNoteDragStartTime; // Начальное время при начале перетаскивания
  double _previousNoteHeight = 0.0; // Для отслеживания изменения размера для вибрации
  double _previousNoteWidth = 0.0; // Для отслеживания изменения размера для вибрации
  Timer? _autoScrollTimer; // Таймер для автоматического скролла
  Offset? _panStartPosition; // Начальная позиция жеста для определения скролла или перетаскивания
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
      _loadTimelineNotes();
      
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
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeNoteMenuOverlay();
    super.dispose();
  }

  void _handleNoteLongPress(BuildContext context, String? noteId) {
    if (noteId == null) return;
    
    HapticFeedback.heavyImpact();
    _showNoteMenuOverlay(context, noteId);
  }

  void _showNoteMenuOverlay(BuildContext context, String noteId) {
    _removeNoteMenuOverlay();
    
    final overlay = Overlay.of(context);
    
    _noteMenuOverlayEntry = OverlayEntry(
      builder: (context) => _NoteMenuOverlay(
        onClose: _removeNoteMenuOverlay,
        onEdit: () {
          _removeNoteMenuOverlay();
          _startEditingNote(noteId);
        },
        onDelete: () async {
          _removeNoteMenuOverlay();
          final intNoteId = int.tryParse(noteId);
          if (intNoteId == null) return;
          
          HapticFeedback.heavyImpact();
          try {
            await noteRepository.deleteNote(intNoteId);
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
      
      // Вычисляем высоту и ширину на основе времени
      final hourHeight = _getHourHeight(context);
      final linesPerHour = _getTimeLinesCount();
      final lineHeight = hourHeight / linesPerHour;
      final minutesPerLine = _getMinutesPerLine();
      final duration = endTime.difference(startTime);
      _attachingNoteHeight = (duration.inMinutes / minutesPerLine) * lineHeight;
      _attachingNoteWidth = MediaQuery.of(context).size.width - 61; // Ширина минус отступ блока времени
      _attachingNoteDragOffsetY = 0.0;
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

  void _openNoteModal() {
    setState(() {
      _isNoteModalOpen = true;
    });
  }

  void _closeNoteModal() {
    setState(() {
      _isNoteModalOpen = false;
    });
  }

  void _startAttachingNote(String title, String color, String? icon, String? linkedElementType, String? linkedElementId) {
    // Сохраняем данные о связи для последующего сохранения
    _attachingNoteLinkedElementType = linkedElementType;
    _attachingNoteLinkedElementId = linkedElementId;
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
    
    // Устанавливаем начальное время
    final startTime = DateTime(now.year, now.month, now.day, now.hour, now.minute);
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
      _attachingNoteDragOffsetY = 0.0;
      _previousNoteHeight = initialHeight;
      _previousNoteWidth = MediaQuery.of(context).size.width - 61;
      
      // Переключаемся на сегодня, если выбран другой день
      if (!_isSameDay(_selectedDate, DateTime.now())) {
        _selectedDate = DateTime.now();
        if (_listViewType != ListViewType.oneDay) {
          _listViewType = ListViewType.oneDay;
        }
      }
    });
    
    // Автоскролл к текущему времени
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentTimePosition = _getCurrentTimePosition(context);
      if (_listViewType == ListViewType.oneDay && _dayContentScrollController.hasClients) {
        _dayContentScrollController.animateTo(
          (currentTimePosition - MediaQuery.of(context).size.height / 2).clamp(0.0, double.infinity),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else if (_listViewType == ListViewType.week && _weekScrollController.hasClients) {
        _weekScrollController.animateTo(
          (currentTimePosition - MediaQuery.of(context).size.height / 2).clamp(0.0, double.infinity),
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
      _attachingNoteDragOffsetY = 0.0;
      _attachingNoteDragStartTime = null;
      _previousNoteHeight = 0.0;
      _previousNoteWidth = 0.0;
      _panStartPosition = null;
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
      // Перезагружаем заметки после сохранения
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
              'startTime': DateTime.parse(contentJson['startTime']),
              'endTime': DateTime.parse(contentJson['endTime']),
              'linkedElementType': contentJson['linkedElementType'],
              'linkedElementId': contentJson['linkedElementId'],
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
    } catch (e) {
      debugPrint('Ошибка загрузки заметок списка: $e');
    }
  }

  IconData? _getIconData(String? iconKey) {
    if (iconKey == null) return null;
    try {
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
      return '${hours}ч ${minutes}м';
    }
    return '${minutes}м';
  }

  // Автоматический скролл при приближении заметки к краям экрана
  void _checkAutoScroll(BuildContext context, double notePosition) {
    final screenHeight = MediaQuery.of(context).size.height;
    final scrollThreshold = 200.0; // Расстояние от края, на котором начинается скролл (увеличено для большего удобства)
    final baseScrollSpeed = 2.5; // Базовая скорость скролла в пикселях за тик (уменьшена для плавности)
    
    // Проверяем, близко ли заметка к нижнему краю
    final noteBottom = notePosition + _attachingNoteHeight;
    final distanceFromBottom = screenHeight - noteBottom;
    
    if (distanceFromBottom < scrollThreshold && distanceFromBottom > 0) {
      // Увеличиваем скорость скролла при приближении к краю (чем ближе, тем быстрее)
      final speedMultiplier = 1.0 + ((scrollThreshold - distanceFromBottom) / scrollThreshold) * 2.0; // От 1x до 3x
      final scrollSpeed = baseScrollSpeed * speedMultiplier;
      
      // Запускаем или продолжаем автоскролл вниз
      _autoScrollTimer?.cancel();
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (!mounted || _attachingNoteDragStartTime == null) {
          timer.cancel();
          return;
        }
        
        if (_listViewType == ListViewType.oneDay && _dayContentScrollController.hasClients) {
          final currentOffset = _dayContentScrollController.offset;
          final maxScroll = _dayContentScrollController.position.maxScrollExtent;
          
          if (currentOffset < maxScroll) {
            final newOffset = (currentOffset + scrollSpeed).clamp(0.0, maxScroll);
            final scrollDelta = newOffset - currentOffset;
            _dayContentScrollController.jumpTo(newOffset);
            setState(() {
              _currentScrollOffset = newOffset;
              // Компенсируем смещение заметки, чтобы она оставалась с пальцем на месте
              // При скролле вниз список движется вверх, заметка должна компенсировать это смещением вниз
              _attachingNoteDragOffsetY -= scrollDelta;
            });
          } else {
            timer.cancel();
          }
        }
      });
    } else if (notePosition < scrollThreshold && notePosition > -_attachingNoteHeight) {
      // Увеличиваем скорость скролла при приближении к краю (чем ближе, тем быстрее)
      final speedMultiplier = 1.0 + ((scrollThreshold - notePosition) / scrollThreshold) * 2.0; // От 1x до 3x
      final scrollSpeed = baseScrollSpeed * speedMultiplier;
      
      // Запускаем или продолжаем автоскролл вверх
      _autoScrollTimer?.cancel();
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (!mounted || _attachingNoteDragStartTime == null) {
          timer.cancel();
          return;
        }
        
        if (_listViewType == ListViewType.oneDay && _dayContentScrollController.hasClients) {
          final currentOffset = _dayContentScrollController.offset;
          
          if (currentOffset > 0) {
            final newOffset = (currentOffset - scrollSpeed).clamp(0.0, double.infinity);
            final scrollDelta = currentOffset - newOffset;
            _dayContentScrollController.jumpTo(newOffset);
            setState(() {
              _currentScrollOffset = newOffset;
              // Компенсируем смещение заметки, чтобы она оставалась с пальцем на месте
              // При скролле вверх список движется вниз, заметка должна компенсировать это смещением вверх
              _attachingNoteDragOffsetY += scrollDelta;
            });
          } else {
            timer.cancel();
          }
        }
      });
    } else {
      // Останавливаем автоскролл, если заметка далеко от краев
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
    }
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
            duration: isKeyboardClosing ? Duration.zero : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            left: 22,
            bottom: bottomPosition,
            child: GestureDetector(
              onTap: (_isAttachingNote || _isEditingNote) 
                ? (_isEditingNote ? _cancelEditingNote : _cancelAttachingNote)
                : (_isSearchOpen ? null : _openSearch),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
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
                    else if (!_isAttachingNote)
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
                      )
                    else if (_isAttachingNote || _isEditingNote)
                      Expanded(
                        child: Center(
                          child: const Icon(
                            Icons.close,
                            color: Colors.black,
                            size: 24,
                          ),
                        ),
                      ),
                    if (_isSearchOpen)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: GestureDetector(
                          onTap: () {
                            if (_isAttachingNote || _isEditingNote) {
                              _isEditingNote ? _cancelEditingNote() : _cancelAttachingNote();
                            } else {
                              FocusScope.of(context).unfocus();
                              _closeSearch();
                            }
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
            duration: isKeyboardClosing ? Duration.zero : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            right: 22,
            bottom: bottomPosition,
            child: GestureDetector(
              onTap: _isAttachingNote 
                ? (_isEditingNote ? _saveEditingNote : _confirmAttachingNote)
                : _openSettings,
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
                      child: (_isAttachingNote || _isEditingNote)
                        ? const Icon(
                          Icons.check,
                          color: Colors.black,
                          size: 24,
                        )
                        : ClipRect(
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
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_attachingNoteStartTime!.hour.toString().padLeft(2, '0')}:${_attachingNoteStartTime!.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '•',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    Text(
                      _formatDuration(_attachingNoteStartTime!, _attachingNoteEndTime!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '•',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    Text(
                      '${_attachingNoteEndTime!.hour.toString().padLeft(2, '0')}:${_attachingNoteEndTime!.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
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
            onChatTap: () {
              _toggleSidebar();
              _navigateTo(const ChatPage(), slideFromRight: true);
            },
          ),
          BottomNavigation(
            currentIndex: 1, // Список
            isSidebarOpen: _isSidebarOpen,
            onAddTask: _openNoteModal,
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
            // Сохраненные заметки на таймлайне
            ..._buildSavedTimelineNotes(context, lineHeight),
            // Блок-превью заметки в режиме прикрепления/редактирования
            if ((_isAttachingNote || _isEditingNote) && _attachingNoteStartTime != null && _listViewType == ListViewType.oneDay && (_isSameDay(_selectedDate, DateTime.now()) || (_isEditingNote && _attachingNoteStartTime != null && _isSameDay(_selectedDate, _attachingNoteStartTime!))))
              _buildAttachingNotePreview(context, lineHeight),
            // Индикатор текущего времени (черная полоса с кругом) - поверх заметок
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

  // Строит виджеты для сохраненных заметок на таймлайне
  List<Widget> _buildSavedTimelineNotes(BuildContext context, double lineHeight) {
    if (_listViewType != ListViewType.oneDay) return [];
    
    final notes = _timelineNotes.where((note) {
      final startTime = note['startTime'] as DateTime;
      return _isSameDay(startTime, _selectedDate);
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
      
      final startPosition = _getTimePositionForDateTime(context, startTime, _selectedDate) - _currentScrollOffset;
      final duration = endTime.difference(startTime);
      final height = (duration.inMinutes / minutesPerLine) * lineHeightCalc;
      
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
          onLongPress: (noteId) => _handleNoteLongPress(context, noteId),
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
      
      // Скрываем заметку, если она полностью выше или ниже видимой области
      final screenHeight = MediaQuery.of(context).size.height;
      if (startPosition + height < 0 || startPosition > screenHeight) {
        return const SizedBox.shrink();
      }
      
      final color = _getColorFromHex(colorHex);
      final iconData = _getIconData(iconKey);
      
      // Вычисляем позицию по горизонтали (left) для нужного столбика
      final left = timeColumnWidth + (dayIndex * dayColumnWidth);
      
      return Positioned(
        top: startPosition,
        left: left,
        width: dayColumnWidth,
        height: height,
        child: _WeekNoteWidget(
          noteId: noteId,
          color: color,
          iconData: iconData,
          noteHeight: height,
          duration: duration,
          onLongPress: (noteId) => _handleNoteLongPress(context, noteId),
        ),
      );
    }).toList();
  }

  Widget _buildAttachingNotePreview(BuildContext context, double lineHeight) {
    if (_attachingNoteStartTime == null || _attachingNoteEndTime == null) {
      return const SizedBox.shrink();
    }

    // Используем начальное время при перетаскивании, если оно есть, иначе используем текущее время
    final baseTime = _attachingNoteDragStartTime ?? _attachingNoteStartTime!;
    final startPosition = _getTimePositionForDateTime(context, baseTime, _selectedDate) - _currentScrollOffset + _attachingNoteDragOffsetY;
    final color = _getColorFromHex(_attachingNoteColor);
    final iconData = _getIconData(_attachingNoteIcon);
    final minutesPerLine = _getMinutesPerLine();
    
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
        onPanStart: (details) {
          // Сохраняем начальное время при начале жеста и сбрасываем смещение
          setState(() {
            _attachingNoteDragStartTime = _attachingNoteStartTime;
            _attachingNoteDragOffsetY = 0.0;
            _panStartPosition = details.globalPosition;
            _isDraggingNote = false;
          });
        },
        onPanUpdate: (details) {
          if (!_isDraggingNote && _panStartPosition != null) {
            final delta = details.globalPosition - _panStartPosition!;
            // Если движение в основном вертикальное (больше вертикального, чем горизонтального) и достаточно большое
            if (delta.dy.abs() > delta.dx.abs() && delta.dy.abs() > 15) {
              // Скроллим список программно
              if (_listViewType == ListViewType.oneDay && _dayContentScrollController.hasClients) {
                final currentOffset = _dayContentScrollController.offset;
                final maxScroll = _dayContentScrollController.position.maxScrollExtent;
                final newOffset = (currentOffset - details.delta.dy).clamp(0.0, maxScroll);
                _dayContentScrollController.jumpTo(newOffset);
                setState(() {
                  _currentScrollOffset = newOffset;
                });
              }
              return; // Не обрабатываем как перетаскивание заметки
            } else if (delta.dx.abs() > 10 || delta.dy.abs() > 10) {
              // Начинаем перетаскивание заметки
              _isDraggingNote = true;
            }
          }
          
          if (_isDraggingNote) {
            setState(() {
              // Накапливаем смещение относительно начальной позиции
              _attachingNoteDragOffsetY += details.delta.dy;
              
              // Вычисляем время для отображения в овальном блоке, но НЕ обновляем основное время
              if (_attachingNoteDragStartTime != null) {
                final basePosition = _getTimePositionForDateTime(context, _attachingNoteDragStartTime!, _selectedDate) - _currentScrollOffset;
                final newPosition = basePosition + _attachingNoteDragOffsetY;
                final totalMinutes = (newPosition / lineHeight) * minutesPerLine;
                final hours = (totalMinutes ~/ 60).floor();
                final minutes = (totalMinutes % 60).floor();
                final displayStartTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hours, minutes);
                final minutesToAdd = (_attachingNoteHeight / lineHeight * minutesPerLine).round();
                final displayEndTime = displayStartTime.add(Duration(minutes: minutesToAdd));
                
                // Обновляем время только для отображения в овальном блоке (временные переменные)
                _attachingNoteStartTime = displayStartTime;
                _attachingNoteEndTime = displayEndTime;
                
                // Автоматический скролл при приближении к краям экрана
                _checkAutoScroll(context, newPosition);
              }
            });
          }
        },
        onPanEnd: (details) {
          // Финализируем время после завершения жеста: обновляем основное время на основе смещения
          // Используем абсолютную позицию (без учета скролла) для вычисления времени, чтобы избежать проблем с округлением
          _autoScrollTimer?.cancel();
          _autoScrollTimer = null;
          if (_isDraggingNote && _attachingNoteDragStartTime != null) {
            setState(() {
              // Вычисляем абсолютную позицию (без учета скролла)
              final basePositionAbsolute = _getTimePositionForDateTime(context, _attachingNoteDragStartTime!, _selectedDate);
              final finalPositionAbsolute = basePositionAbsolute + _attachingNoteDragOffsetY;
              final totalMinutes = (finalPositionAbsolute / lineHeight) * minutesPerLine;
              final hours = (totalMinutes ~/ 60).floor();
              final minutes = (totalMinutes % 60).floor();
              _attachingNoteStartTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hours, minutes);
              final minutesToAdd = (_attachingNoteHeight / lineHeight * minutesPerLine).round();
              _attachingNoteEndTime = _attachingNoteStartTime!.add(Duration(minutes: minutesToAdd));
              
              // Сбрасываем смещение и очищаем начальное время
              _attachingNoteDragOffsetY = 0.0;
              _attachingNoteDragStartTime = null;
            });
          }
          _panStartPosition = null;
          _isDraggingNote = false;
        },
        onPanCancel: () {
          _autoScrollTimer?.cancel();
          _autoScrollTimer = null;
          _panStartPosition = null;
          _isDraggingNote = false;
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
                  final minPadding = 4.0;
                  final maxPadding = 12.0;
                  final padding = maxPadding; // Одинаковый padding для всех заметок
                  
                  // Вычисляем длительность заметки в минутах
                  final noteDurationMinutes = _attachingNoteStartTime != null && _attachingNoteEndTime != null
                      ? _attachingNoteEndTime!.difference(_attachingNoteStartTime!).inMinutes
                      : 0;
                  
                  // Для заметок 10 минут и меньше - показываем время в одну строку с названием
                  final isSmallNote = noteDurationMinutes <= 10;
                  
                  // Размер иконки адаптивный к высоте (с учетом отступов)
                  final iconMaxSize = 48.0;
                  final iconMinSize = 16.0;
                  final iconSize = (availableHeight - padding * 2).clamp(iconMinSize, iconMaxSize);
                  
                  // Размер шрифта названия адаптивный
                  final titleMaxFontSize = 16.0;
                  final titleMinFontSize = 10.0;
                  final titleFontSize = (availableHeight * 0.35).clamp(titleMinFontSize, titleMaxFontSize);
                  
                  // Размер шрифта длительности адаптивный
                  final durationMaxFontSize = 12.0;
                  final durationMinFontSize = 8.0;
                  final durationFontSize = (availableHeight * 0.25).clamp(durationMinFontSize, durationMaxFontSize);
                  
                  // Расстояние между элементами
                  final spacing = availableHeight > 40 ? 12.0 : (availableHeight * 0.15).clamp(4.0, 12.0);
                  final durationSpacing = availableHeight > 50 ? 2.0 : (availableHeight <= 35 ? 0.0 : 1.0);
                  
                  return Padding(
                    padding: EdgeInsets.all(padding),
                    child: Row(
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
                                  child: isSmallNote || availableHeight <= 35
                                      ? Row(
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Flexible(
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
                                            if (_attachingNoteStartTime != null && _attachingNoteEndTime != null) ...[
                                              SizedBox(width: spacing * 0.5),
                                              Text(
                                                _formatDuration(_attachingNoteStartTime!, _attachingNoteEndTime!),
                                                style: TextStyle(
                                                  fontSize: durationFontSize,
                                                  fontWeight: FontWeight.w400,
                                                  color: Colors.black87.withValues(alpha: 0.7),
                                                ),
                                              ),
                                            ],
                                          ],
                                        )
                                      : Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
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
                                              Text(
                                                _formatDuration(_attachingNoteStartTime!, _attachingNoteEndTime!),
                                                style: TextStyle(
                                                  fontSize: durationFontSize,
                                                  fontWeight: FontWeight.w400,
                                                  color: Colors.black87.withValues(alpha: 0.7),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
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
              // Черточка для изменения ширины (слева по центру)
              Positioned(
                left: 0,
                top: (_attachingNoteHeight / 2 - 10).clamp(0.0, double.infinity),
                child: GestureDetector(
                  onPanStart: (details) {
                    _previousNoteWidth = _attachingNoteWidth;
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      final screenWidth = MediaQuery.of(context).size.width;
                      final minWidth = 100.0;
                      final maxWidth = screenWidth - 60; // Ширина минус отступ блока времени
                      
                      _attachingNoteWidth += details.delta.dx;
                      _attachingNoteWidth = _attachingNoteWidth.clamp(minWidth, maxWidth);
                      
                      // Вибрация при изменении на каждые 20 пикселей
                      final currentStep = (_attachingNoteWidth / 20).round();
                      final previousStep = (_previousNoteWidth / 20).round();
                      if (currentStep != previousStep) {
                        HapticFeedback.selectionClick();
                        _previousNoteWidth = _attachingNoteWidth;
                      }
                    });
                  },
                  child: Container(
                    width: 4,
                    height: 20,
                    margin: const EdgeInsets.only(left: 2),
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
            // Сохраненные заметки для недельного вида
            ..._buildWeekTimelineNotes(context, lineHeight),
            // Блок-превью заметки в режиме прикрепления (для недельного вида)
            if (_isAttachingNote && _attachingNoteStartTime != null && _listViewType == ListViewType.week && _shouldShowCurrentTimeIndicator())
              _buildAttachingNotePreview(context, lineHeight),
            // Индикатор текущего времени (черная полоса с кругом) для недельного вида - поверх заметок
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

// Виджет заметки с поддержкой длительного нажатия
class _NoteWidget extends StatefulWidget {
  final String? noteId;
  final String title;
  final Color color;
  final IconData? iconData;
  final double iconSize;
  final double noteHeight;
  final Duration duration;
  final Function(String?) onLongPress;

  const _NoteWidget({
    required this.noteId,
    required this.title,
    required this.color,
    required this.iconData,
    required this.iconSize,
    required this.noteHeight,
    required this.duration,
    required this.onLongPress,
  });

  @override
  State<_NoteWidget> createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<_NoteWidget> {
  Timer? _longPressTimer;
  bool _isPressed = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _isPressed = true;
    _longPressTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _isPressed) {
        widget.onLongPress(widget.noteId);
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

  String _formatDurationWidget(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}ч ${minutes}м';
    }
    return '${minutes}м';
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
      onPointerCancel: (event) {
        _handleTapCancel();
      },
      child: Container(
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.color.withValues(alpha: 0.5), width: 1),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Адаптивные размеры в зависимости от высоты заметки
            final availableHeight = constraints.maxHeight;
            final availableWidth = constraints.maxWidth;
            final minPadding = 2.0;
            final maxPadding = 12.0;
            // Адаптивный padding: уменьшаем, если высота очень маленькая
            final padding = availableHeight < 20 
                ? minPadding 
                : (availableHeight < 30 ? 4.0 : maxPadding);
            
            // Вычисляем длительность заметки в минутах
            final noteDurationMinutes = widget.duration.inMinutes;
            
            // Для заметок 10 минут и меньше - показываем время в одну строку с названием
            final isSmallNote = noteDurationMinutes <= 10;
            
            // Для очень маленьких заметок (меньше 20px) используем минимальный размер иконки или скрываем
            final isVerySmallNote = availableHeight < 20;
            
            // Размер иконки адаптивный к высоте (с учетом отступов)
            final iconMaxSize = 48.0;
            final iconMinSize = isVerySmallNote ? 0.0 : 12.0; // Скрываем иконку для очень маленьких заметок
            final iconSize = isVerySmallNote 
                ? 0.0 
                : (availableHeight - padding * 2).clamp(iconMinSize, iconMaxSize);
            
            // Размер шрифта названия адаптивный
            final titleMaxFontSize = 16.0;
            final titleMinFontSize = 10.0;
            final titleFontSize = (availableHeight * 0.35).clamp(titleMinFontSize, titleMaxFontSize);
            
            // Размер шрифта длительности адаптивный
            final durationMaxFontSize = 12.0;
            final durationMinFontSize = 8.0;
            final durationFontSize = (availableHeight * 0.25).clamp(durationMinFontSize, durationMaxFontSize);
            
            // Расстояние между элементами
            final spacing = isVerySmallNote 
                ? 2.0 
                : (availableHeight > 40 ? 12.0 : (availableHeight * 0.15).clamp(4.0, 12.0));
            final durationSpacing = availableHeight > 50 ? 2.0 : (availableHeight <= 35 ? 0.0 : 1.0);
            
            return Padding(
              padding: EdgeInsets.all(padding),
              child: isVerySmallNote
                  ? // Для очень маленьких заметок - только текст в одну строку
                    Center(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: (availableHeight - padding * 2).clamp(8.0, 12.0),
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.iconData != null && iconSize > 0) ...[
                          SizedBox(
                            width: iconSize,
                            height: iconSize,
                            child: Icon(
                              widget.iconData,
                              size: iconSize,
                              color: Color.lerp(widget.color, Colors.black, 0.5)?.withValues(alpha: 0.7) ?? widget.color.withValues(alpha: 0.7),
                            ),
                          ),
                          SizedBox(width: spacing),
                        ],
                        Expanded(
                          child: isSmallNote || availableHeight <= 35
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.title,
                                        style: TextStyle(
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    if (availableHeight > 25) ...[
                                      SizedBox(width: spacing * 0.5),
                                      Text(
                                        _formatDurationWidget(widget.duration),
                                        style: TextStyle(
                                          fontSize: durationFontSize,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.black87.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.title,
                                      style: TextStyle(
                                        fontSize: titleFontSize,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: availableHeight > 50 ? 2 : 1,
                                    ),
                                    if (durationSpacing > 0) SizedBox(height: durationSpacing),
                                    Text(
                                      _formatDurationWidget(widget.duration),
                                      style: TextStyle(
                                        fontSize: durationFontSize,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.black87.withValues(alpha: 0.7),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

// Упрощенный виджет заметки для недельного вида - только иконка сверху
class _WeekNoteWidget extends StatefulWidget {
  final String? noteId;
  final Color color;
  final IconData? iconData;
  final double noteHeight;
  final Duration duration;
  final Function(String?) onLongPress;

  const _WeekNoteWidget({
    required this.noteId,
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

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _isPressed = true;
    _longPressTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _isPressed) {
        widget.onLongPress(widget.noteId);
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

  String _formatDurationWidget(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}ч ${minutes}м';
    }
    return '${minutes}м';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Обрабатываем только tap и long press, не блокируем pan gestures для прокрутки
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPress: () {
        widget.onLongPress(widget.noteId);
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
            
            // Иконка и продолжительность по центру
            final iconSize = (availableHeight * 0.35).clamp(12.0, 24.0);
            final topPadding = (availableHeight * 0.1).clamp(2.0, 8.0);
            final spacing = (availableHeight * 0.05).clamp(2.0, 6.0);
            final durationFontSize = (availableHeight * 0.15).clamp(8.0, 12.0);
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: topPadding),
                if (widget.iconData != null)
                  Center(
                    child: Icon(
                      widget.iconData,
                      size: iconSize,
                      color: Color.lerp(widget.color, Colors.black, 0.5)?.withValues(alpha: 0.7) ?? widget.color.withValues(alpha: 0.7),
                    ),
                  )
                else
                  // Если нет иконки, показываем цветную полоску сверху на всю ширину
                  Container(
                    width: availableWidth,
                    height: 3,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                if (widget.iconData != null && availableHeight > 25) ...[
                  SizedBox(height: spacing),
                  Center(
                    child: Text(
                      _formatDurationWidget(widget.duration),
                      style: TextStyle(
                        fontSize: durationFontSize,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Меню заметки с backdrop blur
class _NoteMenuOverlay extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoteMenuOverlay({
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_NoteMenuOverlay> createState() => _NoteMenuOverlayState();
}

class _NoteMenuOverlayState extends State<_NoteMenuOverlay> with SingleTickerProviderStateMixin {
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
    return Stack(
      children: [
        // Затемнение фона без размытия заметок
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(
              color: Colors.black.withOpacity(0.4),
            ),
          ),
        ),
        // Меню без блюра, чтобы заметки были четкими
        Center(
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
                        width: 200,
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

