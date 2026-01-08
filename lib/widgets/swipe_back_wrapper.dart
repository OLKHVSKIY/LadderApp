import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Обертка для добавления iOS-стиля жеста "назад" свайпом слева направо
class SwipeBackWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeBack;

  const SwipeBackWrapper({
    super.key,
    required this.child,
    this.onSwipeBack,
  });

  @override
  State<SwipeBackWrapper> createState() => _SwipeBackWrapperState();
}

class _SwipeBackWrapperState extends State<SwipeBackWrapper> {
  double _dragStartX = 0;
  double _dragOffset = 0;
  bool _isDragging = false;
  int? _pointerId;
  static const double _edgeThreshold = 30.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        // Начинаем жест только если он начинается от левого края (в пределах 30px)
        // Используем globalPosition для координат относительно экрана
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
              _isDragging = true;
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
          
          // Возвращаем назад, если свайп был достаточно длинным (более 30% ширины экрана)
          if (_dragOffset > screenWidth * 0.3) {
            if (widget.onSwipeBack != null) {
              widget.onSwipeBack!();
            } else {
              final navigator = Navigator.maybeOf(context);
              if (navigator != null && navigator.canPop()) {
                navigator.pop();
              }
            }
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
          _pointerId = null;
          setState(() {
            _isDragging = false;
            _dragOffset = 0;
          });
        }
      },
      child: Stack(
        children: [
          widget.child,
          // Визуальная индикация жеста
          if (_isDragging && _dragOffset > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _dragOffset.clamp(0, MediaQuery.of(context).size.width),
              child: Container(
                color: Colors.black.withOpacity(
                  (0.1 * (_dragOffset / MediaQuery.of(context).size.width)).clamp(0.0, 0.3)
                ),
              ),
            ),
        ],
      ),
    );
  }
}

