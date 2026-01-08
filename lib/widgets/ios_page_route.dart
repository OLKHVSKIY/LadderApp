import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// Кастомный PageRoute с iOS-стилем анимации, как в SwipeBackWrapper
class IOSPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final bool fullscreenDialog;

  IOSPageRoute({
    required this.builder,
    this.fullscreenDialog = false,
    RouteSettings? settings,
  }) : super(settings: settings, fullscreenDialog: fullscreenDialog);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 350);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 350);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final Widget result = builder(context);
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: result,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Используем такую же анимацию как в SwipeBackWrapper
    // При открытии (push): текущий экран приезжает справа
    // При закрытии (pop): текущий экран уезжает вправо плавно
    // Предыдущий экран Flutter показывает автоматически под текущим
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    // При push: экран приезжает справа (animation: 0 -> 1)
    // При pop: используем secondaryAnimation для плавного закрытия
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0), // Начинается справа
        end: Offset.zero, // Заканчивается на месте
      ).animate(curvedAnimation),
      child: child,
    );
  }
}

