import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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
      });
    }
  }

  void _handlePanStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      final screenHeight = MediaQuery.of(context).size.height;
      final totalHeight = screenHeight * 0.4; // 40% экрана
      
      // Обновляем offset в зависимости от направления перетаскивания
      if (widget.isOpen) {
        // При открытой панели: перетаскивание вверх (положительный delta.dy) закрывает панель
        _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, totalHeight);
      } else {
        // При закрытой панели: перетаскивание вниз (положительный delta.dy) открывает панель
        // Увеличиваем _dragOffset, чтобы topPosition = -totalHeight + _dragOffset приближался к 0
        _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, totalHeight);
      }
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final totalHeight = screenHeight * 0.4; // 40% экрана
    
    // Определяем, нужно ли открыть или закрыть панель
    final threshold = totalHeight * 0.3; // 30% от высоты панели
    
    if (widget.isOpen) {
      // Если панель открыта и перетащена больше порога вверх - закрываем
      if (_dragOffset > threshold || details.velocity.pixelsPerSecond.dy > 500) {
        widget.onToggle();
      }
    } else {
      // Если панель закрыта и перетащена больше порога вниз - открываем
      // При перетаскивании вниз velocity будет положительной
      if (_dragOffset > threshold || details.velocity.pixelsPerSecond.dy > 500) {
        widget.onToggle();
      }
    }
    
    setState(() {
      _isDragging = false;
      _dragOffset = 0.0;
    });
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
    final totalHeight = screenHeight * 0.4; // 40% экрана
    final bgPath = _getBackgroundImage();
    final isNight = bgPath.contains('night');
    
    // Вычисляем позицию с учетом перетаскивания
    double topPosition;
    if (widget.isOpen) {
      // При открытой панели: начинаем с 0, перетаскивание вверх увеличивает topPosition
      topPosition = _dragOffset;
    } else {
      // При закрытой панели: начинаем с -totalHeight, перетаскивание вниз уменьшает отрицательное значение
      topPosition = -totalHeight + _dragOffset;
    }
    
    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      top: topPosition,
      left: 0,
      right: 0,
      height: totalHeight,
      child: GestureDetector(
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
              Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 20,
                  left: 20,
                  right: 20,
                  bottom: 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 24),
                    // Приветствие
                    Text(
                      _getGreeting(),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Статистика
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сегодня у вас: ${_pluralizeTasks(widget.totalTasksToday)}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Выполнено: ${_pluralizeTasks(widget.completedTasksToday)}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Разделитель внизу
                    Center(
                      child: GestureDetector(
                        onTap: widget.onToggle,
                        child: Container(
                          width: 45,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ],
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
        final value = (controller.value + delay) % 1.0;
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
                    color: Colors.white.withOpacity(glowOpacity),
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

