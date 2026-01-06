import 'package:flutter/material.dart';

class MainHeader extends StatefulWidget {
  final VoidCallback? onMenuTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onGreetingToggle;
  final Function(DragUpdateDetails)? onGreetingPanUpdate;
  final Function(DragEndDetails)? onGreetingPanEnd;
  final bool isGreetingPanelOpen;
  final String? title;
  final bool hideSearchAndSettings;
  final bool showBackButton;
  final VoidCallback? onBack;

  const MainHeader({
    super.key,
    this.onMenuTap,
    required this.onSearchTap,
    this.onSettingsTap,
    this.onGreetingToggle,
    this.onGreetingPanUpdate,
    this.onGreetingPanEnd,
    this.isGreetingPanelOpen = false,
    this.title,
    this.hideSearchAndSettings = false,
    this.showBackButton = false,
    this.onBack,
  });

  @override
  State<MainHeader> createState() => _MainHeaderState();
}

class _MainHeaderState extends State<MainHeader> {
  double _settingsTurns = 0;

  void _spinSettings() {
    setState(() {
      _settingsTurns += 1 / 3; // 120 градусов
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 60,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Stack(
            children: [
              // Бургер меню слева
              if (widget.onMenuTap != null || widget.showBackButton)
                Positioned(
                  left: -6,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Transform.translate(
                      offset: widget.showBackButton ? const Offset(0, 1) : const Offset(0, 6),
                      child: widget.showBackButton
                          ? GestureDetector(
                              onTap: widget.onBack,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                width: 44,
                                height: 44,
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.arrow_back_ios_new,
                                  size: 20,
                                  color: Colors.black,
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: widget.onMenuTap,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                width: 44,
                                height: 44,
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: CustomPaint(
                                  size: const Size(24, 24),
                                  painter: BurgerMenuPainter(),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              // Заголовок по центру экрана
              Positioned.fill(
                child: Center(
                  child: Text(
                    widget.title ?? 'Все задачи',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // Поиск и настройки справа
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: widget.hideSearchAndSettings
                      ? const SizedBox(width: 24, height: 24)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: widget.onSearchTap,
                              child: Container(
                                width: 24,
                                height: 24,
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: Image.asset(
                                  'assets/icon/glass.png',
                                  width: 24,
                                  height: 24,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            MouseRegion(
                              onEnter: (_) => _spinSettings(),
                              onHover: (_) => _spinSettings(),
                              child: GestureDetector(
                                onTap: () {
                                  _spinSettings();
                                  widget.onSettingsTap?.call();
                                },
                                child: AnimatedRotation(
                                  duration: const Duration(milliseconds: 200),
                                  turns: _settingsTurns,
                                  curve: Curves.easeOut,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    color: Colors.transparent,
                                    alignment: Alignment.center,
                                    child: Image.asset(
                                      'assets/icon/settings.png',
                                      width: 24,
                                      height: 24,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
        // Header divider для открытия шторки
        if (widget.onGreetingToggle != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: widget.onGreetingToggle,
                onPanUpdate: widget.onGreetingPanUpdate,
                onPanEnd: widget.onGreetingPanEnd,
                child: Container(
                  width: 150, // Увеличена область тапа
                  height: 40, // Увеличена область тапа
                  color: Colors.transparent, // Прозрачный цвет для корректной работы hit testing
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: 45, // Размер самой черточки остается прежним
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC2C1C1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class BurgerMenuPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Верхняя линия
    canvas.drawLine(
      const Offset(3, 2),
      const Offset(21, 2),
      paint,
    );
    // Средняя линия
    canvas.drawLine(
      const Offset(3, 8),
      const Offset(21, 8),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

