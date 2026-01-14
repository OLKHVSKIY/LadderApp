import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as dr;
import '../data/database_instance.dart';
import '../data/app_database.dart' as db;
import '../data/user_session.dart';
import '../pages/custom_tasks_page.dart';

class GreetingPanel extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onToggle;
  final int totalTasksToday;
  final int completedTasksToday;
  final String? userName;

  const GreetingPanel({
    super.key,
    required this.isOpen,
    required this.onToggle,
    required this.totalTasksToday,
    required this.completedTasksToday,
    this.userName,
  });

  @override
  State<GreetingPanel> createState() => _GreetingPanelState();
}

class _GreetingPanelState extends State<GreetingPanel>
    with TickerProviderStateMixin {
  double _dragOffset = 0.0;
  bool _isDragging = false;
  Offset? _panStartPosition;
  AnimationController? _twinkleController;
  AnimationController? _fallingController;
  Timer? _fallingTimer;
  int _fallingIndex = 0;
  final List<Offset> _fallingStarPositions = const [
    Offset(40, 30),
    Offset(120, 60),
    Offset(200, 40),
    Offset(260, 80),
    Offset(320, 50),
  ];

  void _ensureControllers() {
    _twinkleController ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _fallingController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _fallingTimer ??= Timer.periodic(const Duration(seconds: 14), (_) {
      _fallingIndex = (_fallingIndex + 1) % _fallingStarPositions.length;
      _fallingController?.forward(from: 0);
    });
  }

  String _getGreeting() {
    final name = widget.userName?.trim();
    final hour = DateTime.now().hour;
    String base;
    if (hour >= 5 && hour < 12) {
      base = 'Доброе утро';
    } else if (hour >= 12 && hour < 17) {
      base = 'Добрый день';
    } else if (hour >= 17 && hour < 22) {
      base = 'Добрый вечер';
    } else {
      base = 'Доброй ночи';
    }
    if (name == null || name.isEmpty) return base;
    return '$base, $name';
  }

  String _pluralizeTasks(int count) {
    final rem100 = count % 100;
    final rem10 = count % 10;
    final word = (rem100 >= 11 && rem100 <= 14)
        ? 'задач'
        : rem10 == 1
            ? 'задача'
            : (rem10 >= 2 && rem10 <= 4)
                ? 'задачи'
                : 'задач';
    return '$count $word';
  }

  String _getBackgroundImage() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'assets/backgrounds/morning.jpg';
    } else if (hour >= 12 && hour < 17) {
      return 'assets/backgrounds/day.jpg';
    } else if (hour >= 17 && hour < 22) {
      return 'assets/backgrounds/evening.jpg';
    } else {
      return 'assets/backgrounds/night.jpg';
    }
  }

  String _getDayOfWeek() {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[DateTime.now().weekday - 1];
  }

  String _getFormattedDate() {
    final now = DateTime.now();
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
      'декабря',
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  void initState() {
    super.initState();
    _ensureControllers();
  }

  @override
  void dispose() {
    _twinkleController?.dispose();
    _fallingController?.dispose();
    _fallingTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(GreetingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Сбрасываем offset при изменении isOpen извне
    if (oldWidget.isOpen != widget.isOpen) {
      setState(() {
        _isDragging = false;
        _dragOffset = 0.0;
        _panStartPosition = null;
      });
      // При закрытии шторки скрываем клавиатуру
      if (!widget.isOpen) {
        FocusScope.of(context).unfocus();
      }
    }
  }

  void _handlePanStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _panStartPosition = details.globalPosition;
      _dragOffset = 0.0;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging || _panStartPosition == null) return;
    
    final screenHeight = MediaQuery.of(context).size.height;
    final totalHeight = screenHeight * 0.42; // 42% экрана (увеличено для нового контента)
    
    // Вычисляем смещение от начальной позиции
    // При движении вверх globalPosition.dy уменьшается (deltaY отрицательный)
    // При движении вниз globalPosition.dy увеличивается (deltaY положительный)
    final deltaY = details.globalPosition.dy - _panStartPosition!.dy;
    
    if (widget.isOpen) {
      // При открытой панели: разрешаем только перетаскивание вверх (закрытие)
      // deltaY отрицательный при перетаскивании вверх (dy уменьшается)
      if (deltaY > 0) {
        // Движение вниз - игнорируем
        return;
      }
      // deltaY отрицательный - движение вверх, закрываем
      setState(() {
        _dragOffset = (-deltaY).clamp(0.0, totalHeight);
      });
    } else {
      // При закрытой панели: разрешаем только перетаскивание вниз (открытие)
      // deltaY положительный при перетаскивании вниз (dy увеличивается)
      if (deltaY < 0) {
        // Движение вверх - игнорируем
        return;
      }
      // deltaY положительный - движение вниз, открываем
      setState(() {
        _dragOffset = deltaY.clamp(0.0, totalHeight);
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!_isDragging) {
      // Если не было перетаскивания, просто сбрасываем состояние
      setState(() {
        _isDragging = false;
        _dragOffset = 0.0;
        _panStartPosition = null;
      });
      return;
    }
    
    final screenHeight = MediaQuery.of(context).size.height;
    final totalHeight = screenHeight * 0.42; // 42% экрана (увеличено для нового контента)
    
    // Определяем, нужно ли переключить состояние панели
    final threshold = totalHeight * 0.2; // 20% от высоты панели
    
    bool shouldToggle = false;
    
    if (widget.isOpen) {
      // Если панель открыта и перетащена больше порога вверх - закрываем
      // При перетаскивании вверх velocity будет положительной (вниз по экрану)
      if (_dragOffset > threshold || details.velocity.pixelsPerSecond.dy > 200) {
        shouldToggle = true;
      }
    } else {
      // Если панель закрыта и перетащена больше порога вниз - открываем
      // При перетаскивании вниз velocity будет положительной
      if (_dragOffset > threshold || details.velocity.pixelsPerSecond.dy > 200) {
        shouldToggle = true;
      }
    }
    
    if (shouldToggle) {
      widget.onToggle();
      setState(() {
        _isDragging = false;
        _dragOffset = 0.0;
        _panStartPosition = null;
      });
    } else {
      // Если не переключаем, возвращаем панель в исходное состояние с анимацией
      setState(() {
        _isDragging = false;
        _dragOffset = 0.0;
        _panStartPosition = null;
      });
    }
  }

  List<Widget> _buildTwinklingStars() {
    const positions = [
      Offset(20, 30),
      Offset(60, 50),
      Offset(110, 40),
      Offset(160, 60),
      Offset(210, 35),
      Offset(260, 55),
      Offset(310, 45),
      Offset(40, 90),
      Offset(90, 110),
      Offset(140, 95),
      Offset(190, 115),
      Offset(240, 100),
      Offset(290, 120),
      Offset(330, 105),
      Offset(30, 150),
      Offset(80, 165),
      Offset(130, 145),
      Offset(180, 170),
      Offset(230, 155),
      Offset(280, 175),
      Offset(320, 160),
      Offset(50, 200),
      Offset(120, 190),
      Offset(210, 205),
      Offset(300, 195),
    ];

    return List.generate(positions.length, (i) {
      final delay = i * 0.12;
      return Positioned(
        left: positions[i].dx,
        top: positions[i].dy,
        child: _TwinkleDot(
          controller: _twinkleController!,
          delay: delay,
        ),
      );
    });
  }

  Widget _buildFallingStar() {
    final start = _fallingStarPositions[_fallingIndex];
    final end = start + const Offset(80, 80);

    return AnimatedBuilder(
      animation: _fallingController ?? const AlwaysStoppedAnimation(0.0),
      builder: (context, child) {
        final controller = _fallingController;
        final t = controller == null
            ? 0.0
            : Curves.easeInOut.transform(controller.value);
        final pos = Offset(
          start.dx + (end.dx - start.dx) * t,
          start.dy + (end.dy - start.dy) * t,
        );
        final opacity = (1 - t).clamp(0.0, 1.0);
        return Positioned(
          left: pos.dx,
          top: pos.dy,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final screenHeight = MediaQuery.of(context).size.height;
    final totalHeight = screenHeight * 0.42; // 42% экрана (увеличено для нового контента)
    final bgPath = _getBackgroundImage();
    final isNight = bgPath.contains('night');
    
    // Вычисляем позицию с учетом перетаскивания
    double topPosition;
    if (widget.isOpen) {
      // При открытой панели: начинаем с 0, перетаскивание вверх уменьшает topPosition (шторка уходит вверх)
      topPosition = -_dragOffset;
    } else {
      // При закрытой панели: начинаем с -totalHeight, перетаскивание вниз уменьшает отрицательное значение
      // _dragOffset будет отрицательным при перетаскивании вниз
      topPosition = -totalHeight + _dragOffset;
    }
    
    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      top: topPosition,
      left: 0,
      right: 0,
      height: totalHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            child: Stack(
              children: [
                // Фоновое изображение (заполняет весь контейнер включая статус бар)
                Positioned.fill(
                child: Image.asset(
                  bgPath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.blue.shade300,
                            Colors.blue.shade500,
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
                // Звезды и падающая звезда только для ночной темы
                if (isNight) ...[
                  ..._buildTwinklingStars(),
                  _buildFallingStar(),
                ],
                // Контент
                GestureDetector(
                  onTap: () {
                    // Перехватываем клики, но не закрываем клавиатуру
                    // Не вызываем unfocus, чтобы клавиатура оставалась открытой
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 20,
                      left: 20,
                      right: 20,
                      bottom: 30,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Заголовок с датой
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _getDayOfWeek(),
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                            Text(
                              _getFormattedDate(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Приветствие
                        Text(
                          _getGreeting(),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 30),
                        // Статистика
                        Text(
                          'Сегодня у вас: ${_pluralizeTasks(widget.totalTasksToday)}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        // Кнопка "Новый экран +" и список экранов
                        _CustomScreensSection(
                          isPanelOpen: widget.isOpen,
                        ),
                      ],
                    ),
                  ),
                ),
                // Полоска для перетаскивания внизу
                if (widget.isOpen)
                  Positioned(
                    bottom: -7,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      onPanStart: _handlePanStart,
                      onPanUpdate: _handlePanUpdate,
                      onPanEnd: _handlePanEnd,
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TwinkleDot extends StatelessWidget {
  final AnimationController controller;
  final double delay;

  const _TwinkleDot({
    required this.controller,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final controllerValue = controller.value.clamp(0.0, 1.0);
        final value = ((controllerValue + delay) % 1.0).clamp(0.0, 1.0);
        final sine = math.sin(value * 2 * math.pi);
        final opacity = (0.2 + 0.8 * (0.5 + 0.5 * sine)).clamp(0.0, 1.0);
        final scale = 0.9 + 0.5 * (0.5 + 0.5 * sine);
        final glowOpacity = (0.3 + 0.7 * opacity).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 2,
              height: 2,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: glowOpacity),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomScreensSection extends StatefulWidget {
  final bool? isPanelOpen;

  const _CustomScreensSection({
    this.isPanelOpen,
  });

  @override
  State<_CustomScreensSection> createState() => _CustomScreensSectionState();
}

class _CustomScreensSectionState extends State<_CustomScreensSection> {
  bool _isExpanded = false;
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<db.CustomTaskScreen> _screens = [];
  bool _isLoading = false;
  int? _newlyCreatedScreenId;

  @override
  void initState() {
    super.initState();
    _loadScreens();
    // Слушаем изменения фокуса
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isExpanded) {
        setState(() {
          _isExpanded = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(_CustomScreensSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // При закрытии шторки сворачиваем поле ввода (клавиатуру не закрываем)
    final wasOpen = oldWidget.isPanelOpen ?? false;
    final isNowOpen = widget.isPanelOpen ?? false;
    if (wasOpen && !isNowOpen && _isExpanded) {
      setState(() {
        _isExpanded = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadScreens() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final screens = await (appDatabase.select(appDatabase.customTaskScreens)
            ..where((s) => s.userId.equals(userId))
            ..orderBy([(s) => dr.OrderingTerm.desc(s.createdAt)]))
          .get();

      setState(() {
        _screens = screens;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки экранов: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCreateScreen() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name.length > 15) return;

    final userId = UserSession.currentUserId;
    if (userId == null) return;

    try {
      final screenId = await appDatabase.into(appDatabase.customTaskScreens).insert(
        db.CustomTaskScreensCompanion(
          userId: dr.Value(userId),
          name: dr.Value(name),
        ),
      );

      _nameController.clear();
      // Скрываем клавиатуру и сворачиваем поле ввода
      _focusNode.unfocus();
      
      // Устанавливаем флаг нового экрана и сворачиваем поле
      setState(() {
        _isExpanded = false;
        _newlyCreatedScreenId = screenId;
      });
      
      // Загружаем экраны после установки флага
      await _loadScreens();

      // Прокручиваем к новому экрану с задержкой для анимации
      if (mounted && _newlyCreatedScreenId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted && _scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                );
              }
            });
            // Сбрасываем флаг после анимации
            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted) {
                setState(() {
                  _newlyCreatedScreenId = null;
                });
              }
            });
          }
        });
      }

      // Открываем страницу задач
      if (mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (_, animation, __) => FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
              child: CustomTasksPage(
                screenId: screenId,
                screenName: name,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Ошибка создания экрана: $e');
    }
  }

  void _openScreen(db.CustomTaskScreen screen) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: CustomTasksPage(
            screenId: screen.id,
            screenName: screen.name,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _isLoading
            ? const SizedBox.shrink()
            : GestureDetector(
                onTap: () {
                  // Перехватываем клики, чтобы не закрывать клавиатуру
                  if (_isExpanded && _focusNode.hasFocus) {
                    _focusNode.requestFocus();
                  }
                },
                behavior: HitTestBehavior.translucent,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ClipRect(
                      clipBehavior: Clip.none,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                    // Кнопка "Новый экран +"
                    Padding(
                      padding: const EdgeInsets.only(left: 0, right: 12),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isExpanded = true;
                          });
                          Future.delayed(const Duration(milliseconds: 100), () {
                            _focusNode.requestFocus();
                            // Прокручиваем к началу, чтобы поле ввода было видно
                            _scrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            );
                          });
                        },
                        child: SizedBox(
                          height: 32,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            width: _isExpanded ? 200 : null,
                            padding: EdgeInsets.only(
                              left: _isExpanded ? 15 : 16,
                              right: _isExpanded ? 6 : 16,
                              top: 7,
                              bottom: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            alignment: Alignment.center,
                            child: _isExpanded
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            // Перехватываем клики, чтобы не закрывать клавиатуру
                                            _focusNode.requestFocus();
                                          },
                                          child: ClipRect(
                                            child: SizedBox(
                                              height: 18,
                                              child: TextField(
                                                controller: _nameController,
                                                focusNode: _focusNode,
                                                maxLength: 15,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  height: 1.0,
                                                ),
                                                decoration: const InputDecoration(
                                                  hintText: 'Название экрана',
                                                  hintStyle: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 14,
                                                    height: 1.0,
                                                  ),
                                                  border: InputBorder.none,
                                                  counterText: '',
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.symmetric(vertical: 2),
                                                ),
                                                textAlignVertical: TextAlignVertical.center,
                                                onSubmitted: (_) => _handleCreateScreen(),
                                                enableInteractiveSelection: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: _handleCreateScreen,
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.add,
                                            size: 13,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : RichText(
                                    text: const TextSpan(
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        height: 1.0,
                                      ),
                                      children: [
                                        TextSpan(text: 'Новый экран '),
                                        TextSpan(
                                          text: '+',
                                          style: TextStyle(
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    // Горизонтальный скролл экранов
                    ..._screens.map((screen) {
                      final isNew = screen.id == _newlyCreatedScreenId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        key: ValueKey(screen.id),
                        child: TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          tween: Tween<double>(
                            begin: isNew ? 0.0 : 1.0,
                            end: 1.0,
                          ),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.scale(
                                scale: isNew ? 0.8 + (value * 0.2) : 1.0,
                                child: GestureDetector(
                                  onTap: () => _openScreen(screen),
                                  child: SizedBox(
                                    height: 32,
                                    child: Container(
                                      padding: const EdgeInsets.only(
                                        left: 16,
                                        right: 16,
                                        top: 7,
                                        bottom: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        screen.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          height: 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }).toList(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                ),
              ),
      ],
    );
  }
}

