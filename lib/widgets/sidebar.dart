import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'dart:math' as math;
import '../pages/subscription_page.dart';

class Sidebar extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback? onTasksTap;
  final VoidCallback? onChatTap;

  const Sidebar({
    super.key,
    required this.isOpen,
    required this.onClose,
    this.onTasksTap,
    this.onChatTap,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _starsAnimationController;
  late AnimationController _fallingStarController;
  Timer? _scrollTimer;
  Timer? _fallingStarTimer;
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _starsAnimationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _fallingStarController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    if (widget.isOpen) {
      _animationController.forward();
      _startScrolling();
      _startFallingStarAnimation();
    }
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _animationController.forward();
        _startScrolling();
        _startFallingStarAnimation();
      } else {
        _animationController.reverse();
        _stopScrolling();
        _stopFallingStarAnimation();
      }
    }
  }

  void _startScrolling() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.offset + 2,
          duration: const Duration(milliseconds: 50),
          curve: Curves.linear,
        );
        if (_scrollController.offset >= _scrollController.position.maxScrollExtent) {
          _scrollController.jumpTo(0);
        }
      }
    });
  }

  void _stopScrolling() {
    _scrollTimer?.cancel();
  }

  void _startFallingStarAnimation() {
    _fallingStarTimer?.cancel();
    _fallingStarTimer = Timer.periodic(const Duration(seconds: 14), (timer) {
      if (mounted && widget.isOpen) {
        _fallingStarController.forward(from: 0).then((_) {
          if (mounted) {
            _fallingStarController.reset();
          }
        });
      }
    });
    // Запускаем первую анимацию сразу
    _fallingStarController.forward(from: 0).then((_) {
      if (mounted) {
        _fallingStarController.reset();
      }
    });
  }

  void _stopFallingStarAnimation() {
    _fallingStarTimer?.cancel();
    _fallingStarController.reset();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _starsAnimationController.dispose();
    _fallingStarController.dispose();
    _scrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen && _animationController.value == 0) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !widget.isOpen,
        child: FadeTransition(
          opacity: _animationController,
          child: Container(
            color: Colors.white,
            child: Stack(
              children: [
                // Фон для закрытия (перехватывает клики на пустое место)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                // Бегущая строка с safe zone
                Positioned(
                  top: -10,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).padding.top + 50,
                  child: GestureDetector(
                    onTap: () {}, // Блокируем закрытие при клике на бегущую строку
                    child: Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top,
                      ),
                      color: Colors.white,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(
                            30,
                            (index) => const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                'Ladder',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Контент сайдбара
                Positioned(
                  top: MediaQuery.of(context).padding.top + 20,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {}, // Блокируем закрытие при клике на контент
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 340),
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildSidebarItem(
                                  text: 'Чат с AI',
                                  onTap: () {
                                    // Если передан callback чата — вызываем, иначе просто закрываем
                                    if (widget.onChatTap != null) {
                                      widget.onChatTap!();
                                    } else {
                                      widget.onClose();
                                    }
                                  },
                                ),
                                const SizedBox(height: 14),
                                _buildSidebarItem(
                                  text: 'Задачи',
                                  onTap: () {
                                    widget.onTasksTap?.call();
                                    widget.onClose();
                                  },
                                ),
                                const SizedBox(height: 14),
                                _buildSidebarItem(
                                  text: 'Информация',
                                  onTap: () {},
                                ),
                                const SizedBox(height: 14),
                                _buildSidebarItem(
                                  text: 'Поддержка',
                                  onTap: () {},
                                ),
                                const SizedBox(height: 14),
                                _buildSidebarItem(
                                  text: 'Предложить идею',
                                  onTap: () {},
                                ),
                                const SizedBox(height: 14),
                                // Баннер подписки
                                _buildSubscriptionBanner(),
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
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionBanner() {
    return GestureDetector(
      onTap: () {
        widget.onClose();
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const SubscriptionPage(),
          ),
        );
      },
      child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF58ABF5),
            Color(0xFF2037E7),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Контент баннера
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Ladder',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Basic',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Оформи Pro, чтобы получить больше',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          // Мерцающие звезды
          ..._buildTwinklingStars(),
          // Падающая звезда
          _buildFallingStar(),
        ],
      ),
      ),
    );
  }
  
  Widget _buildFallingStar() {
    return AnimatedBuilder(
      animation: _fallingStarController,
      builder: (context, child) {
        final value = _fallingStarController.value.clamp(0.0, 1.0);
        // Звезда появляется вверху слева и плавно падает вниз вправо
        final startX = 60.0;
        final endX = 240.0;
        final startY = 0.0;
        final endY = 65.0;
        
        // Используем кривую для плавного движения
        final curveValue = Curves.easeInOut.transform(value);
        
        final x = startX + (endX - startX) * curveValue;
        final y = startY + (endY - startY) * curveValue;
        
        // Плавное появление и исчезновение
        final opacity = value < 0.15 
            ? (value / 0.15).clamp(0.0, 1.0)
            : value > 0.85
                ? ((1.0 - value) / 0.15).clamp(0.0, 1.0)
                : 1.0;
        
        return Positioned(
          left: x - 2,
          top: y - 2,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity((opacity * 0.9).clamp(0.0, 1.0)),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildTwinklingStars() {
    final stars = <Widget>[];
    // 20 звездочек, равномерно распределенных по всей поверхности баннера
    final positions = [
      const Offset(20, 8),   // Верхний ряд
      const Offset(70, 6),
      const Offset(120, 10),
      const Offset(170, 8),
      const Offset(220, 6),
      const Offset(270, 10),
      const Offset(40, 20),  // Второй ряд
      const Offset(90, 22),
      const Offset(140, 18),
      const Offset(190, 20),
      const Offset(240, 22),
      const Offset(30, 35),  // Третий ряд
      const Offset(80, 32),
      const Offset(130, 36),
      const Offset(180, 34),
      const Offset(230, 38),
      const Offset(50, 48),  // Нижний ряд
      const Offset(100, 50),
      const Offset(150, 46),
      const Offset(200, 52),
      const Offset(260, 48),  // 20-я звезда
    ];

    for (int i = 0; i < positions.length; i++) {
      final delay = i * 0.2;
      stars.add(
        Positioned(
          left: positions[i].dx,
          top: positions[i].dy,
          child: _TwinklingStar(
            animationController: _starsAnimationController,
            delay: delay,
          ),
        ),
    );
    }
    return stars;
  }
}

class _TwinklingStar extends StatelessWidget {
  final AnimationController animationController;
  final double delay;

  const _TwinklingStar({
    required this.animationController,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animationController,
      builder: (context, child) {
        // Создаем плавную синусоидальную анимацию с задержкой
        final controllerValue = animationController.value.clamp(0.0, 1.0);
        final value = ((controllerValue + delay) % 1.0).clamp(0.0, 1.0);
        final sineValue = math.sin(value * 2 * math.pi);
        // Преобразуем синус от -1..1 в 0..1, чтобы opacity доходил до 0
        final opacity = (0.5 + 0.5 * sineValue).clamp(0.0, 1.0);
        final scale = 0.9 + (0.3 * (0.5 + 0.5 * sineValue));

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity((opacity * 0.8).clamp(0.0, 1.0)),
                    blurRadius: 3,
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

