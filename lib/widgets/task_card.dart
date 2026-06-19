import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../theme/app_colors.dart';
import 'file_attachment_display.dart';
import 'task_sound_player.dart';

class TextLineMetrics {
  final double width;
  final double height;
  
  TextLineMetrics({required this.width, required this.height});
}


class TaskCard extends StatefulWidget {
  final Task task;
  final Function(bool) onToggle;
  final String? openMenuTaskId;
  final Function(String?, GlobalKey?)? onMenuToggle;
  final Function(String)? onDelete;
  // Колбэк изменения чек-листа: возвращает обновлённый список подзадач.
  final void Function(List<SubTask>)? onSubtasksChanged;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggle,
    this.openMenuTaskId,
    this.onMenuToggle,
    this.onDelete,
    this.onSubtasksChanged,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> with TickerProviderStateMixin {
  bool _isHovered = false;
  final GlobalKey _menuButtonKey = GlobalKey();
  final GlobalKey _checkboxKey = GlobalKey();
  late AnimationController _menuAnimationController;
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

  // Долгое нажатие на задачу: открываем меню с тактильной отдачей.
  void _handleLongPress() {
    if (_isMenuOpen) return;
    HapticFeedback.mediumImpact();
    widget.onMenuToggle?.call(widget.task.id, _menuButtonKey);
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.red.withValues(alpha: 0.9);
      case 2:
        return Colors.orange.withValues(alpha: 0.9);
      case 3:
        return Colors.blue.withValues(alpha: 0.9);
      default:
        return Colors.grey.withValues(alpha: 0.9);
    }
  }

  List<TextLineMetrics> _getTextLineMetrics(String text, TextStyle style, double maxWidth) {
    if (text.isEmpty) return [];
    
    final lineMetrics = <TextLineMetrics>[];
    
    // Используем TextPainter с теми же параметрами, что и для отображения
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null, // Без ограничения строк, как в Text виджете
    )..layout(minWidth: 0, maxWidth: maxWidth);
    
    final lineHeight = tp.preferredLineHeight;
    
    // Используем getPositionForOffset для определения позиций строк
    // Проходим по вертикали и находим каждую строку
    double currentY = 0;
    int lastOffset = 0;
    
