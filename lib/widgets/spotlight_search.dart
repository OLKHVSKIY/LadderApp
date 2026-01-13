import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:open_filex/open_filex.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/database_instance.dart';
import '../data/user_session.dart';
import '../models/task.dart' as task_model;
import '../models/task.dart';
import '../models/note_model.dart';
import '../models/goal_model.dart';
import '../models/attached_file.dart';
import '../pages/tasks_page.dart';
import '../pages/notes_page.dart';
import '../pages/plan_page.dart';
import '../services/yandex_gpt_service.dart';
import '../widgets/custom_snackbar.dart';
import 'main_header.dart';

enum SearchResultType {
  task,
  note,
  goal,
  file,
}

class SearchResult {
  final SearchResultType type;
  final String title;
  final String subtitle;
  final String? description; // Для задач: описание отдельно от хештегов
  final List<String>? tags; // Для задач: хештеги отдельно
  final dynamic data;
  final DateTime? date;

  SearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    this.description,
    this.tags,
    required this.data,
    this.date,
  });
}

/// Виджет поиска в стиле Spotlight macOS
class SpotlightSearch extends StatefulWidget {
  final VoidCallback? onTaskCreated;

  const SpotlightSearch({super.key, this.onTaskCreated});

  @override
  State<SpotlightSearch> createState() => _SpotlightSearchState();
}

class _SpotlightChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _SpotlightChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class _SpotlightPendingTask {
  final String title;
  final DateTime date;

  _SpotlightPendingTask({
    required this.title,
    required this.date,
  });
}

class _SpotlightPendingNote {
  final String title;
  final String content;
  final DateTime date;

  _SpotlightPendingNote({
    required this.title,
    required this.content,
    required this.date,
  });
}

