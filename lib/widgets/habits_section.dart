import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../models/habit.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

/// Секция привычек на странице Задач: список привычек, запланированных на
/// выбранный день, с отметкой выполнения и мини-серией. Сворачивается.
class HabitsSection extends StatefulWidget {
  final List<HabitWithStats> habits;
  final ValueChanged<int> onToggle; // habitId
  final ValueChanged<Habit> onEdit;
  final ValueChanged<int> onDelete; // habitId
  final bool canToggle; // отмечать можно только за сегодня

  const HabitsSection({
    super.key,
    required this.habits,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.canToggle = true,
  });

  @override
  State<HabitsSection> createState() => _HabitsSectionState();
}

class _HabitsSectionState extends State<HabitsSection> {
  bool _expanded = true;
  OverlayEntry? _menuOverlay;

  @override
  void dispose() {
    _menuOverlay?.remove();
    _menuOverlay = null;
    super.dispose();
  }

  void _toggleExpanded() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  void _showMenu(HabitWithStats h, Offset position) {
    HapticFeedback.mediumImpact();
    _menuOverlay?.remove();
    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;
    const menuWidth = 200.0;
    double left = position.dx;
    if (left + menuWidth > screenSize.width - 12) {
      left = screenSize.width - 12 - menuWidth;
    }
    if (left < 12) left = 12;
    double top = position.dy;
    if (top + 110 > screenSize.height - 12) {
      top = screenSize.height - 12 - 110;
    }
    _menuOverlay = OverlayEntry(
      builder: (_) => _HabitMenu(
        left: left,
        top: top,
        width: menuWidth,
        onEdit: () {
          _menuOverlay?.remove();
          _menuOverlay = null;
          widget.onEdit(h.habit);
        },
        onDelete: () {
          _menuOverlay?.remove();
          _menuOverlay = null;
          HapticFeedback.heavyImpact();
          widget.onDelete(h.habit.id!);
        },
        onClose: () {
          _menuOverlay?.remove();
          _menuOverlay = null;
        },
      ),
    );
    overlay.insert(_menuOverlay!);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // Показываем только запланированные на выбранный день привычки.
    final scheduled =
        widget.habits.where((h) => h.scheduledToday).toList();
    if (scheduled.isEmpty) return const SizedBox.shrink();

    final doneCount = scheduled.where((h) => h.completedToday).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок секции с прогрессом и сворачиванием
          GestureDetector(
            onTap: _toggleExpanded,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Text(
                    tr('Привычки'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$doneCount/${scheduled.length}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 240),
                    turns: _expanded ? 0.0 : -0.25,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Список привычек
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    children: [
                      for (final h in scheduled)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _HabitRow(
                            key: ValueKey(h.habit.id),
                            data: h,
                            canToggle: widget.canToggle,
                            onToggle: () => widget.onToggle(h.habit.id!),
                            onLongPress: (pos) => _showMenu(h, pos),
                          ),
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _HabitRow extends StatefulWidget {
  final HabitWithStats data;
  final bool canToggle;
  final VoidCallback onToggle;
  final ValueChanged<Offset> onLongPress;

  const _HabitRow({
    super.key,
    required this.data,
    required this.canToggle,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  State<_HabitRow> createState() => _HabitRowState();
}

class _HabitRowState extends State<_HabitRow>
    with TickerProviderStateMixin {
  late AnimationController _pressController;
  // Бесконечно крутится — гоняет оранжево-белый градиент по бордеру
  // выполненной привычки.
  late AnimationController _borderController;
  Offset _pressPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.04,
      vsync: this,
    );
    _borderController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pressController.dispose();
    _borderController.dispose();
    super.dispose();
  }

  void _handleToggle() {
    // За прошлые/будущие дни отмечать нельзя.
    if (!widget.canToggle) {
      HapticFeedback.lightImpact();
      return;
    }
    HapticFeedback.lightImpact();
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final h = widget.data;
    final done = h.completedToday;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          // Кружок-отметка (в цвете привычки)
          _CheckCircle(done: done, color: h.habit.color),
          const SizedBox(width: 12),
          // Название + расписание
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  h.habit.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: done ? colors.textTertiary : colors.textPrimary,
                  ),
                ),
                    const SizedBox(height: 2),
                    Text(
                      tr(h.habit.scheduleLabel),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // Мини-серия
              if (h.streak > 0) ...[
                const SizedBox(width: 8),
                _StreakPill(
                  streak: h.streak,
                  atRisk: h.atRisk,
                  icon: h.habit.icon,
                  color: h.habit.color,
                ),
              ],
            ],
          ),
        );

    return GestureDetector(
      onTap: _handleToggle,
      onTapDown: (d) {
        _pressPosition = d.globalPosition;
        _pressController.forward();
      },
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onLongPress: () => widget.onLongPress(_pressPosition),
      child: AnimatedBuilder(
        animation: done
            ? Listenable.merge([_pressController, _borderController])
            : _pressController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1 - _pressController.value,
            // Градиент рисуется ТОЛЬКО по периметру (поверх контента), сам
            // блок остаётся чистым. Белый блик плавно бежит вдоль бордера.
            child: done
                ? CustomPaint(
                    foregroundPainter: _RunningBorderPainter(
                      t: _borderController.value,
                      color: h.habit.color,
                    ),
                    child: child,
                  )
                : child,
          );
        },
        child: content,
      ),
    );
  }
}

