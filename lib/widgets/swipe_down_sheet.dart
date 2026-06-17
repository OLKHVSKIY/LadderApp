import 'package:flutter/material.dart';

/// Обёртка для нижних шторок: закрытие свайпом вниз за верхнюю часть.
///
/// Захват жеста идёт только по верхней зоне высотой [handleHeight] (шапка
/// шторки), поэтому скролл и кнопки ниже продолжают работать. Во время
/// перетаскивания шторка плавно следует за пальцем; при отпускании она либо
/// закрывается (если утянули дальше [dismissThreshold] или резко дёрнули вниз),
/// либо плавно возвращается на место.
///
/// Если у самой шторки нет собственной анимации закрытия, выставьте
/// [animateOut] = true — тогда перед вызовом [onDismiss] шторка плавно уезжает
/// вниз за край экрана (иначе при резком свайпе она исчезает рывком).
class SwipeDownSheet extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  final double handleHeight;
  final double dismissThreshold;
  final bool animateOut;

  const SwipeDownSheet({
    super.key,
    required this.child,
    required this.onDismiss,
    this.handleHeight = 80,
    this.dismissThreshold = 120,
    this.animateOut = false,
  });

  @override
  State<SwipeDownSheet> createState() => _SwipeDownSheetState();
}

enum _AnimMode { back, out }

class _SwipeDownSheetState extends State<SwipeDownSheet>
    with SingleTickerProviderStateMixin {
  double _offset = 0;
  double _from = 0;
  double _to = 0;
  _AnimMode _mode = _AnimMode.back;
  late final AnimationController _anim;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _curve.addListener(() {
      setState(() => _offset = _from + (_to - _from) * _curve.value);
    });
    _anim.addStatusListener((status) {
      if (status == AnimationStatus.completed && _mode == _AnimMode.out) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _anim.stop();
    // Тянуть можно только вниз — вверх шторка не уезжает.
    setState(() => _offset = (_offset + d.delta.dy).clamp(0.0, double.infinity));
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.velocity.pixelsPerSecond.dy;
    final shouldDismiss = _offset > widget.dismissThreshold || velocity > 700;
    if (shouldDismiss) {
      if (!widget.animateOut) {
        widget.onDismiss();
        return;
      }
      // Доводим шторку вниз за край экрана, затем закрываем.
      _from = _offset;
      _to = MediaQuery.of(context).size.height;
      _mode = _AnimMode.out;
      _anim
        ..reset()
        ..forward();
      return;
    }
    // Плавно возвращаем на место.
    _from = _offset;
    _to = 0;
    _mode = _AnimMode.back;
    _anim
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, _offset),
      child: Stack(
        children: [
          widget.child,
          // Прозрачная зона захвата по верхней части шторки.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: widget.handleHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
            ),
          ),
        ],
      ),
    );
  }
}
