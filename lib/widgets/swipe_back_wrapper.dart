import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Обертка для добавления iOS-стиля жеста "назад" свайпом слева направо
class SwipeBackWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeBack;
  final Widget? previousScreen; // Виджет предыдущего экрана для отображения при свайпе

  const SwipeBackWrapper({
    super.key,
    required this.child,
    this.onSwipeBack,
    this.previousScreen,
  });

  @override
  State<SwipeBackWrapper> createState() => _SwipeBackWrapperState();
}

class _SwipeBackWrapperState extends State<SwipeBackWrapper> with SingleTickerProviderStateMixin {
  double _dragStartX = 0;
  double _dragOffset = 0;
  double _animatedOffset = 0;
  bool _isDragging = false;
  int? _pointerId;
  DateTime? _lastMoveTime;
  double _lastMoveX = 0;
  late AnimationController _animationController;
  static const double _edgeThreshold = 30.0;
  // Базовая длительность снапа; реальная масштабируется по остатку пути,
  // чтобы короткий доводок не тянулся и не казался «рывком».
  static const int _snapDurationMs = 320;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _snapDurationMs),
    );
    // Один-единственный слушатель: гонит смещение напрямую из контроллера
    // (линейно, без CurvedAnimation-ремапа → нет скачка при отпускании).
    _animationController.addListener(() {
      if (!_isDragging) {
        setState(() => _animatedOffset = _animationController.value);
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    // Используем анимацию, если не тянем, иначе используем реальное значение
    final currentOffset = _isDragging
        ? _dragOffset
        : _animatedOffset * screenWidth;
    final progress = (currentOffset / screenWidth).clamp(0.0, 1.0);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        // Начинаем жест только если он начинается от левого края (в пределах 30px)
        if (event.position.dx <= _edgeThreshold && _pointerId == null) {
          // Проверяем, можно ли вернуться назад
          final navigator = Navigator.maybeOf(context);
          final canSwipe = widget.onSwipeBack != null || 
                          (navigator != null && navigator.canPop());
          if (canSwipe) {
            _pointerId = event.pointer;
            setState(() {
              _dragStartX = event.position.dx;
              _dragOffset = 0;
              _animatedOffset = 0;
              _isDragging = true;
              _lastMoveTime = DateTime.now();
              _lastMoveX = event.position.dx;
              _animationController.reset();
            });
          }
        }
      },
      onPointerMove: (event) {
        if (_isDragging && _pointerId == event.pointer) {
          final newOffset = event.position.dx - _dragStartX;
          // Ограничиваем движение только вправо
          if (newOffset > 0) {
            setState(() {
              _dragOffset = newOffset;
              _lastMoveX = event.position.dx;
              _lastMoveTime = DateTime.now();
            });
          } else {
            setState(() {
              _dragOffset = 0;
            });
          }
        }
      },
      onPointerUp: (event) {
        if (_isDragging && _pointerId == event.pointer) {
          final screenWidth = MediaQuery.of(context).size.width;
          
          // Вычисляем скорость на основе последних движений
          double velocity = 0;
          if (_lastMoveTime != null) {
            final timeDelta = DateTime.now().difference(_lastMoveTime!).inMilliseconds;
            if (timeDelta > 0) {
              final distanceDelta = event.position.dx - _lastMoveX;
              velocity = (distanceDelta / timeDelta) * 1000; // пикселей в секунду
            }
          }
          
          // Определяем, нужно ли завершить переход
          final shouldComplete = _dragOffset > screenWidth * 0.3 || velocity > 300;

          final start = (_dragOffset / screenWidth).clamp(0.0, 1.0);
          _pointerId = null;
          // Снимаем флаг drag и синхронизируем анимируемое смещение со стартовой
          // позицией ДО запуска анимации — иначе первый кадр прыгнет.
          setState(() {
            _isDragging = false;
            _dragOffset = 0;
            _animatedOffset = start;
          });
          _animationController.value = start;

          if (shouldComplete) {
            // animateTo стартует из текущего значения (без ремапа кривой) →
            // плавный доводок до края. Минимум 200мс даже при коротком остатке,
            // чтобы доводок (когда старая страница доезжает за край и текущая
            // заполняет экран) не «щёлкал» резко, а мягко завершался.
            // easeOutCubic даёт плавное затухание скорости у самого края →
            // передача управления (pop / onSwipeBack) проходит незаметно.
            final ms = ((1.0 - start) * _snapDurationMs).clamp(200, _snapDurationMs).round();
            _animationController
                .animateTo(1.0,
                    duration: Duration(milliseconds: ms),
                    curve: Curves.easeOutCubic)
                .then((_) {
              if (!mounted) return;
              if (widget.onSwipeBack != null) {
                widget.onSwipeBack!();
              } else {
                final navigator = Navigator.maybeOf(context);
                if (navigator != null && navigator.canPop()) {
                  navigator.pop();
                }
              }
            });
          } else {
            final ms = (start * _snapDurationMs).clamp(120, _snapDurationMs).round();
            _animationController.animateBack(0.0,
                duration: Duration(milliseconds: ms), curve: Curves.easeOut);
          }
        }
      },
      onPointerCancel: (event) {
        if (_pointerId == event.pointer) {
          final screenWidth = MediaQuery.of(context).size.width;
          final start = (_dragOffset / screenWidth).clamp(0.0, 1.0);
          _pointerId = null;
          setState(() {
            _isDragging = false;
            _dragOffset = 0;
            _animatedOffset = start;
          });
          _animationController.value = start;
          final ms = (start * _snapDurationMs).clamp(120, _snapDurationMs).round();
          _animationController.animateBack(0.0,
              duration: Duration(milliseconds: ms), curve: Curves.easeOut);
        }
      },
      child: Stack(
        children: [
          // Предыдущий экран: едет из-под текущего (параллакс) и проявляется
          // по мере завершения свайпа — как в CupertinoPageRoute. При progress=1
          // он на месте и при полной яркости, поэтому передача управления
          // (pop / onSwipeBack) проходит бесшовно, без вспышки.
          if (progress > 0)
            Positioned.fill(
              child: Container(
                color: colors.background,
                child: widget.previousScreen != null
                    ? Transform.translate(
                        // Сдвиг влево на четверть экрана в начале → к 0 в конце.
                        offset: Offset(-screenWidth * 0.25 * (1 - progress), 0),
                        child: Opacity(
                          opacity: 0.7 + 0.3 * progress,
                          child: widget.previousScreen!,
                        ),
                      )
                    : Container(
                        color: colors.surfaceVariant
                            .withValues(alpha: 0.7 + 0.3 * progress),
                      ),
              ),
            ),
          // Текущий экран (двигается вправо, "снимается" с предыдущего)
          Positioned(
            left: currentOffset,
            top: 0,
            bottom: 0,
            right: -currentOffset,
            child: Container(
              decoration: BoxDecoration(
                color: colors.background,
                boxShadow: progress > 0
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1 * progress),
                          blurRadius: 10 * progress,
                          offset: Offset(0, 0),
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

