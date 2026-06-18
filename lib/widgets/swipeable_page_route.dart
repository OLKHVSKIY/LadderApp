import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// iOS-подобный маршрут с горизонтальными свайпами в обе стороны:
///
/// 1. Свайп от ЛЕВОГО края слева→направо закрывает страницу (как iOS back).
///    В отличие от стандартного CupertinoPageRoute доводок при отпускании
///    делается мягким: когда страница уже почти уехала, остаток пути
///    докручивается за ≥ [_kMinSnapMs] мс (а не за ~80 мс), поэтому нет
///    резкого «щелчка» в самом конце.
///
/// 2. После закрытия страница запоминается в [SwipeNav]. На странице-источнике
///    свайп от ПРАВОГО края справа→налево открывает её снова («вперёд»),
///    как будто возвращаешься обратно.
class SwipeablePageRoute<T> extends PageRoute<T> {
  SwipeablePageRoute({required this.builder, super.settings});

  /// Билдер страницы. Хранится отдельно, чтобы [SwipeNav] мог пере-открыть
  /// страницу тем же билдером после закрытия.
  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 360);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 360);

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  bool get _popGestureInProgress => navigator!.userGestureInProgress;

  static bool _isPopGestureEnabled<T>(SwipeablePageRoute<T> route) {
    if (route.isFirst) return false;
    if (route.willHandlePopInternally) return false;
    if (route.popDisposition == RoutePopDisposition.doNotPop) return false;
    if (route.animation!.status != AnimationStatus.completed) return false;
    if (route.secondaryAnimation!.status != AnimationStatus.dismissed) {
      return false;
    }
    if (route.navigator!.userGestureInProgress) return false;
    return true;
  }

  static _BackGestureController<T> _startPopGesture<T>(
      SwipeablePageRoute<T> route) {
    return _BackGestureController<T>(
      navigator: route.navigator!,
      controller: route.controller!,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Во время самого свайпа двигаем линейно (1:1 за пальцем). При обычном
    // push/pop и доводке — мягкая кривая.
    final bool linear = _popGestureInProgress;

    final Animation<Offset> primaryPosition =
        (linear ? animation : _curved(animation)).drive(
      Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero),
    );
    // Параллакс нижней страницы: чуть уезжает влево, пока верхняя наезжает.
    final Animation<Offset> secondaryPosition =
        (linear ? secondaryAnimation : _curved(secondaryAnimation)).drive(
      Tween<Offset>(begin: Offset.zero, end: const Offset(-0.25, 0.0)),
    );

    final Widget shadowed = DecoratedBoxTransition(
      decoration: animation.drive(_shadowTween),
      child: child,
    );

    return SlideTransition(
      position: secondaryPosition,
      child: SlideTransition(
        position: primaryPosition,
        child: _BackGestureDetector<T>(
          enabledCallback: () => _isPopGestureEnabled<T>(this),
          onStartPopGesture: () => _startPopGesture<T>(this),
          child: shadowed,
        ),
      ),
    );
  }

  static CurvedAnimation _curved(Animation<double> parent) => CurvedAnimation(
        parent: parent,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

  static final DecorationTween _shadowTween = DecorationTween(
    begin: const BoxDecoration(boxShadow: <BoxShadow>[]),
    end: const BoxDecoration(
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 12,
          offset: Offset(-4, 0),
        ),
      ],
    ),
  );
}

// === Жест «назад» (порт CupertinoPageRoute с мягким доводком) ===

const double _kBackGestureWidth = 22.0;
const double _kMinFlingVelocity = 1.0; // ширин экрана в секунду
// Мягкий доводок: даже короткий остаток пути докручивается не быстрее, чем
// за этот минимум — это и убирает «резкий слайд» в конце свайпа.
const int _kMinSnapMs = 240;
const int _kMaxSnapMs = 360;

class _BackGestureController<T> {
  _BackGestureController({
    required this.navigator,
    required this.controller,
  }) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;

  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  void dragEnd(double velocity) {
    const Curve animationCurve = Curves.easeOutCubic;
    final bool animateForward;

    if (velocity.abs() >= _kMinFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      // Отмена: возвращаем страницу на место (value → 1).
      final int ms = _snapDuration(1.0 - controller.value);
      controller.animateTo(1.0,
          duration: Duration(milliseconds: ms), curve: animationCurve);
    } else {
      // Закрываем: страница доезжает за край (value → 0).
      navigator.pop();
      if (controller.isAnimating) {
        final int ms = _snapDuration(controller.value);
        controller.animateBack(0.0,
            duration: Duration(milliseconds: ms), curve: animationCurve);
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener cb;
      cb = (AnimationStatus status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(cb);
      };
      controller.addStatusListener(cb);
    } else {
      navigator.didStopUserGesture();
    }
  }

  // Длительность пропорциональна остатку пути, но не меньше _kMinSnapMs —
  // короткий доводок не «щёлкает», а мягко докручивается.
  int _snapDuration(double remaining) {
    final base = lerpDouble(0, _kMaxSnapMs, remaining.clamp(0.0, 1.0))!;
    return base.clamp(_kMinSnapMs.toDouble(), _kMaxSnapMs.toDouble()).round();
  }
}

class _BackGestureDetector<T> extends StatefulWidget {
  const _BackGestureDetector({
    super.key,
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final Widget child;
  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_BackGestureController<T>> onStartPopGesture;

  @override
  State<_BackGestureDetector<T>> createState() =>
      _BackGestureDetectorState<T>();
}

class _BackGestureDetectorState<T> extends State<_BackGestureDetector<T>> {
  _BackGestureController<T>? _backGestureController;
  late HorizontalDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _backGestureController?.dragUpdate(
        _convertToLogical(details.primaryDelta! / context.size!.width));
  }

  void _handleDragEnd(DragEndDetails details) {
    _backGestureController?.dragEnd(_convertToLogical(
        details.velocity.pixelsPerSecond.dx / context.size!.width));
    _backGestureController = null;
  }

  void _handleDragCancel() {
    _backGestureController?.dragEnd(0.0);
    _backGestureController = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabledCallback()) _recognizer.addPointer(event);
  }

