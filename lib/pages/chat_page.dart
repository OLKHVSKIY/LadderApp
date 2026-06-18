import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../widgets/main_header.dart';
import '../widgets/sidebar.dart';
import '../widgets/spotlight_search.dart';
import '../services/yandex_gpt_service.dart';
import 'tasks_page.dart';
import 'settings_page.dart';
import 'notifications_page.dart';
import '../data/database_instance.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/task_repository.dart';
import '../models/task.dart';
import '../widgets/custom_snackbar.dart';
import '../l10n/app_translations.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  bool _isSidebarOpen = false;
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;
  final YandexGptService _gptService = YandexGptService();
  late final ChatRepository _chatRepository;
  TaskRepository? _taskRepository;
  final String _currentLanguage = 'ru'; // TODO: получать из настроек
  bool _isLoadingHistory = true;
  // Состояние для ожидания выбора приоритета задачи
  _PendingTask? _pendingTask;
  int _loadedMessagesCount = 0; // Количество загруженных сообщений из БД

  TaskRepository get taskRepository {
    _taskRepository ??= TaskRepository(appDatabase);
    return _taskRepository!;
  }

  @override
  void initState() {
    super.initState();
    _chatRepository = ChatRepository(appDatabase);
    _taskRepository = TaskRepository(appDatabase);
    _loadChatHistory();
  }

  /// Загрузить историю чата из БД
  Future<void> _loadChatHistory() async {
    try {
      final dbMessages = await _chatRepository.loadMessages();
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(
            dbMessages.map((msg) => _ChatMessage(
                  text: msg.content,
                  isUser: msg.role == 'user',
                  timestamp: msg.createdAt,
                )),
          );
          _loadedMessagesCount = _messages.length; // Запоминаем количество загруженных сообщений
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  void _toggleSidebar() {
    // Скрываем клавиатуру при открытии/закрытии сайдбара
    FocusScope.of(context).unfocus();
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }

  void _navigateTo(Widget page, {bool slideFromRight = false}) {
    if (page is SettingsPage) {
      // Для настроек используем push с CupertinoPageRoute для iOS swipe back
      Navigator.of(context).push(
        CupertinoPageRoute(
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

  // Распознает запрос на создание задачи
  _PendingTask? _parseTaskRequest(String text) {
    final lowerText = text.toLowerCase();
    
    // Словарь месяцев
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
    
    // Паттерны для распознавания запросов на создание задач
    final taskPatterns = [
      // Паттерн для "поставь задачу на 12 января Билеты" или "поставь задачу на 12 января 2025 Билеты"
      RegExp(r'поставь\s+задачу\s+(?:на\s+)?(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)(?:\s+(\d{2,4}))?\s+(.+)$', caseSensitive: false),
      RegExp(r'создай\s+задачу\s+(?:на\s+)?(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)(?:\s+(\d{2,4}))?\s+(.+)$', caseSensitive: false),
      RegExp(r'добавь\s+задачу\s+(?:на\s+)?(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря|янв|фев|мар|апр|мая|июн|июл|авг|сен|окт|ноя|дек)(?:\s+(\d{2,4}))?\s+(.+)$', caseSensitive: false),
      // Старые паттерны для других форматов
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
        
        // Первые три паттерна - для формата "12 января"
        if (i < 3) {
          try {
            final day = int.parse(match.group(1)!);
            final monthName = match.group(2)!.toLowerCase();
            final month = monthNames[monthName] ?? DateTime.now().month;
            final year = match.group(3) != null ? int.parse(match.group(3)!) : DateTime.now().year;
            taskDate = DateTime(year, month, day);
            taskTitle = originalMatch.group(4)?.trim(); // Используем оригинальный текст
          } catch (e) {
            debugPrint('Ошибка парсинга даты: $e');
            continue;
          }
        } else {
          // Старые паттерны
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
            // Парсим дату в формате дд.мм или дд.мм.гггг
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
          return _PendingTask(
            title: taskTitle,
            date: DateTime(taskDate.year, taskDate.month, taskDate.day),
          );
        }
      }
    }
    
    return null;
  }

  // Обрабатывает ответ пользователя с приоритетом
  bool _handlePriorityResponse(String text) {
    if (_pendingTask == null) return false;
    
    final trimmed = text.trim();
    final priority = int.tryParse(trimmed);
    
    if (priority != null && priority >= 1 && priority <= 3) {
      _createTask(_pendingTask!.title, _pendingTask!.date, priority);
      setState(() {
        _pendingTask = null;
      });
      return true;
    }
    
    return false;
  }

  // Создает задачу в БД
  Future<void> _createTask(String title, DateTime date, int priority) async {
    if (!mounted) return;
    
    // Проверяем, что дата не в прошлом
    final today = DateTime.now();
    final taskDateNormalized = DateTime(date.year, date.month, date.day);
    final todayNormalized = DateTime(today.year, today.month, today.day);
    
    if (taskDateNormalized.isBefore(todayNormalized)) {
      final errorMessage = _ChatMessage(
        text: tr('Нельзя создать задачу на прошедшую дату. Выберите сегодняшнюю или будущую дату.'),
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      if (mounted) {
        setState(() {
          _messages.add(errorMessage);
        });
        
        // Сохраняем сообщение в БД
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
      
      await taskRepository.addTask(task);
      
      final successMessage = _ChatMessage(
        text: tr('Задача "{0}" успешно создана на {1}.{2}.{3} с приоритетом {4} 🌿', [title, date.day.toString().padLeft(2, '0'), date.month.toString().padLeft(2, '0'), date.year, priority]),
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      if (mounted) {
        setState(() {
          _messages.add(successMessage);
        });
        
        // Сохраняем сообщение в БД
        try {
          await _chatRepository.saveMessage(
            role: 'assistant',
            content: successMessage.text,
          );
        } catch (e) {
          debugPrint('Ошибка сохранения сообщения: $e');
        }
      }
    } catch (e) {
      final errorMessage = _ChatMessage(
        text: tr('Не удалось создать задачу: {0}', [e]),
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      if (mounted) {
        setState(() {
          _messages.add(errorMessage);
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    // Проверяем, ожидаем ли мы ответ с приоритетом
    if (_pendingTask != null) {
      if (_handlePriorityResponse(text)) {
        final userMessageObj = _ChatMessage(
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
        );
        
        setState(() {
          _messages.add(userMessageObj);
          _controller.clear();
        });
        
        // Сохраняем сообщение пользователя в БД
        try {
          await _chatRepository.saveMessage(
            role: 'user',
            content: text,
          );
        } catch (e) {
          debugPrint('Ошибка сохранения сообщения пользователя: $e');
        }
        
        return;
      }
    }

    // Проверяем, является ли сообщение запросом на создание задачи
    final taskRequest = _parseTaskRequest(text);
    if (taskRequest != null) {
      final userMessageObj = _ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _messages.add(userMessageObj);
        _controller.clear();
        _pendingTask = taskRequest;
      });
      
      // Сохраняем сообщение пользователя в БД
      try {
        await _chatRepository.saveMessage(
          role: 'user',
          content: text,
        );
      } catch (e) {
        debugPrint('Ошибка сохранения сообщения пользователя: $e');
      }
      
      // Спрашиваем про приоритет
      final priorityQuestion = _ChatMessage(
        text: tr('Какой приоритет выбрать для задачи? 1, 2 или 3?'),
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      setState(() {
        _messages.add(priorityQuestion);
      });
      
      // Сохраняем вопрос AI в БД
      try {
        await _chatRepository.saveMessage(
          role: 'assistant',
          content: priorityQuestion.text,
        );
      } catch (e) {
        debugPrint('Ошибка сохранения сообщения AI: $e');
      }
      
      return;
    }

    final userMessage = text;
    final userMessageObj = _ChatMessage(
      text: userMessage,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessageObj);
      _controller.clear();
      _isSending = true;
    });

    // Сохраняем сообщение пользователя в БД
    try {
      await _chatRepository.saveMessage(
        role: 'user',
        content: userMessage,
      );
    } catch (e) {
      // Логируем ошибку, но продолжаем работу
      debugPrint('Ошибка сохранения сообщения пользователя: $e');
    }

    try {
      // Формируем историю сообщений для API (исключаем последнее сообщение пользователя, которое уже добавлено)
      final chatHistory = _messages
          .where((m) => m.text != userMessage)
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'text': m.text,
              })
          .toList();

      // Отправляем запрос к Yandex GPT
      final response = await _gptService.sendMessage(
        userMessage,
        chatHistory,
        _currentLanguage,
      );

      final aiMessageObj = _ChatMessage(
        text: response,
        isUser: false,
        timestamp: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _messages.add(aiMessageObj);
          _isSending = false;
        });

        // Сохраняем ответ AI в БД
        try {
          await _chatRepository.saveMessage(
            role: 'assistant',
            content: response,
          );
        } catch (e) {
          // Логируем ошибку, но продолжаем работу
          debugPrint('Ошибка сохранения сообщения AI: $e');
        }
      }
    } catch (e) {
      final errorMessage = tr('Извините, произошла ошибка. Попробуйте еще раз.');
      final errorMessageObj = _ChatMessage(
        text: errorMessage,
        isUser: false,
        timestamp: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _messages.add(errorMessageObj);
          _isSending = false;
        });

        // Сохраняем сообщение об ошибке в БД
        try {
          await _chatRepository.saveMessage(
            role: 'assistant',
            content: errorMessage,
          );
        } catch (saveError) {
          debugPrint('Ошибка сохранения сообщения об ошибке: $saveError');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top - 10,
            ),
            child: Column(
              children: [
                MainHeader(
                  title: tr('Чат с AI'),
                  showBackButton: true,
                  onBack: () {
                    Navigator.of(context).pop();
                  },
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
                  onGreetingToggle: null,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                          children: [
                            // Сообщения / пустое состояние
                            Expanded(
                              child: _isLoadingHistory
                                  ? const Center(child: CircularProgressIndicator())
                                  : _messages.isEmpty
                                      ? _buildEmptyState()
                                      : _buildMessages(),
                            ),
                            // Отступ между сообщениями и полем ввода
                            const SizedBox(height: 15),
                            // Поле ввода
                            _buildInput(),
                          ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Sidebar(
            isOpen: _isSidebarOpen,
            onClose: _toggleSidebar,
            onTasksTap: () {
              _navigateTo(const TasksPage(animateNavIn: true), slideFromRight: false);
            },
            onSettingsTap: () {
              _navigateTo(const SettingsPage(), slideFromRight: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: ListView.separated(
        reverse: true,
        itemCount: _messages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final msg = _messages[_messages.length - 1 - index];
          final actualIndex = _messages.length - 1 - index;
          // Анимируем только новые сообщения (после загрузки истории)
          // В reverse ListView индекс 0 - это последнее сообщение (самое новое)
          final shouldAnimate = actualIndex >= _loadedMessagesCount;
          // Для reverse ListView используем обратный индекс для правильной последовательности анимации
          final animationIndex = shouldAnimate ? (_messages.length - actualIndex - 1) : 0;
          return _AnimatedMessageBubble(
            key: ValueKey('${msg.timestamp.millisecondsSinceEpoch}_${msg.text}'),
            message: msg,
            index: animationIndex,
            shouldAnimate: shouldAnimate,
          );
        },
      ),
    );
  }

  Widget _buildInput() {
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // При открытой клавиатуре safe-area снизу = 0, поле прилипает к клавиатуре.
    // Оставляем зазор 7px между низом поля и клавиатурой.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, keyboardOpen ? 7 : bottomInset),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: Scrollbar(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.logicalKeysPressed.contains(
                              LogicalKeyboardKey.shiftLeft) &&
                          !HardwareKeyboard.instance.logicalKeysPressed.contains(
                              LogicalKeyboardKey.shiftRight)) {
                        _sendMessage();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      minLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      textInputAction: TextInputAction.send,
                      keyboardType: TextInputType.text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: colors.textPrimary,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        hintText: tr('Напишите сообщение...'),
                        hintStyle: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: colors.textTertiary,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _sendMessage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _controller.text.trim().isEmpty
                      ? colors.textTertiary
                      : colors.inverseSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_upward,
                  size: 18,
                  color: colors.onInverseSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 155),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            tr('Чат с AI'),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            tr('Спрашивайте, получайте подсказки и планируйте задачи с помощью AI'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              color: colors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class _AnimatedMessageBubble extends StatefulWidget {
  final _ChatMessage message;
  final int index;
  final bool shouldAnimate;

  const _AnimatedMessageBubble({
    super.key,
    required this.message,
    required this.index,
    this.shouldAnimate = true,
  });

  @override
  State<_AnimatedMessageBubble> createState() => _AnimatedMessageBubbleState();
}

class _AnimatedMessageBubbleState extends State<_AnimatedMessageBubble>
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

    // Запускаем анимацию только если нужно
    if (widget.shouldAnimate) {
      // Запускаем анимацию сразу, без задержки для первого сообщения
      Future.delayed(Duration(milliseconds: widget.index * 30), () {
        if (mounted) {
          _controller.forward();
        }
      });
    } else {
      // Для загруженных сообщений сразу показываем без анимации
      _controller.value = 1.0;
    }
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
        child: _MessageBubble(message: widget.message),
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
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
        CustomSnackBar.show(context, tr('Текст скопирован в буфер обмена'));
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
    final colors = AppColors.of(context);
    final isUser = widget.message.isUser;
    final bgColor = isUser ? colors.inverseSurface : colors.surfaceVariant;
    final textColor = isUser ? colors.onInverseSurface : colors.textPrimary;
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
                        color: colors.textTertiary,
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

class _PendingTask {
  final String title;
  final DateTime date;

  _PendingTask({
    required this.title,
    required this.date,
  });
}