    while (currentY < tp.size.height && lastOffset < text.length) {
      // Находим позицию текста на текущей Y координате
      final position = tp.getPositionForOffset(Offset(0, currentY));
      final lineStart = position.offset;
      
      // Находим конец строки - следующая строка или конец текста
      double nextY = currentY + lineHeight;
      int lineEnd = text.length;
      
      if (nextY < tp.size.height) {
        final nextPosition = tp.getPositionForOffset(Offset(0, nextY));
        lineEnd = nextPosition.offset;
      }
      
      // Получаем текст строки
      final lineText = text.substring(lineStart, lineEnd).replaceAll('\n', '');
      
      if (lineText.isEmpty && lineStart >= text.length) {
        break;
      }
      
      // Измеряем ширину строки
      final lineTp = TextPainter(
        text: TextSpan(text: lineText, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(minWidth: 0, maxWidth: double.infinity);
      
      lineMetrics.add(TextLineMetrics(
        width: lineTp.width,
        height: lineHeight,
      ));
      
      currentY = nextY;
      lastOffset = lineEnd;
      
      // Если достигли конца текста, выходим
      if (lineEnd >= text.length) {
        break;
      }
    }
    
    // Если не получилось определить строки через getPositionForOffset,
    // используем резервный метод - разбиваем по \n
    if (lineMetrics.isEmpty) {
      final lines = text.split('\n');
      for (final line in lines) {
        if (line.isEmpty) {
          lineMetrics.add(TextLineMetrics(
            width: 0,
            height: lineHeight,
          ));
          continue;
        }
        
        final lineTp = TextPainter(
          text: TextSpan(text: line, style: style),
          textDirection: TextDirection.ltr,
        )..layout(minWidth: 0, maxWidth: maxWidth);
        
        if (lineTp.width <= maxWidth) {
          lineMetrics.add(TextLineMetrics(
            width: lineTp.width,
            height: lineHeight,
          ));
        } else {
          // Разбиваем длинную строку
          int start = 0;
          while (start < line.length) {
            int end = start;
            while (end < line.length) {
              final test = line.substring(start, end + 1);
              final testTp = TextPainter(
                text: TextSpan(text: test, style: style),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout(minWidth: 0, maxWidth: double.infinity);
              
              if (testTp.width > maxWidth && end > start) {
                break;
              }
              end++;
            }
            
            if (end > start) {
              final sub = line.substring(start, end);
              final subTp = TextPainter(
                text: TextSpan(text: sub, style: style),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout(minWidth: 0, maxWidth: double.infinity);
              
              lineMetrics.add(TextLineMetrics(
                width: subTp.width,
                height: lineHeight,
              ));
              start = end;
            } else {
              break;
            }
          }
        }
      }
    }
    
    return lineMetrics;
  }

  void _toggleSubtask(int index) {
    HapticFeedback.selectionClick();
    final updated = List<SubTask>.from(widget.task.subtasks);
    updated[index] =
        updated[index].copyWith(isCompleted: !updated[index].isCompleted);
    widget.onSubtasksChanged?.call(updated);
  }

  // Компактный чек-лист подзадач с индикатором прогресса.
  Widget _buildSubtasks(AppColors colors) {
    final subtasks = widget.task.subtasks;
    final done = subtasks.where((s) => s.isCompleted).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Индикатор прогресса: тонкая полоса + счётчик.
        Row(
          children: [
            Icon(Icons.checklist_rounded,
                size: 14, color: colors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: 0,
                    end: subtasks.isEmpty ? 0 : done / subtasks.length,
                  ),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 3,
                    backgroundColor: colors.border,
                    valueColor: AlwaysStoppedAnimation(
                      _getPriorityColor(widget.task.priority),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$done/${subtasks.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < subtasks.length; i++)
          GestureDetector(
            onTap: () => _toggleSubtask(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: subtasks[i].isCompleted
                          ? _getPriorityColor(widget.task.priority)
                          : Colors.transparent,
                      border: Border.all(
                        color: subtasks[i].isCompleted
                            ? _getPriorityColor(widget.task.priority)
                            : (colors.isDark
                                ? colors.textTertiary
                                : const Color(0xFFB8B8BD)),
                        width: 1.6,
                      ),
                    ),
                    child: subtasks[i].isCompleted
                        ? const Icon(Icons.check,
                            size: 11, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      subtasks[i].title,
                      style: TextStyle(
                        fontSize: 14,
                        color: subtasks[i].isCompleted
                            ? colors.textTertiary
                            : colors.textSecondary,
                        decoration: subtasks[i].isCompleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final card = Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          // Долгое нажатие на любую часть карточки открывает меню.
          onLongPress: _handleLongPress,
          child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Чекбокс
              GestureDetector(
                onTap: () {
                  final newCompletedState = !widget.task.isCompleted;
                  
                  // Воспроизводим звук и вибрацию СРАЗУ при нажатии
                  if (newCompletedState) {
                    // Запускаем звук первым, чтобы он начал загружаться как можно раньше
                    TaskSoundPlayer().playTaskCompleteSound();
                    // Вибрация сразу после - они должны начаться почти одновременно
                    HapticFeedback.lightImpact();
                  }
                  
                  widget.onToggle(newCompletedState);
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
                        // Незавершённый чекбокс: видимая, но мягкая рамка.
                        // В светлой теме чуть светлее textTertiary.
                        color: widget.task.isCompleted
                            ? _getPriorityColor(widget.task.priority)
                            : _isHovered
                                ? colors.textSecondary
                                : (colors.isDark
                                    ? colors.textTertiary
                                    : const Color(0xFFB8B8BD)),
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textStyle = TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: widget.task.isCompleted
                              ? colors.textTertiary
                              : colors.textPrimary,
                        );
                        final availableWidth = constraints.maxWidth;
                        final titleLineMetrics = _getTextLineMetrics(
                          widget.task.title,
                          textStyle,
                          availableWidth,
                        );
                        
                        return IntrinsicHeight(
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.topLeft,
                            children: [
                              Text(
                                widget.task.title,
                                style: textStyle,
                                maxLines: null,
                              ),
                              AnimatedBuilder(
                                animation: _strikeAnimation ??
                                    const AlwaysStoppedAnimation(0.0),
                                builder: (context, child) {
                                  final v = _strikeAnimation?.value ??
                                      (widget.task.isCompleted ? 1.0 : 0.0);
                                  
                                  if (v == 0.0 || titleLineMetrics.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  
                                  // Используем TextPainter для точного определения позиций строк названия
                                  final titleTp = TextPainter(
                                    text: TextSpan(text: widget.task.title, style: textStyle),
                                    textDirection: TextDirection.ltr,
                                    maxLines: null,
                                  )..layout(minWidth: 0, maxWidth: availableWidth);
                                  
                                  final actualLineHeight = titleTp.preferredLineHeight;
                                  
                                  // Получаем реальные координаты каждой строки названия
                                  final titleLineCenterPositions = <double>[];
                                  double currentY = 0;

                                  for (int i = 0; i < titleLineMetrics.length; i++) {
                                    final position = titleTp.getPositionForOffset(Offset(0, currentY));
                                    final caretOffset = titleTp.getOffsetForCaret(position, Rect.zero);
                                    
                                    // Отдельные коррекции для названия задачи (настраиваются вручную)
                                    final correction = i == 0 
                                        ? 2   // Первая строка названия
                                        : (i == 1 
                                            ? 6   // Вторая строка названия
                                            : (i == 2 
                                                ? 10   // Третья строка названия
                                                : 8)); // Для остальных строк (если понадобится)
                                    final lineCenterY = caretOffset.dy + (actualLineHeight / 2) + correction;
                                    titleLineCenterPositions.add(lineCenterY);
                                    
                                    currentY += actualLineHeight;

                                    if (position.offset >= widget.task.title.length) {
                                      break;
                                    }
                                  }
                                  
                                  while (titleLineCenterPositions.length < titleLineMetrics.length) {
                                    final index = titleLineCenterPositions.length;
                                    final fallbackY = index * actualLineHeight + (actualLineHeight / 2) + 1;
                                    titleLineCenterPositions.add(fallbackY);
                                  }
                                  
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.topLeft,
                                    children: titleLineMetrics.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final metrics = entry.value;
                                      final lineWidth = metrics.width * v;
                                      
                                      final centerY = index < titleLineCenterPositions.length 
                                          ? titleLineCenterPositions[index] 
                                          : index * actualLineHeight + (actualLineHeight / 2);
                                      
                                      final topPosition = centerY;
                                      
                                      return Positioned(
                                        left: 0,
                                        top: topPosition,
                                        child: Container(
                                          width: lineWidth,
                                          height: 2,
                                          color: (widget.task.isCompleted
                                                  ? const Color(0xFF999999)
                                                  : const Color(0xFF666666))
                                              .withValues(alpha: 0.6),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (widget.task.description != null && widget.task.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final textStyle = TextStyle(
                            fontSize: 14,
                            color: widget.task.isCompleted
                                ? colors.textTertiary
                                : colors.textSecondary,
                          );
                          final availableWidth = constraints.maxWidth;
                          final lineMetrics = _getTextLineMetrics(
                            widget.task.description!,
                            textStyle,
                            availableWidth,
                          );
                          
                          return IntrinsicHeight(
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.topLeft,
                              children: [
                                Text(
                                  widget.task.description!,
                                  style: textStyle,
                                  maxLines: null,
                                ),
                                AnimatedBuilder(
                                  animation: _strikeAnimation ??
                                      const AlwaysStoppedAnimation(0.0),
                                  builder: (context, child) {
                                    final v = _strikeAnimation?.value ??
                                        (widget.task.isCompleted ? 1.0 : 0.0);
                                    
                                    if (v == 0.0 || lineMetrics.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    
                                    // Создаем линии для каждой строки
                                    // Используем TextPainter для точного определения позиций строк
                                    final textTp = TextPainter(
                                      text: TextSpan(text: widget.task.description!, style: textStyle),
                                      textDirection: TextDirection.ltr,
                                      maxLines: null,
                                    )..layout(minWidth: 0, maxWidth: availableWidth);
                                    
                                    // Получаем реальные координаты каждой строки через TextPainter
                                    final lineCenterPositions = <double>[];
                                    final actualLineHeight = textTp.preferredLineHeight;
                                    
                                    // Используем тот же алгоритм, что и в _getTextLineMetrics для определения позиций строк
                                    // Проходим по тексту и определяем центр каждой строки
                                    double currentY = 0;

                                    for (int i = 0; i < lineMetrics.length; i++) {
                                      // Получаем позицию текста на текущей Y координате
                                      final position = textTp.getPositionForOffset(Offset(0, currentY));
                                      
                                      // Получаем точные координаты для начала этой строки
                                      final caretOffset = textTp.getOffsetForCaret(position, Rect.zero);
                                      
                                      // Вычисляем центр строки: Y координата начала строки + половина высоты строки
                                      // Для каждой строки используем коррекцию по арифметической прогрессии:
                                      // Первая: +1, Вторая: +5, Третья: +8, Четвертая: +11
                                      // Продолжаем прогрессию с разностью 3: 5-я: +14, 6-я: +17, 7-я: +20, 8-я: +23
                                      final correction = i == 0 
                                          ? 1 
                                          : (i == 1 
                                              ? 5 
                                              : (i == 2 
                                                  ? 8 
                                                  : (i == 3 
                                                      ? 11 
                                                      : (i == 4 
                                                          ? 14 
                                                          : (i == 5 
                                                              ? 17 
                                                              : (i == 6 
                                                                  ? 20 
                                                                  : (i == 7 
                                                                      ? 23 
                                                                      : 11 + (i - 3) * 3)))))));
                                      final lineCenterY = caretOffset.dy + (actualLineHeight / 2) + correction;
                                      lineCenterPositions.add(lineCenterY);
                                      
                                      // Переходим к следующей строке
                                      currentY += actualLineHeight;
                                      
                                      // Если достигли конца текста, выходим
                                      if (position.offset >= widget.task.description!.length) {
                                        break;
                                      }
                                    }
                                    
                                    // Если не получилось определить все позиции, дополняем расчетом
                                    while (lineCenterPositions.length < lineMetrics.length) {
                                      final index = lineCenterPositions.length;
                                      final fallbackY = index * actualLineHeight + (actualLineHeight / 2) + 1;
                                      lineCenterPositions.add(fallbackY);
                                    }
                                    
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.topLeft,
                                      children: lineMetrics.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final metrics = entry.value;
                                        // Ширина линии = ширина текста (без дополнительных пикселей)
                                        final lineWidth = metrics.width * v;
                                        
                                        // Используем реальную позицию центра строки из lineCenterPositions
                                        final centerY = index < lineCenterPositions.length 
                                            ? lineCenterPositions[index] 
                                            : index * actualLineHeight + (actualLineHeight / 2);
                                        
                                        // Позиция линии: центр строки (коррекция уже учтена в lineCenterPositions)
                                        final topPosition = centerY;
                                        
                                        return Positioned(
                                          left: 0,
                                          top: topPosition,
                                          child: Container(
                                            width: lineWidth,
                                            height: 2,
                                            color: (widget.task.isCompleted
                                                    ? const Color(0xFF999999)
                                                    : const Color(0xFF666666))
                                                .withValues(alpha: 0.6),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
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
                              color: colors.border,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    // Отображение прикрепленных файлов
                    if (widget.task.attachedFiles != null && widget.task.attachedFiles!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      FileAttachmentDisplay(
                        files: widget.task.attachedFiles!,
                        isCompact: true,
                      ),
                    ],
                    // Чек-лист подзадач
                    if (widget.task.subtasks.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildSubtasks(colors),
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
                  child: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ],
    );

    // Свайп справа налево удаляет задачу.
    if (widget.onDelete == null) return card;
    return Dismissible(
      key: ValueKey('dismiss_${widget.task.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        widget.onDelete!(widget.task.id);
      },
      background: Padding(
        // Совпадает с нижним отступом карточки, чтобы кнопка центрировалась
        // по её высоте.
        padding: const EdgeInsets.only(bottom: 8, right: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.delete_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
      child: card,
    );
  }
}