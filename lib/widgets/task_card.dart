import 'package:flutter/material.dart';
import '../models/task.dart';

class TaskCard extends StatefulWidget {
  final Task task;
  final Function(bool) onToggle;
  final String? openMenuTaskId;
  final Function(String?, GlobalKey?)? onMenuToggle;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggle,
    this.openMenuTaskId,
    this.onMenuToggle,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> with TickerProviderStateMixin {
  bool _isHovered = false;
  final GlobalKey _menuButtonKey = GlobalKey();
  final GlobalKey _checkboxKey = GlobalKey();
  late AnimationController _menuAnimationController;
  late Animation<double> _menuFadeAnimation;
  late Animation<Offset> _menuSlideAnimation;
  AnimationController? _strikeController;
  Animation<double>? _strikeAnimation;
  
  bool get _isMenuOpen => widget.openMenuTaskId == widget.task.id;

  @override
  void initState() {
    super.initState();
    _menuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _menuFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _menuAnimationController,
        curve: Curves.easeOut,
      ),
    );
    _menuSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _menuAnimationController,
        curve: Curves.easeOut,
      ),
    );
    _initStrike();
  }

  void _initStrike() {
    if (_strikeController == null) {
      _strikeController = AnimationController(
        duration: const Duration(milliseconds: 400),
        vsync: this,
        value: widget.task.isCompleted ? 1.0 : 0.0,
      );
      _strikeAnimation = CurvedAnimation(
        parent: _strikeController!,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _menuAnimationController.dispose();
    _disposeStrike();
    super.dispose();
  }

  void _disposeStrike() {
    _strikeController?.dispose();
    _strikeController = null;
    _strikeAnimation = null;
  }

  @override
  void didUpdateWidget(TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.openMenuTaskId != widget.openMenuTaskId) {
      if (_isMenuOpen) {
        _menuAnimationController.forward();
      } else {
        _menuAnimationController.reverse();
      }
    }
    
    // Анимация перечеркивания текста
    if (oldWidget.task.isCompleted != widget.task.isCompleted) {
      _initStrike();
      
      if (widget.task.isCompleted) {
        _strikeController?.forward();
      } else {
        _strikeController?.reverse();
      }
    }
  }

  void _toggleMenu() {
    if (_isMenuOpen) {
      widget.onMenuToggle?.call(null, null);
    } else {
      widget.onMenuToggle?.call(widget.task.id, _menuButtonKey);
    }
  }

  void _closeMenu() {
    widget.onMenuToggle?.call(null, null);
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.red.withOpacity(0.9);
      case 2:
        return Colors.orange.withOpacity(0.9);
      case 3:
        return Colors.blue.withOpacity(0.9);
      default:
        return Colors.grey.withOpacity(0.9);
    }
  }

  double _measureTextWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return tp.size.width;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F6F7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              // Чекбокс
              GestureDetector(
                onTap: () {
                  widget.onToggle(!widget.task.isCompleted);
                  if (_isMenuOpen) {
                    _closeMenu();
                  }
                },
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isHovered = true),
                  onExit: (_) => setState(() => _isHovered = false),
                  child: Container(
                    key: _checkboxKey,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.task.isCompleted
                            ? _getPriorityColor(widget.task.priority)
                            : _isHovered
                                ? const Color(0xFFCCCCCC)
                                : const Color(0xFFE5E5E5),
                        width: 2,
                      ),
                      color: widget.task.isCompleted
                          ? _getPriorityColor(widget.task.priority)
                          : Colors.transparent,
                    ),
                    child: widget.task.isCompleted
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Контент задачи
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Text(
                          widget.task.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: widget.task.isCompleted
                                ? const Color(0xFF999999)
                                : Colors.black,
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _strikeAnimation ??
                              const AlwaysStoppedAnimation(0.0),
                          builder: (context, child) {
                            final v = _strikeAnimation?.value ??
                                (widget.task.isCompleted ? 1.0 : 0.0);
                            final textStyle = TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: widget.task.isCompleted
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                            );
                            final textWidth =
                                _measureTextWidth(widget.task.title, textStyle);
                            final lineWidth = (textWidth + 5) * v;
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: lineWidth,
                                height: 2,
                                color: (widget.task.isCompleted
                                        ? const Color(0xFF999999)
                                        : const Color(0xFF666666))
                                    .withOpacity(0.6),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    if (widget.task.description != null && widget.task.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Text(
                            widget.task.description!,
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.task.isCompleted
                                  ? const Color(0xFF999999)
                                  : const Color(0xFF666666),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _strikeAnimation ??
                                const AlwaysStoppedAnimation(0.0),
                            builder: (context, child) {
                              final v = _strikeAnimation?.value ??
                                  (widget.task.isCompleted ? 1.0 : 0.0);
                              final textStyle = TextStyle(
                                fontSize: 14,
                                color: widget.task.isCompleted
                                    ? const Color(0xFF999999)
                                    : const Color(0xFF666666),
                              );
                              final textWidth = _measureTextWidth(
                                  widget.task.description!, textStyle);
                              final lineWidth = (textWidth + 5) * v;
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: lineWidth,
                                  height: 2,
                                  color: (widget.task.isCompleted
                                          ? const Color(0xFF999999)
                                          : const Color(0xFF666666))
                                      .withOpacity(0.6),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                    if (widget.task.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: widget.task.tags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF666666),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              // Вертикальное троеточие
              GestureDetector(
                onTap: _toggleMenu,
                child: Container(
                  key: _menuButtonKey,
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.more_vert,
                    size: 20,
                    color: Color(0xFF666666),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}