  double _convertToLogical(double value) {
    return Directionality.of(context) == TextDirection.rtl ? -value : value;
  }

  @override
  Widget build(BuildContext context) {
    final double dragAreaWidth = Directionality.of(context) == TextDirection.ltr
        ? MediaQuery.paddingOf(context).left + _kBackGestureWidth
        : MediaQuery.paddingOf(context).right + _kBackGestureWidth;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        PositionedDirectional(
          start: 0,
          width: dragAreaWidth,
          top: 0,
          bottom: 0,
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}

// === «Вперёд»: пере-открытие закрытой свайпом страницы ===

/// Глобальное состояние навигации свайпами. Хранит ключ навигатора и
/// последнюю закрытую свайп-страницу, чтобы её можно было открыть снова
/// свайпом от правого края.
class SwipeNav {
  SwipeNav._();
  static final SwipeNav instance = SwipeNav._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Билдер последней закрытой свайпом (или кнопкой) страницы; null — нечего
  /// открывать «вперёд». ValueNotifier — чтобы зона жеста включалась/выключалась.
  final ValueNotifier<WidgetBuilder?> lastDismissed =
      ValueNotifier<WidgetBuilder?>(null);

  void remember(WidgetBuilder builder) => lastDismissed.value = builder;

  void clear() => lastDismissed.value = null;

  /// Открыть запомненную страницу снова (свайп «вперёд»).
  void reopen() {
    final builder = lastDismissed.value;
    final nav = navigatorKey.currentState;
    if (builder == null || nav == null) return;
    nav.push(SwipeablePageRoute<void>(builder: builder));
  }
}

/// Наблюдатель навигатора: запоминает закрытые свайп-страницы и сбрасывает
/// «вперёд», когда пользователь уходит куда-то ещё.
class SwipeNavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Любой новый переход обнуляет «вперёд» (в т.ч. само пере-открытие —
    // билдер уже захвачен в reopen()).
    SwipeNav.instance.clear();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    SwipeNav.instance.clear();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is SwipeablePageRoute) {
      SwipeNav.instance.remember(route.builder);
    }
  }
}

/// Обёртка для всего приложения: добавляет у ПРАВОГО края зону жеста
/// справа→налево, которая пере-открывает последнюю закрытую страницу.
/// Зона активна только когда есть что открывать (lastDismissed != null),
/// поэтому не мешает горизонтальным жестам внутри страниц.
class SwipeForwardArea extends StatefulWidget {
  const SwipeForwardArea({super.key, required this.child});

  final Widget child;

  @override
  State<SwipeForwardArea> createState() => _SwipeForwardAreaState();
}

class _SwipeForwardAreaState extends State<SwipeForwardArea> {
  late HorizontalDragGestureRecognizer _recognizer;
  double _dx = 0;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = (_) {
        _dx = 0;
        _triggered = false;
      }
      ..onUpdate = (d) {
        _dx += d.primaryDelta ?? 0;
        // Свайп влево (dx уменьшается). Порог 64px или явный флинг влево.
        if (!_triggered && _dx < -64) {
          _triggered = true;
          SwipeNav.instance.reopen();
        }
      }
      ..onEnd = (d) {
        if (!_triggered && d.velocity.pixelsPerSecond.dx < -350) {
          _triggered = true;
          SwipeNav.instance.reopen();
        }
      }
      ..onCancel = () => _triggered = false;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (SwipeNav.instance.lastDismissed.value != null) {
      _recognizer.addPointer(event);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WidgetBuilder?>(
      valueListenable: SwipeNav.instance.lastDismissed,
      builder: (context, dismissed, _) {
        if (dismissed == null) return widget.child;
        final double edge =
            MediaQuery.paddingOf(context).right + _kBackGestureWidth;
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            widget.child,
            Positioned(
              right: 0,
              width: edge,
              top: 0,
              bottom: 0,
              child: Listener(
                onPointerDown: _onPointerDown,
                behavior: HitTestBehavior.translucent,
              ),
            ),
          ],
        );
      },
    );
  }
}
