import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart';

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
  late Animation<double> _offsetAnimation;
  static const double _edgeThreshold = 30.0;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _offsetAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Используем анимацию, если не тянем, иначе используем реальное значение
    final currentOffset = _isDragging 
        ? _dragOffset 
        : _animatedOffset * screenWidth;
    final progress = (currentOffset / screenWidth).clamp(0.0, 1.0);
    
    // Слушаем анимацию для плавного движения
    _offsetAnimation.addListener(() {
      if (!_isDragging) {
        setState(() {
          _animatedOffset = _offsetAnimation.value;
        });
      }
    });
    
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
          
          if (shouldComplete) {
            // Анимируем до конца экрана плавно
            _animationController.value = _dragOffset / screenWidth;
            _animatedOffset = _dragOffset / screenWidth;
            _animationController.forward().then((_) {
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
            // Анимируем обратно к началу плавно
            _animationController.value = _dragOffset / screenWidth;
            _animatedOffset = _dragOffset / screenWidth;
            _animationController.reverse();
          }
          
          _pointerId = null;
          setState(() {
            _isDragging = false;
            _dragOffset = 0;
          });
        }
      },
      onPointerCancel: (event) {
        if (_pointerId == event.pointer) {
          final screenWidth = MediaQuery.of(context).size.width;
          _animationController.value = _dragOffset / screenWidth;
          _animatedOffset = _dragOffset / screenWidth;
          _animationController.reverse();
          _pointerId = null;
          setState(() {
            _isDragging = false;
            _dragOffset = 0;
          });
        }
      },
      child: Stack(
        children: [
          // Предыдущий экран (остается на месте, слегка затемняется) - как в CupertinoPageRoute
          if (progress > 0)
            Positioned.fill(
              child: Container(
                color: Colors.white,
                child: widget.previousScreen != null
                    ? Opacity(
                        opacity: 1.0 - (0.3 * progress), // Легкое затемнение при свайпе
                        child: widget.previousScreen!,
                      )
                    : Container(
                        // Если предыдущий экран не передан, показываем затемненный фон
                        color: Colors.grey[100]?.withOpacity(1.0 - (0.3 * progress)),
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
                color: Colors.white,
                boxShadow: progress > 0
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1 * progress),
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