class _SpotlightSearchState extends State<SpotlightSearch>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  List<SearchResult> _results = [];
  List<_SpotlightChatMessage> _chatMessages = [];
  bool _isSearching = false;
  bool _isSending = false;
  bool _isChatMode = false;
  String _currentQuery = '';

  late final TaskRepository _taskRepository;
  late final NoteRepository _noteRepository;
  late final PlanRepository _planRepository;
  late final ChatRepository _chatRepository;
  late final YandexGptService _gptService;
  _SpotlightPendingTask? _pendingTask;
  _SpotlightPendingNote? _pendingNote;

  @override
  void initState() {
    super.initState();
    _taskRepository = TaskRepository(appDatabase);
    _noteRepository = NoteRepository(appDatabase);
    _planRepository = PlanRepository(appDatabase);
    _chatRepository = ChatRepository(appDatabase);
    _gptService = YandexGptService();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward();
    _focusNode.requestFocus();

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _currentQuery = '';
        _isSearching = false;
        _isChatMode = _chatMessages.isNotEmpty; // Если есть сообщения, остаемся в режиме чата
      });
      return;
    }

    // Если есть сообщения чата, не выполняем поиск при каждом изменении
    // Поиск будет выполняться только при потере фокуса или при нажатии Enter
    if (_isChatMode) {
      return;
    }

    if (query != _currentQuery) {
      _currentQuery = query;
      _performSearch(query);
    }
  }
  
  void _handleSearchSubmit() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    
    // Всегда отправляем сообщение в чат при нажатии на кнопку отправки
    _sendChatMessage();
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final userId = UserSession.currentUserId;
      if (userId == null) {
        setState(() {
          _results = [];
          _isSearching = false;
        });
        return;
      }

      final results = <SearchResult>[];
      
      // Проверяем, является ли запрос поиском по хештегам
      final isHashtagSearch = query.startsWith('#');
      final searchQuery = isHashtagSearch ? query.substring(1).trim() : query;

      // Поиск задач
      final allTasks = await _taskRepository.searchAllTasks();
      for (final task in allTasks) {
        bool matches = false;
        
        if (isHashtagSearch) {
          // Поиск только по хештегам
          if (task.tags.isNotEmpty) {
            for (final tag in task.tags) {
              if (_matchesQuery(searchQuery, tag)) {
                matches = true;
                break;
              }
            }
          }
        } else {
          // Обычный поиск: по названию, описанию и хештегам
          matches = _matchesQuery(query, task.title) ||
              (task.description != null &&
                  _matchesQuery(query, task.description!));
          
          // Также ищем по хештегам
          if (!matches && task.tags.isNotEmpty) {
            for (final tag in task.tags) {
              if (_matchesQuery(query, tag)) {
                matches = true;
                break;
              }
            }
          }
        }
        
        if (matches) {
          // Для задач храним описание и хештеги отдельно
          String subtitle = '';
          if (task.description != null && task.description!.isNotEmpty) {
            subtitle = task.description!;
          }
          if (task.tags.isNotEmpty) {
            final tagsString = task.tags.join(' ');
            if (subtitle.isNotEmpty) {
              subtitle = '$subtitle $tagsString';
            } else {
              subtitle = tagsString;
            }
          }
          results.add(SearchResult(
            type: SearchResultType.task,
            title: task.title,
            subtitle: subtitle,
            description: task.description,
            tags: task.tags.isNotEmpty ? task.tags : null,
            data: task,
            date: task.date,
          ));
        }
      }

      // Поиск заметок (только если не поиск по хештегам)
      if (!isHashtagSearch) {
        final notes = await _noteRepository.loadNotes(userId);
        for (final note in notes) {
          if (_matchesQuery(query, note.title) ||
              _matchesQuery(query, note.content)) {
            // Для заметок subtitle - это только контент без заголовка
            // Убираем заголовок из контента, если он там есть
            String subtitle = note.content;
            // Если контент начинается с заголовка, убираем его
            if (subtitle.startsWith(note.title)) {
              subtitle = subtitle.substring(note.title.length).trim();
              // Убираем возможные разделители в начале
              while (subtitle.isNotEmpty && (subtitle.startsWith('\n') || subtitle.startsWith(' '))) {
                subtitle = subtitle.substring(1).trim();
              }
            }
            // Если после удаления заголовка subtitle пустой или равен title, делаем пустым
            if (subtitle.isEmpty || subtitle == note.title) {
              subtitle = '';
            }
            results.add(SearchResult(
              type: SearchResultType.note,
              title: note.title,
              subtitle: subtitle,
              data: note,
              date: note.updatedAt ?? note.createdAt,
            ));
          }
        }
      }

      // Поиск целей (только если не поиск по хештегам)
      if (!isHashtagSearch) {
        final goals = await _planRepository.loadGoals(userId);
        for (final goal in goals) {
          if (_matchesQuery(query, goal.title)) {
            results.add(SearchResult(
              type: SearchResultType.goal,
              title: goal.title,
              subtitle: '',
              data: goal,
              date: goal.savedAt ?? goal.createdAt,
            ));
          }
        }
      }

      // Поиск по файлам в задачах и заметках (только если не поиск по хештегам)
      if (!isHashtagSearch) {
        // Поиск файлов в задачах
        final allTasks = await _taskRepository.searchAllTasks();
        for (final task in allTasks) {
          if (task.attachedFiles != null && task.attachedFiles!.isNotEmpty) {
            for (final file in task.attachedFiles!) {
              if (_matchesQuery(query, file.fileName)) {
                results.add(SearchResult(
                  type: SearchResultType.file,
                  title: file.fileName,
                  subtitle: 'Файл в задаче: ${task.title}',
                  data: file,
                  date: task.date,
                ));
              }
            }
          }
        }
        
        // Поиск файлов в заметках
        final notes = await _noteRepository.loadNotes(userId);
        for (final note in notes) {
          if (note.attachedFiles != null && note.attachedFiles!.isNotEmpty) {
            for (final file in note.attachedFiles!) {
              if (_matchesQuery(query, file.fileName)) {
                results.add(SearchResult(
                  type: SearchResultType.file,
                  title: file.fileName,
                  subtitle: 'Файл в заметке: ${note.title}',
                  data: file,
                  date: note.updatedAt ?? note.createdAt,
                ));
              }
            }
          }
        }
      }

      // Сортируем по дате (новые сначала)
      results.sort((a, b) => (b.date ?? DateTime(2000))
          .compareTo(a.date ?? DateTime(2000)));

      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
    }
  }

  bool _matchesQuery(String query, String text) {
    final lowerQuery = query.toLowerCase();
    final lowerText = text.toLowerCase();
    return lowerText.contains(lowerQuery);
  }

  // Распознает запрос на создание задачи
  _SpotlightPendingTask? _parseTaskRequest(String text) {
    final lowerText = text.toLowerCase();
    
    final monthNames = {
      'января': 1, 'янв': 1, 'январь': 1,
      'февраля': 2, 'фев': 2, 'февраль': 2,
      'марта': 3, 'мар': 3, 'март': 3,
      'апреля': 4, 'апр': 4, 'апрель': 4,
      'мая': 5, 'май': 5,
      'июня': 6, 'июн': 6, 'июнь': 6,
      'июля': 7, 'июл': 7, 'июль': 7,
      'августа': 8, 'авг': 8, 'август': 8,
      'сентября': 9, 'сен': 9, 'сентябрь': 9,
      'октября': 10, 'окт': 10, 'октябрь': 10,
      'ноября': 11, 'ноя': 11, 'ноябрь': 11,
      'декабря': 12, 'дек': 12, 'декабрь': 12,
    };
    
    final taskPatterns = [
      RegExp(r'поставь\s+задачу\s+(?:на\s+)?(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)(?:\s+(\d{2,4}))?\s+(.+)$', caseSensitive: false),
      RegExp(r'создай\s+задачу\s+(?:на\s+)?(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)(?:\s+(\d{2,4}))?\s+(.+)$', caseSensitive: false),
      RegExp(r'добавь\s+задачу\s+(?:на\s+)?(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)(?:\s+(\d{2,4}))?\s+(.+)$', caseSensitive: false),
      RegExp(r'поставь\s+задачу\s+(?:на\s+)?(сегодня|завтра|вчера|послезавтра|(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?)\s+(.+)', caseSensitive: false),
      RegExp(r'создай\s+задачу\s+(?:на\s+)?(сегодня|завтра|вчера|послезавтра|(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?)\s+(.+)', caseSensitive: false),
      RegExp(r'добавь\s+задачу\s+(?:на\s+)?(сегодня|завтра|вчера|послезавтра|(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?)\s+(.+)', caseSensitive: false),
    ];
    
    for (int i = 0; i < taskPatterns.length; i++) {
      final pattern = taskPatterns[i];
      final match = pattern.firstMatch(lowerText);
      if (match != null) {
        // Ищем совпадение в оригинальном тексте для сохранения регистра
        final originalMatch = pattern.firstMatch(text);
        if (originalMatch == null) continue;
        
        DateTime taskDate = DateTime.now();
        String? taskTitle;
        
        if (i < 3) {
          try {
            final day = int.parse(match.group(1)!);
            final monthName = match.group(2)!.toLowerCase();
            final month = monthNames[monthName] ?? DateTime.now().month;
            final year = match.group(3) != null ? int.parse(match.group(3)!) : DateTime.now().year;
            taskDate = DateTime(year, month, day);
            taskTitle = originalMatch.group(4)?.trim(); // Используем оригинальный текст
          } catch (e) {
            continue;
          }
        } else {
          String dateStr = match.group(1) ?? '';
          
          if (dateStr == 'сегодня') {
            taskDate = DateTime.now();
          } else if (dateStr == 'завтра') {
            taskDate = DateTime.now().add(const Duration(days: 1));
          } else if (dateStr == 'послезавтра') {
            taskDate = DateTime.now().add(const Duration(days: 2));
          } else if (dateStr == 'вчера') {
            taskDate = DateTime.now().subtract(const Duration(days: 1));
          } else if (match.group(2) != null && match.group(3) != null) {
            try {
              final day = int.parse(match.group(2)!);
              final month = int.parse(match.group(3)!);
              final year = match.group(4) != null ? int.parse(match.group(4)!) : DateTime.now().year;
              taskDate = DateTime(year, month, day);
            } catch (_) {
              taskDate = DateTime.now();
            }
          }
          
          taskTitle = originalMatch.group(5)?.trim() ?? text.replaceFirst(originalMatch.group(0)!, '').trim(); // Используем оригинальный текст
        }
        
        if (taskTitle != null && taskTitle.isNotEmpty) {
          return _SpotlightPendingTask(
            title: taskTitle,
            date: DateTime(taskDate.year, taskDate.month, taskDate.day),
          );
        }
      }
    }
    
    return null;
  }

  // Распознает запрос на создание заметки
  _SpotlightPendingNote? _parseNoteRequest(String text) {
    final lowerText = text.toLowerCase();
    
    final monthNames = {
      'января': 1, 'янв': 1, 'январь': 1,
      'февраля': 2, 'фев': 2, 'февраль': 2,
      'марта': 3, 'мар': 3, 'март': 3,
      'апреля': 4, 'апр': 4, 'апрель': 4,
      'мая': 5, 'май': 5,
      'июня': 6, 'июн': 6, 'июнь': 6,
      'июля': 7, 'июл': 7, 'июль': 7,
      'августа': 8, 'авг': 8, 'август': 8,
      'сентября': 9, 'сен': 9, 'сентябрь': 9,
      'октября': 10, 'окт': 10, 'октябрь': 10,
      'ноября': 11, 'ноя': 11, 'ноябрь': 11,
      'декабря': 12, 'дек': 12, 'декабрь': 12,
    };
    
    final notePatterns = [
      RegExp(r'поставь\s+заметку\s+(?:на\s+)?(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)(?:\s+(\d{2,4}))?\s+(.+)$', caseSensitive: false),
      RegExp(r'создай\s+заметку\s+(?:на\s+)?(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)(?:\s+(\d{2,4}))?\s+(.+)$', caseSensitive: false),
      RegExp(r'добавь\s+заметку\s+(?:на\s+)?(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)(?:\s+(\d{2,4}))?\s+(.+)$', caseSensitive: false),
      RegExp(r'поставь\s+заметку\s+(?:на\s+)?(сегодня|завтра|вчера|послезавтра|(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?)\s+(.+)', caseSensitive: false),
      RegExp(r'создай\s+заметку\s+(?:на\s+)?(сегодня|завтра|вчера|послезавтра|(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?)\s+(.+)', caseSensitive: false),
      RegExp(r'добавь\s+заметку\s+(?:на\s+)?(сегодня|завтра|вчера|послезавтра|(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?)\s+(.+)', caseSensitive: false),
    ];
    
    for (int i = 0; i < notePatterns.length; i++) {
      final pattern = notePatterns[i];
      final match = pattern.firstMatch(lowerText);
      if (match != null) {
        // Ищем совпадение в оригинальном тексте для сохранения регистра
        final originalMatch = pattern.firstMatch(text);
        if (originalMatch == null) continue;
        
        DateTime noteDate = DateTime.now();
        String? noteContent;
        
        if (i < 3) {
          try {
            final day = int.parse(match.group(1)!);
            final monthName = match.group(2)!.toLowerCase();
            final month = monthNames[monthName] ?? DateTime.now().month;
            final year = match.group(3) != null ? int.parse(match.group(3)!) : DateTime.now().year;
            noteDate = DateTime(year, month, day);
            noteContent = originalMatch.group(4)?.trim(); // Используем оригинальный текст
          } catch (e) {
            continue;
          }
        } else {
          String dateStr = match.group(1) ?? '';
          
          if (dateStr == 'сегодня') {
            noteDate = DateTime.now();
          } else if (dateStr == 'завтра') {
            noteDate = DateTime.now().add(const Duration(days: 1));
          } else if (dateStr == 'послезавтра') {
            noteDate = DateTime.now().add(const Duration(days: 2));
          } else if (dateStr == 'вчера') {
            noteDate = DateTime.now().subtract(const Duration(days: 1));
          } else if (match.group(2) != null && match.group(3) != null) {
            try {
              final day = int.parse(match.group(2)!);
              final month = int.parse(match.group(3)!);
              final year = match.group(4) != null ? int.parse(match.group(4)!) : DateTime.now().year;
              noteDate = DateTime(year, month, day);
            } catch (_) {
              noteDate = DateTime.now();
            }
          }
          
          noteContent = originalMatch.group(5)?.trim() ?? text.replaceFirst(originalMatch.group(0)!, '').trim(); // Используем оригинальный текст
        }
        
        if (noteContent != null && noteContent.isNotEmpty) {
          // Разделяем на заголовок и содержимое (первое предложение - заголовок, остальное - содержимое)
          final parts = noteContent.split(RegExp(r'[.!?]\s+'));
          final title = parts.isNotEmpty ? parts[0].trim() : noteContent.trim();
          final content = parts.length > 1 ? parts.sublist(1).join('. ').trim() : noteContent.trim();
          
          return _SpotlightPendingNote(
            title: title,
            content: content,
            date: DateTime(noteDate.year, noteDate.month, noteDate.day),
          );
        }
      }
    }
    
    return null;
  }

  // Обрабатывает ответ пользователя с приоритетом
  bool _handlePriorityResponse(String text) {
    final trimmed = text.trim();
    final priority = int.tryParse(trimmed);
    
    if (priority != null && priority >= 1 && priority <= 3) {
      if (_pendingTask != null) {
        _createTask(_pendingTask!.title, _pendingTask!.date, priority);
        setState(() {
          _pendingTask = null;
        });
        return true;
      } else if (_pendingNote != null) {
        // Для заметок создаем задачу с указанным приоритетом
        _createTask(_pendingNote!.title, _pendingNote!.date, priority);
        setState(() {
          _pendingNote = null;
        });
        return true;
      }
    }
    
    return false;
  }

  // Создает задачу в БД
  Future<void> _createTask(String title, DateTime date, int priority) async {
    if (!mounted) return;
    
    final today = DateTime.now();
    final taskDateNormalized = DateTime(date.year, date.month, date.day);
    final todayNormalized = DateTime(today.year, today.month, today.day);
    
    if (taskDateNormalized.isBefore(todayNormalized)) {
      final errorMessage = _SpotlightChatMessage(
        text: 'Нельзя создать задачу на прошедшую дату. Выберите сегодняшнюю или будущую дату.',
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      if (mounted) {
        setState(() {
          _chatMessages.add(errorMessage);
        });
        
        try {
          await _chatRepository.saveMessage(
            role: 'assistant',
            content: errorMessage.text,
          );
        } catch (e) {
          debugPrint('Ошибка сохранения сообщения: $e');
        }
      }
      return;
    }
    
    try {
      final task = Task(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        description: null,
        priority: priority,
        tags: [],
        date: date,
        endDate: null,
        isCompleted: false,
      );
      
      await _taskRepository.addTask(task);
      
      // Вызываем callback для обновления задач
      if (widget.onTaskCreated != null) {
        widget.onTaskCreated!();
      }
      
      final successMessage = _SpotlightChatMessage(
        text: 'Задача "$title" успешно создана на ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} с приоритетом $priority 🌿',
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      if (mounted) {
        setState(() {
          _chatMessages.add(successMessage);
        });
        
        try {
          await _chatRepository.saveMessage(
            role: 'assistant',
            content: successMessage.text,
          );
        } catch (e) {
          debugPrint('Ошибка сохранения сообщения: $e');
        }
        
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
    } catch (e) {
      final errorMessage = _SpotlightChatMessage(
        text: 'Не удалось создать задачу: $e',
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      if (mounted) {
        setState(() {
          _chatMessages.add(errorMessage);
        });
      }
    }
  }

  // Отправляет сообщение в чат
  Future<void> _sendChatMessage() async {
    final text = _searchController.text.trim();
    if (text.isEmpty || _isSending) return;

    // Проверяем, ожидаем ли мы ответ с приоритетом
    if (_pendingTask != null || _pendingNote != null) {
      if (_handlePriorityResponse(text)) {
        final userMessageObj = _SpotlightChatMessage(
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
        );
        
        setState(() {
          _chatMessages.add(userMessageObj);
          _searchController.clear();
          _isChatMode = true;
        });
        
        try {
          await _chatRepository.saveMessage(
            role: 'user',
            content: text,
          );
        } catch (e) {
          debugPrint('Ошибка сохранения сообщения пользователя: $e');
        }
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
        
        return;
      }
    }

    // Проверяем, является ли сообщение запросом на создание заметки
    final noteRequest = _parseNoteRequest(text);
    if (noteRequest != null) {
      final userMessageObj = _SpotlightChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _chatMessages.add(userMessageObj);
        _searchController.clear();
        _isChatMode = true;
        _pendingNote = noteRequest;
      });
      
      try {
        await _chatRepository.saveMessage(
          role: 'user',
          content: text,
        );
      } catch (e) {
        debugPrint('Ошибка сохранения сообщения пользователя: $e');
      }
      
      // Спрашиваем про приоритет
      final priorityQuestion = _SpotlightChatMessage(
        text: 'Какой приоритет выбрать для задачи? 1, 2 или 3?',
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _chatMessages.add(priorityQuestion);
      });
      
      try {
        await _chatRepository.saveMessage(
          role: 'assistant',
          content: priorityQuestion.text,
        );
      } catch (e) {
        debugPrint('Ошибка сохранения сообщения AI: $e');
      }
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      
      return;
    }

    // Проверяем, является ли сообщение запросом на создание задачи
    final taskRequest = _parseTaskRequest(text);
    if (taskRequest != null) {
      final userMessageObj = _SpotlightChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _chatMessages.add(userMessageObj);
        _searchController.clear();
        _isChatMode = true;
        _pendingTask = taskRequest;
      });
      
      try {
        await _chatRepository.saveMessage(
          role: 'user',
          content: text,
        );
      } catch (e) {
        debugPrint('Ошибка сохранения сообщения пользователя: $e');
      }
      
      final priorityQuestion = _SpotlightChatMessage(
        text: 'Какой приоритет выбрать для задачи? 1, 2 или 3?',
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _chatMessages.add(priorityQuestion);
      });
      
      try {
        await _chatRepository.saveMessage(
          role: 'assistant',
          content: priorityQuestion.text,
        );
      } catch (e) {
        debugPrint('Ошибка сохранения сообщения AI: $e');
      }
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      
      return;
    }

    final userMessage = text;
    final userMessageObj = _SpotlightChatMessage(
      text: userMessage,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _chatMessages.add(userMessageObj);
      _searchController.clear();
      _isChatMode = true;
      _isSending = true;
    });

    try {
      await _chatRepository.saveMessage(
        role: 'user',
        content: userMessage,
      );
    } catch (e) {
      debugPrint('Ошибка сохранения сообщения пользователя: $e');
    }

    try {
      final chatHistory = _chatMessages
          .where((m) => m.text != userMessage)
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'text': m.text,
              })
          .toList();

      final response = await _gptService.sendMessage(
        userMessage,
        chatHistory,
        'ru',
      );

      final aiMessageObj = _SpotlightChatMessage(
        text: response,
        isUser: false,
        timestamp: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _chatMessages.add(aiMessageObj);
          _isSending = false;
        });

        try {
          await _chatRepository.saveMessage(
            role: 'assistant',
            content: response,
          );
        } catch (e) {
          debugPrint('Ошибка сохранения сообщения AI: $e');
        }
        
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
    } catch (e) {
      final errorMessage = 'Извините, произошла ошибка. Попробуйте еще раз.';
      final errorMessageObj = _SpotlightChatMessage(
        text: errorMessage,
        isUser: false,
        timestamp: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _chatMessages.add(errorMessageObj);
          _isSending = false;
        });

        try {
          await _chatRepository.saveMessage(
            role: 'assistant',
            content: errorMessage,
          );
        } catch (saveError) {
          debugPrint('Ошибка сохранения сообщения об ошибке: $saveError');
        }
        
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
    }
  }

  void _close() {
    _animationController.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _onResultTap(SearchResult result) {
    _close();
    
    // Небольшая задержка для завершения анимации закрытия
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      
      switch (result.type) {
        case SearchResultType.task:
          _navigateToTask(result.data as task_model.Task);
          break;
        case SearchResultType.note:
          _navigateToNote(result.data as NoteModel);
          break;
        case SearchResultType.goal:
          _navigateToGoal(result.data as GoalModel);
          break;
        case SearchResultType.file:
          _openFile(result.data);
          break;
      }
    });
  }
  
  void _navigateToTask(task_model.Task task) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: TasksPage(
            animateNavIn: false,
            initialTaskToOpen: task,
          ),
        ),
      ),
    );
  }
  
  void _navigateToNote(NoteModel note) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: NotesPage(
            initialNoteToOpen: note,
          ),
        ),
      ),
    );
  }
  
  void _navigateToGoal(GoalModel goal) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: PlanPage(
            initialGoalIdToOpen: goal.id,
          ),
        ),
      ),
    );
  }

  Future<void> _openFile(AttachedFile file) async {
    try {
      HapticFeedback.mediumImpact();
      
      final sourceFile = File(file.filePath);
      if (!await sourceFile.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл не найден')),
        );
        return;
      }

      // Получаем директорию для загрузок
      Directory? directory = await getDownloadsDirectory();
      
      // Если папка Downloads недоступна, используем Documents
      if (directory == null || !await directory.exists()) {
        directory = await getApplicationDocumentsDirectory();
      }
      
      // Создаем папку Downloads внутри Documents, если её нет
      final downloadsDir = Directory(path.join(directory.path, 'Downloads'));
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      
      // Очищаем имя файла от префикса timestamp, если он есть
      String cleanFileName = file.fileName;
      final timestampPattern = RegExp(r'^\d+_');
      if (timestampPattern.hasMatch(cleanFileName)) {
        cleanFileName = cleanFileName.replaceFirst(timestampPattern, '');
      }
      
      final downloadsPath = path.join(downloadsDir.path, cleanFileName);
      var targetFile = File(downloadsPath);
      
      // Если файл уже существует, добавляем номер
      int counter = 1;
      String finalPath = downloadsPath;
      while (await targetFile.exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(cleanFileName);
        final ext = path.extension(cleanFileName);
        finalPath = path.join(downloadsDir.path, '${nameWithoutExt}_$counter$ext');
        targetFile = File(finalPath);
        counter++;
      }
      
      // Копируем файл в папку загрузок
      await sourceFile.copy(finalPath);
      
      // Пытаемся открыть файл
      final result = await OpenFilex.open(finalPath);
      
      if (!mounted) return;
      
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Файл сохранен: $cleanFileName'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при открытии файла: $e')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Затемнение на весь экран - занимает весь экран без белых полос
          Positioned.fill(
      child: GestureDetector(
        onTap: _close,
              child: Container(
                color: Colors.black.withOpacity(0.75),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
          ),
          // Контент Spotlight с анимацией
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child!,
              ),
            );
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenHeight = MediaQuery.of(context).size.height;
              // Фиксированная позиция - центр экрана минус половина высоты контейнера
              // Используем фиксированное значение вместо динамического расчета с клавиатурой
              final fixedTop = (screenHeight / 2) - 270;
              
              return Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: fixedTop.clamp(0.0, double.infinity),
                              ),
                              child: GestureDetector(
                                onTap: () {}, // Предотвращаем закрытие при клике на контент
                                child: Container(
                                  width: MediaQuery.of(context).size.width * 0.94,
                                  constraints: const BoxConstraints(maxWidth: 600),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(28),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Поле ввода
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.search,
                                                color: Colors.grey,
                                                size: 26,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: TextField(
                                                  controller: _searchController,
                                                  focusNode: _focusNode,
                                                  autofocus: true,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    color: Colors.black,
                                                  ),
                                                  decoration: const InputDecoration(
                                                    hintText: 'Поиск задач, заметок, целей..',
                                                    hintStyle: TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 18,
                                                    ),
                                                    border: InputBorder.none,
                                                    contentPadding: EdgeInsets.symmetric(vertical: 0),
                                                    isDense: true,
                                                  ),
                                                  onSubmitted: (_) {
                                                    _handleSearchSubmit();
                                                  },
                                                  textInputAction: TextInputAction.send,
                                                  onChanged: (_) => setState(() {}),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              GestureDetector(
                                                onTap: _searchController.text.trim().isEmpty ? null : _handleSearchSubmit,
                                                child: AnimatedContainer(
                                                  duration: const Duration(milliseconds: 150),
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color: _searchController.text.trim().isEmpty
                                                        ? const Color(0xFFCCCCCC)
                                                        : Colors.black,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.arrow_upward,
                                                    size: 18,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Разделитель (показываем только если есть результаты или текст введен)
                                        if ((_results.isNotEmpty || _chatMessages.isNotEmpty) || 
                                            ((_results.isEmpty && _chatMessages.isEmpty) && _searchController.text.isNotEmpty))
                                          const Divider(height: 1),
                                        // Сообщения чата или результаты поиска
                                        if (_chatMessages.isNotEmpty)
                                          ClipRRect(
                                            borderRadius: const BorderRadius.only(
                                              bottomLeft: Radius.circular(30),
                                              bottomRight: Radius.circular(30),
                                            ),
                                            child: SizedBox(
                                              height: 230.0,
                                              child: Scrollbar(
                                                thickness: 3.0,
                                                radius: const Radius.circular(2.0),
                                                thumbVisibility: true,
                                                controller: _scrollController,
                                                child: ListView.builder(
                                                  controller: _scrollController,
                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                  itemCount: _chatMessages.length,
                                                  itemBuilder: (context, index) {
                                                    final message = _chatMessages[index];
                                                    return Padding(
                                                      padding: EdgeInsets.only(bottom: index < _chatMessages.length - 1 ? 12 : 0),
                                                      child: _AnimatedSpotlightMessageBubble(
                                                        message: message,
                                                        index: index,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          )
                                        else if (_results.isEmpty &&
                                            _searchController.text.isNotEmpty)
                                          const Padding(
                                            padding: EdgeInsets.all(20),
                                            child: Text(
                                              'Ничего не найдено',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 16,
                                              ),
                                            ),
                                          )
                                        else if (_results.isNotEmpty)
                                          ClipRRect(
                                            borderRadius: const BorderRadius.only(
                                              bottomLeft: Radius.circular(30),
                                              bottomRight: Radius.circular(30),
                                            ),
                                            child: SizedBox(
                                              height: _results.length <= 3 ? null : 202.0,
                                              child: Scrollbar(
                                                thickness: 3.0,
                                                radius: const Radius.circular(2.0),
                                                thumbVisibility: true,
                                                child: ListView.builder(
                                                  shrinkWrap: _results.length <= 3,
                                                  itemCount: _results.length,
                                                  itemBuilder: (context, index) {
                                                    final result = _results[index];
                                                    return _buildResultItem(result, isLast: index == _results.length - 1);
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
              );
            },
          ),
        ),
        ],
      ),
    );
  }

  // Виджет бабла сообщения для Spotlight
  Widget _buildChatMessageBubble(_SpotlightChatMessage message) {
    return _SpotlightMessageBubble(message: message);
  }

  Widget _buildResultItem(SearchResult result, {bool isLast = false}) {
    IconData icon;
    Color iconColor;
    String typeLabel;

    switch (result.type) {
      case SearchResultType.task:
        icon = Icons.check_circle_outline;
        // Цвет иконки зависит от приоритета задачи
        final task = result.data as task_model.Task;
        if (task.priority == 1) {
          iconColor = Colors.red;
        } else if (task.priority == 2) {
          iconColor = Colors.yellow[700] ?? Colors.orange;
        } else if (task.priority == 3) {
          iconColor = Colors.blue;
        } else {
          iconColor = Colors.blue; // По умолчанию синий
        }
        typeLabel = 'Задача';
        break;
      case SearchResultType.note:
        icon = Icons.note_outlined;
        iconColor = Colors.orange;
        typeLabel = 'Заметка';
        break;
      case SearchResultType.goal:
        icon = Icons.flag_outlined;
        iconColor = Colors.green;
        typeLabel = 'Цель';
        break;
      case SearchResultType.file:
        final file = result.data as dynamic;
        // Определяем иконку по типу файла
        if (file.fileType == 'pdf') {
          icon = Icons.picture_as_pdf;
          iconColor = Colors.red;
        } else if (file.fileType == 'word') {
          icon = Icons.description;
          iconColor = Colors.blue;
        } else if (file.fileType == 'excel') {
          icon = Icons.table_chart;
          iconColor = Colors.green;
        } else if (file.fileType == 'image') {
          icon = Icons.image;
          iconColor = Colors.purple;
        } else {
          icon = Icons.insert_drive_file;
          iconColor = Colors.grey;
        }
        typeLabel = 'Файл';
        break;
    }

    return InkWell(
      onTap: () => _onResultTap(result),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: isLast ? 17 : 12, // Увеличиваем отступ снизу на 5px для последнего элемента
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Для задач: показываем описание и хештеги с умным переносом
                  if (result.type == SearchResultType.task && 
                      (result.description != null && result.description!.isNotEmpty || 
                       (result.tags != null && result.tags!.isNotEmpty))) ...[
                    const SizedBox(height: 4),
                    _buildTaskSubtitle(result.description, result.tags),
                  ]
                  // Для заметок: показываем subtitle если он не равен заголовку
                  else if (result.type == SearchResultType.note && 
                           result.subtitle.isNotEmpty && 
                           result.subtitle != result.title) ...[
                    const SizedBox(height: 4),
                    Text(
                      result.subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]
                  // Для файлов: показываем subtitle
                  else if (result.type == SearchResultType.file && 
                           result.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      result.subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSubtitle(String? description, List<String>? tags) {
    final hasDescription = description != null && description.isNotEmpty;
    final hasTags = tags != null && tags.isNotEmpty;
    
    if (!hasDescription && !hasTags) {
      return const SizedBox.shrink();
    }

    // Определяем, нужно ли переносить хештеги на новую строку
    // Если описание длиннее 40 символов, переносим хештеги
    final shouldWrap = hasDescription && description.length > 40;

    if (shouldWrap) {
      // Длинное описание - хештеги на новой строке
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasTags) ...[
            const SizedBox(height: 2),
            Text(
              tags.join(' '),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      );
    } else {
      // Короткое описание - все на одной строке
      String subtitle = '';
      if (hasDescription) {
        subtitle = description;
      }
      if (hasTags) {
        final tagsString = tags.join(' ');
        if (subtitle.isNotEmpty) {
          subtitle = '$subtitle $tagsString';
        } else {
          subtitle = tagsString;
        }
      }
      return Text(
        subtitle,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.grey,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
  }
}

class _AnimatedSpotlightMessageBubble extends StatefulWidget {
  final _SpotlightChatMessage message;
  final int index;

  const _AnimatedSpotlightMessageBubble({
    required this.message,
    required this.index,
  });

  @override
  State<_AnimatedSpotlightMessageBubble> createState() => _AnimatedSpotlightMessageBubbleState();
}

class _AnimatedSpotlightMessageBubbleState extends State<_AnimatedSpotlightMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Задержка для последовательного появления
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: _SpotlightMessageBubble(message: widget.message),
      ),
    );
  }
}

class _SpotlightMessageBubble extends StatefulWidget {
  final _SpotlightChatMessage message;

  const _SpotlightMessageBubble({required this.message});

  @override
  State<_SpotlightMessageBubble> createState() => _SpotlightMessageBubbleState();
}

class _SpotlightMessageBubbleState extends State<_SpotlightMessageBubble> {
  Timer? _longPressTimer;
  bool _isPressed = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _isPressed = true;
    _longPressTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted && _isPressed) {
        // Копируем текст в буфер обмена
        Clipboard.setData(ClipboardData(text: widget.message.text));
        // Вибрация (усиленная)
        HapticFeedback.heavyImpact();
        // Показываем уведомление
        CustomSnackBar.show(context, 'Текст скопирован в буфер обмена');
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
    final isUser = widget.message.isUser;
    final bgColor = isUser ? Colors.black : const Color(0xFFF5F5F5);
    final textColor = isUser ? Colors.white : Colors.black;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
      bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: GestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: radius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.message.text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: textColor,
                  ),
                ),
                if (!isUser) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'by AI',
                      style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFF999999),
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

