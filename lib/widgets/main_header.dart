import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

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
  final String? searchIconPath;
  // Иконка правой кнопки. Если null — показываем колокольчик (уведомления).
  final String? settingsIconPath;

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
    this.searchIconPath,
    this.settingsIconPath,
  });

  @override
  State<MainHeader> createState() => _MainHeaderState();
}

class _MainHeaderState extends State<MainHeader> {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Stack(
      children: [
        Container(
          height: 60,
          color: colors.background,
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
                                child: Icon(
                                  // Стандартный шеврон "назад" как в iOS.
                                  CupertinoIcons.back,
                                  size: 24,
                                  color: colors.icon,
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
                                  painter: BurgerMenuPainter(color: colors.icon),
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
                    widget.title ?? tr('Все задачи'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
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
                                  widget.searchIconPath ?? 'assets/icon/glass.png',
                                  width: 24,
                                  height: 24,
                                  fit: BoxFit.contain,
                                  // В тёмной теме перекрашиваем чёрную PNG-иконку в белую.
                                  color: colors.isDark ? colors.icon : null,
                                  colorBlendMode: colors.isDark ? BlendMode.srcIn : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: widget.onSettingsTap,
                              child: Container(
                                width: 24,
                                height: 24,
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                // По умолчанию — колокольчик (уведомления).
                                // Если задан settingsIconPath — кастомная иконка
                                // (напр. делегирование на кастомных экранах).
                                child: widget.settingsIconPath != null
                                    ? Image.asset(
                                        widget.settingsIconPath!,
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.contain,
                                        color: colors.isDark ? colors.icon : null,
                                        colorBlendMode:
                                            colors.isDark ? BlendMode.srcIn : null,
                                      )
                                    : Icon(
                                        CupertinoIcons.bell,
                                        size: 23,
                                        color: colors.icon,
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
                child: Container(
                  width: 150,
                  height: 40,
                  color: Colors.transparent,
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: 45,
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
  final Color color;

  BurgerMenuPainter({this.color = Colors.black});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
  bool shouldRepaint(covariant BurgerMenuPainter oldDelegate) =>
      oldDelegate.color != color;
}