// Рисует тонкий (1px) бордер цвета привычки с белым бликом, который плавно
// бежит по периметру. Только обводка — заливки нет.
class _RunningBorderPainter extends CustomPainter {
  final double t; // 0..1 — позиция блика по периметру
  final Color color; // цвет бордера = цвет привычки
  const _RunningBorderPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 1.5;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      const Radius.circular(20),
    );
    final shader = SweepGradient(
      // Сплошной бордер цвета привычки с одним узким белым бликом.
      colors: [color, color, Colors.white, color, color],
      stops: const [0.0, 0.38, 0.5, 0.62, 1.0],
      transform: GradientRotation(t * 2 * math.pi),
    ).createShader(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = shader;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_RunningBorderPainter old) =>
      old.t != t || old.color != color;
}

// Анимированный кружок-отметка: пустое кольцо → заливка цветом + галочка.
class _CheckCircle extends StatelessWidget {
  final bool done;
  final Color color; // цвет, выбранный при создании привычки

  const _CheckCircle({required this.done, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // Мягкая серая рамка, пока не выполнено; заливка цветом привычки + белая
    // галочка после выполнения.
    final idleBorder =
        colors.isDark ? colors.textTertiary : const Color(0xFFB8B8BD);
    // Чекбокс как у задач: скруглённый квадрат 24×24, белая галочка.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: done ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: done ? color : idleBorder,
          width: 2,
        ),
      ),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        scale: done ? 1.0 : 0.0,
        child: const Icon(
          Icons.check,
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }
}

// Пилюля серии: значок привычки + число подряд.
class _StreakPill extends StatelessWidget {
  final int streak;
  final bool atRisk;
  final IconData icon; // выбранный значок привычки
  final Color color; // цвет привычки

  const _StreakPill({
    required this.streak,
    required this.atRisk,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // Подложка и значок — в цвете привычки; жёлтый оттенок предупреждает,
    // что серия под угрозой (сегодня ещё не отмечена).
    final tint = atRisk ? const Color(0xFFFFB800) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: atRisk ? 0.16 : 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: tint,
          ),
          const SizedBox(width: 3),
          Text(
            '$streak',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// Контекстное меню привычки (стиль iOS 26, как меню задач).
class _HabitMenu extends StatefulWidget {
  final double left;
  final double top;
  final double width;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const _HabitMenu({
    required this.left,
    required this.top,
    required this.width,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<_HabitMenu> createState() => _HabitMenuState();
}

class _HabitMenuState extends State<_HabitMenu>
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
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => _close(widget.onClose),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Positioned(
              left: widget.left,
              top: widget.top,
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
                      alignment: Alignment.topLeft,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                                  _item(CupertinoIcons.pencil,
                                      tr('Редактировать'),
                                      () => _close(widget.onEdit)),
                                  _divider(),
                                  _item(CupertinoIcons.delete, tr('Удалить'),
                                      () => _close(widget.onDelete),
                                      color: const Color(0xFFFF3B30)),
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
    );
  }

  Widget _divider() {
    final colors = AppColors.of(context);
    return Container(
      height: 0.5,
      color: colors.isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.07),
    );
  }

  Widget _item(IconData icon, String text, VoidCallback onTap, {Color? color}) {
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
