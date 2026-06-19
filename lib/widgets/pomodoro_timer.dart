import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

/// Фаза цикла Pomodoro.
enum _PomodoroPhase { work, shortBreak, longBreak }

/// Полноэкранный таймер Pomodoro в стилистике приложения (liquid glass,
/// плавные анимации). Запускается по тапу на заметку таймлайна.
class PomodoroTimer extends StatefulWidget {
  final String noteTitle;
  final Color accentColor;

  const PomodoroTimer({
    super.key,
    required this.noteTitle,
    required this.accentColor,
  });

  @override
  State<PomodoroTimer> createState() => _PomodoroTimerState();
}

class _PomodoroTimerState extends State<PomodoroTimer>
    with TickerProviderStateMixin {
  // Длительности фаз (в секундах) — классические интервалы Pomodoro.
  static const int _workSeconds = 25 * 60;
  static const int _shortBreakSeconds = 5 * 60;
  static const int _longBreakSeconds = 15 * 60;
  static const int _pomodorosBeforeLongBreak = 4;

  _PomodoroPhase _phase = _PomodoroPhase.work;
  late int _totalSeconds;
  late int _remainingSeconds;
  bool _isRunning = false;
  int _completedPomodoros = 0;
  Timer? _ticker;

  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<double> _entranceScale;
  // Лёгкая пульсация кольца во время работы таймера.
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _totalSeconds = _workSeconds;
    _remainingSeconds = _workSeconds;

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _entranceScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceController.forward();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2600),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color get _phaseColor {
    switch (_phase) {
      case _PomodoroPhase.work:
        return widget.accentColor;
      case _PomodoroPhase.shortBreak:
      case _PomodoroPhase.longBreak:
        return const Color(0xFF34C759);
    }
  }

  String get _phaseLabel {
    switch (_phase) {
      case _PomodoroPhase.work:
        return tr('Фокус');
      case _PomodoroPhase.shortBreak:
        return tr('Перерыв');
      case _PomodoroPhase.longBreak:
        return tr('Длинный перерыв');
    }
  }

  void _toggleRunning() {
    HapticFeedback.mediumImpact();
    if (_isRunning) {
      _pause();
    } else {
      _start();
    }
  }

  void _start() {
    if (_remainingSeconds <= 0) return;
    setState(() => _isRunning = true);
    _pulseController.repeat(reverse: true);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        }
      });
      if (_remainingSeconds <= 0) {
        _onPhaseComplete();
      }
    });
  }

  void _pause() {
    _ticker?.cancel();
    _ticker = null;
    _pulseController.stop();
    setState(() => _isRunning = false);
  }

  void _resetPhase() {
    HapticFeedback.lightImpact();
    _ticker?.cancel();
    _ticker = null;
    _pulseController.stop();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _totalSeconds;
    });
  }

  void _onPhaseComplete() {
    HapticFeedback.heavyImpact();
    _ticker?.cancel();
    _ticker = null;
    _pulseController.stop();
    if (_phase == _PomodoroPhase.work) {
      _completedPomodoros++;
    }
    _goToNextPhase(autoStart: false);
  }

  void _skipPhase() {
    HapticFeedback.selectionClick();
    _ticker?.cancel();
    _ticker = null;
    _pulseController.stop();
    _goToNextPhase(autoStart: false);
  }

  // Переход к следующей фазе по правилу Pomodoro: после 4 «фокусов» —
  // длинный перерыв, иначе короткий; после перерыва — снова «фокус».
  void _goToNextPhase({required bool autoStart}) {
    _PomodoroPhase next;
    if (_phase == _PomodoroPhase.work) {
      next = _completedPomodoros % _pomodorosBeforeLongBreak == 0
          ? _PomodoroPhase.longBreak
          : _PomodoroPhase.shortBreak;
    } else {
      next = _PomodoroPhase.work;
    }
    setState(() {
      _phase = next;
      _totalSeconds = switch (next) {
        _PomodoroPhase.work => _workSeconds,
        _PomodoroPhase.shortBreak => _shortBreakSeconds,
        _PomodoroPhase.longBreak => _longBreakSeconds,
      };
      _remainingSeconds = _totalSeconds;
      _isRunning = false;
    });
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final progress = _totalSeconds == 0 ? 0.0 : _remainingSeconds / _totalSeconds;
    final accent = _phaseColor;

    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
      opacity: _entranceFade,
      child: Stack(
        children: [
          // Затемнённый размытый фон поверх таймлайна.
          Positioned.fill(
            child: GestureDetector(
              onTap: () {},
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  color: (colors.isDark ? Colors.black : Colors.white)
                      .withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          SafeArea(
            child: ScaleTransition(
              scale: _entranceScale,
              child: Column(
                children: [
                  // Верхняя панель: закрыть + название заметки.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        _GlassIconButton(
                          icon: CupertinoIcons.xmark,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        _GlassIconButton(
                          icon: CupertinoIcons.arrow_counterclockwise,
                          onTap: _resetPhase,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Название заметки.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      widget.noteTitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Метка фазы.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      key: ValueKey(_phase),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _phaseLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Кольцо прогресса с таймером по центру.
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final pulse = _isRunning
                          ? 1.0 + 0.012 * math.sin(_pulseController.value * math.pi)
                          : 1.0;
                      return Transform.scale(scale: pulse, child: child);
                    },
                    child: SizedBox(
                      width: 260,
                      height: 260,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Плавная прокрутка дуги между секундными тиками.
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: progress),
                            duration: const Duration(milliseconds: 950),
                            curve: Curves.linear,
                            builder: (context, value, _) {
                              return CustomPaint(
                                size: const Size(260, 260),
                                painter: _RingPainter(
                                  progress: value,
                                  color: accent,
                                  trackColor: colors.isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.06),
                                ),
                              );
                            },
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatTime(_remainingSeconds),
                                style: TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: colors.textPrimary,
                                  fontFeatures: const [
                                    ui.FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tr('Помидоров: {0}', [_completedPomodoros]),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Нижний отступ больше верхнего — кольцо таймера
                  // поднимается ближе к центру экрана.
                  const Spacer(flex: 2),
                  // Управление: главная кнопка Старт/Пауза + пропуск фазы.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Симметричный отступ под пропуском (пустой плейсхолдер).
                        const SizedBox(width: 54),
                        const SizedBox(width: 28),
                        _PlayPauseButton(
                          isRunning: _isRunning,
                          color: accent,
                          onTap: _toggleRunning,
                        ),
                        const SizedBox(width: 28),
                        // Кнопка переключения фазы (режима) — справа.
                        _GlassIconButton(
                          icon: CupertinoIcons.forward_end,
                          onTap: _skipPhase,
                          size: 54,
                          iconSize: 20,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Круглая стеклянная кнопка-иконка.
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.05),
              border: Border.all(
                color: colors.isDark
                    ? Colors.white.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Icon(icon, size: iconSize, color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Главная кнопка Старт/Пауза с плавной сменой иконки.
class _PlayPauseButton extends StatelessWidget {
  final bool isRunning;
  final Color color;
  final VoidCallback onTap;

  const _PlayPauseButton({
    required this.isRunning,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            isRunning ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
            key: ValueKey(isRunning),
            size: 34,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Рисует фоновое кольцо и дугу прогресса (по часовой от 12 часов).
class _RingPainter extends CustomPainter {
  final double progress; // 0..1 — доля оставшегося времени
  final Color color;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.trackColor != trackColor;
}
