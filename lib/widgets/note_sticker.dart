import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:convert';
import '../models/note_model.dart';

class NoteSticker extends StatefulWidget {
  final NoteModel note;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final Function(NoteModel) onUpdate;
  final VoidCallback onBringToFront;
  final VoidCallback? onAlign;
  final bool isAligning;

  const NoteSticker({
    super.key,
    required this.note,
    required this.onDelete,
    required this.onEdit,
    required this.onUpdate,
    required this.onBringToFront,
    this.onAlign,
    this.isAligning = false,
  });

  @override
  State<NoteSticker> createState() => _NoteStickerState();
}

class _NoteStickerState extends State<NoteSticker> {
  bool _isDragging = false;
  bool _isResizing = false;
  Offset _dragStartPosition = Offset.zero;
  Offset _noteStartPosition = Offset.zero;
  double _resizeStartHeight = 0;
  double _resizeStartY = 0;

  Color _getColorFromHex(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFFFFEB3B); // Желтый по умолчанию
    }
  }

  // Форматирует дату в формат д.мм.гг (например, 7.01.26)
  String _formatDate(DateTime date) {
    final day = date.day;
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year % 100;
    return '$day.$month.$year';
  }

  // Определяет, является ли цвет темным
  bool _isDarkColor(Color color) {
    // Вычисляем яркость цвета по формуле: 0.299*R + 0.587*G + 0.114*B
    final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    return luminance < 0.5; // Если яркость меньше 0.5, цвет считается темным
  }

  // Возвращает цвет текста/иконок в зависимости от яркости фона
  Color _getTextColor(Color backgroundColor) {
    return _isDarkColor(backgroundColor) ? Colors.white : Colors.black;
  }

  Widget _buildContent(Color textColor) {
    final hasDrawing = widget.note.drawingData != null && widget.note.drawingData!.isNotEmpty;
    final hasText = widget.note.content.isNotEmpty || widget.note.title.isNotEmpty;
    final content = widget.note.content.isEmpty ? widget.note.title : widget.note.content;
    
    // Если есть рисунок, показываем его
    if (hasDrawing) {
      try {
        final drawingJson = jsonDecode(widget.note.drawingData!);
        final paths = drawingJson['paths'] as List?;
        if (paths != null && paths.isNotEmpty) {
          return Stack(
            children: [
              // Рисунок
              SizedBox(
                width: widget.note.width - 24,
                height: widget.note.height - 80,
                child: CustomPaint(
                  painter: _DrawingPainter(paths, widget.note.color),
                  size: Size(widget.note.width - 24, widget.note.height - 80),
                ),
              ),
              // Текст поверх рисунка (если есть)
              if (hasText)
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _parseAndDisplayText(content, textColor),
                  ),
                ),
            ],
          );
        }
      } catch (e) {
        // Если ошибка парсинга, показываем текст
        print('Error parsing drawing: $e');
      }
    }
    
    // Показываем только текст
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _parseAndDisplayText(content, textColor),
    );
  }

  Widget _parseAndDisplayText(String text, Color textColor) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    // Парсим HTML-теги выравнивания - удаляем все div теги и извлекаем выравнивание
    TextAlign? align;
    String cleanedText = text;
    
    // Ищем все div теги с выравниванием (поддерживаем одинарные и двойные кавычки)
    final divPattern = RegExp('<div\\s+style=["\']text-align:\\s*(\\w+)["\']>(.*?)</div>', dotAll: true);
    
    // Находим все div теги и извлекаем выравнивание из первого
    final matches = divPattern.allMatches(text);
    if (matches.isNotEmpty) {
      final firstMatch = matches.first;
      final alignValue = firstMatch.group(1);
      
      // Удаляем все div теги рекурсивно (на случай вложенных)
      cleanedText = text;
      int iterations = 0;
      while (divPattern.hasMatch(cleanedText) && iterations < 10) {
        cleanedText = cleanedText.replaceAll(divPattern, r'$2');
        iterations++;
      }
      
      switch (alignValue) {
        case 'left':
          align = TextAlign.left;
          break;
        case 'center':
          align = TextAlign.center;
          break;
        case 'right':
          align = TextAlign.right;
          break;
        case 'justify':
          align = TextAlign.justify;
          break;
      }
    }

    // Парсим markdown
    return Text.rich(
      _parseMarkdown(cleanedText, textColor),
      textAlign: align ?? TextAlign.left,
      style: TextStyle(
        fontSize: 14,
        height: 1.5,
        color: textColor,
      ),
    );
  }

  TextSpan _parseMarkdown(String text, Color textColor) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: TextStyle(color: textColor));
    }

    return _parseMarkdownRecursive(text, textColor);
  }

  TextSpan _parseMarkdownRecursive(String text, Color textColor) {
    if (text.isEmpty) {
      return const TextSpan(text: '');
    }

    List<TextSpan> spans = [];
    int i = 0;

    while (i < text.length) {
      // Проверяем жирный текст **text** (приоритет выше, проверяем первым)
      if (i < text.length - 1 && text[i] == '*' && text[i + 1] == '*') {
        int closePos = text.indexOf('**', i + 2);
        if (closePos != -1) {
          // Парсим содержимое рекурсивно для поддержки вложенных тегов
          final innerText = text.substring(i + 2, closePos);
          final innerSpan = _parseMarkdownRecursive(innerText, textColor);
          spans.add(TextSpan(
            children: innerSpan.children ?? [TextSpan(text: innerSpan.text ?? '', style: TextStyle(color: textColor))],
            style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
          ));
          i = closePos + 2;
          continue;
        }
      }
      
      // Проверяем курсив *text* (но не **text**)
      if (text[i] == '*' && 
          (i == 0 || text[i - 1] != '*') && 
          (i == text.length - 1 || text[i + 1] != '*')) {
        int closePos = text.indexOf('*', i + 1);
        if (closePos != -1 && (closePos == text.length - 1 || text[closePos + 1] != '*')) {
          // Парсим содержимое рекурсивно
          final innerText = text.substring(i + 1, closePos);
          final innerSpan = _parseMarkdownRecursive(innerText, textColor);
          spans.add(TextSpan(
            children: innerSpan.children ?? [TextSpan(text: innerSpan.text ?? '', style: TextStyle(color: textColor))],
            style: TextStyle(fontStyle: FontStyle.italic, color: textColor),
          ));
          i = closePos + 1;
          continue;
        }
      }
      
      // Проверяем подчеркивание _text_ (одинарное)
      if (text[i] == '_' && 
          (i == 0 || text[i - 1] != '_') && 
          (i == text.length - 1 || text[i + 1] != '_')) {
        int closePos = text.indexOf('_', i + 1);
        if (closePos != -1 && (closePos == text.length - 1 || text[closePos + 1] != '_')) {
          // Парсим содержимое рекурсивно
          final innerText = text.substring(i + 1, closePos);
          final innerSpan = _parseMarkdownRecursive(innerText, textColor);
          spans.add(TextSpan(
            children: innerSpan.children ?? [TextSpan(text: innerSpan.text ?? '', style: TextStyle(color: textColor))],
            style: TextStyle(decoration: TextDecoration.underline, color: textColor),
          ));
          i = closePos + 1;
          continue;
        }
      }
      
      // Проверяем подчеркивание __text__ (двойное, для совместимости)
      if (i < text.length - 1 && text[i] == '_' && text[i + 1] == '_') {
        int closePos = text.indexOf('__', i + 2);
        if (closePos != -1) {
          // Парсим содержимое рекурсивно
          final innerText = text.substring(i + 2, closePos);
          final innerSpan = _parseMarkdownRecursive(innerText, textColor);
          spans.add(TextSpan(
            children: innerSpan.children ?? [TextSpan(text: innerSpan.text ?? '', style: TextStyle(color: textColor))],
            style: TextStyle(decoration: TextDecoration.underline, color: textColor),
          ));
          i = closePos + 2;
          continue;
        }
      }
      
      // Обычный текст - ищем следующее специальное вхождение
      int nextSpecial = text.length;
      for (int j = i; j < text.length; j++) {
        if (j < text.length - 1 && text[j] == '*' && text[j + 1] == '*') {
          nextSpecial = j;
          break;
        } else if (text[j] == '*' && (j == 0 || text[j - 1] != '*') && (j == text.length - 1 || text[j + 1] != '*')) {
          nextSpecial = j;
          break;
        } else if (text[j] == '_' && (j == 0 || text[j - 1] != '_') && (j == text.length - 1 || text[j + 1] != '_')) {
          nextSpecial = j;
          break;
        } else if (j < text.length - 1 && text[j] == '_' && text[j + 1] == '_') {
          nextSpecial = j;
          break;
        }
      }
      
      if (nextSpecial > i) {
        spans.add(TextSpan(text: text.substring(i, nextSpecial), style: TextStyle(color: textColor)));
        i = nextSpecial;
      } else {
        spans.add(TextSpan(text: text[i], style: TextStyle(color: textColor)));
        i++;
      }
    }

    if (spans.isEmpty) {
      return TextSpan(text: text, style: TextStyle(color: textColor));
    }

    return TextSpan(children: spans, style: TextStyle(color: textColor));
  }

  void _showColorPicker(BuildContext context) {
    final colors = [
      '#FFEB3B', // Желтый
      '#FF9800', // Оранжевый
      '#F44336', // Красный
      '#E91E63', // Розовый
      '#9C27B0', // Фиолетовый
      '#673AB7', // Глубокий фиолетовый
      '#3F51B5', // Индиго
      '#2196F3', // Синий
      '#03A9F4', // Светло-синий
      '#00BCD4', // Циан
      '#009688', // Бирюзовый
      '#4CAF50', // Зеленый
      '#8BC34A', // Светло-зеленый
      '#CDDC39', // Лайм
      '#FFC107', // Янтарный
    ];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: colors.length,
            itemBuilder: (context, index) {
              final color = _getColorFromHex(colors[index]);
              return GestureDetector(
                onTap: () {
                  widget.onUpdate(widget.note.copyWith(color: colors[index]));
                  Navigator.of(context).pop();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.note.color == colors[index]
                          ? Colors.black
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColorFromHex(widget.note.color);
    final textColor = _getTextColor(color);
    
    // Используем AnimatedPositioned только при выравнивании
    if (widget.isAligning) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        left: widget.note.x,
        top: widget.note.y,
        child: _buildStickerContent(color, textColor),
      );
    }
    
    return Positioned(
      left: widget.note.x,
      top: widget.note.y,
      child: _buildStickerContent(color, textColor),
    );
  }
  
  Widget _buildStickerContent(Color color, Color textColor) {
    return GestureDetector(
        onTap: () {
          // Поднимаем стикер наверх при нажатии (как окна в macOS)
          widget.onBringToFront();
        },
        child: Container(
          width: widget.note.width + 20, // Увеличена ширина на 20px
          height: widget.note.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.black.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: _isDragging
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Заголовок с кнопками управления
              GestureDetector(
                onPanStart: widget.note.isLocked ? null : (details) {
                  widget.onBringToFront();
                  setState(() {
                    _isDragging = true;
                    _dragStartPosition = details.globalPosition;
                    _noteStartPosition = Offset(widget.note.x, widget.note.y);
                  });
                },
                onPanUpdate: widget.note.isLocked ? null : (details) {
                  if (_isDragging) {
                    final delta = details.globalPosition - _dragStartPosition;
                    final newX = (_noteStartPosition.dx + delta.dx).clamp(0.0, double.infinity);
                    final newY = (_noteStartPosition.dy + delta.dy).clamp(0.0, double.infinity);
                    widget.onUpdate(widget.note.copyWith(x: newX, y: newY));
                  }
                },
                onPanEnd: widget.note.isLocked ? null : (details) {
                  setState(() {
                    _isDragging = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                    // Кнопка закрепления
                    GestureDetector(
                      onTap: () {
                        widget.onUpdate(widget.note.copyWith(isLocked: !widget.note.isLocked));
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          widget.note.isLocked ? Icons.lock : Icons.lock_open,
                          size: 18,
                          color: Colors.black,
                          weight: 700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Кнопка выравнивания
                    if (widget.onAlign != null)
                      GestureDetector(
                        onTap: widget.onAlign,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.grid_view,
                            size: 16,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    if (widget.onAlign != null) const SizedBox(width: 4),
                    // Кнопка выбора цвета
                    GestureDetector(
                      onTap: () {
                        _showColorPicker(context);
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.palette,
                          size: 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Кнопка редактирования
                    GestureDetector(
                      onTap: widget.onEdit,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.edit,
                          size: 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Кнопка удаления
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.delete,
                          size: 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                  ),
                ),
              ),
              // Контент заметки
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: _buildContent(textColor),
                ),
              ),
              // Дата создания
              if (widget.note.createdAt != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    _formatDate(widget.note.createdAt!),
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withOpacity(0.6),
                    ),
                  ),
                ),
              // Ресайзер
              if (!widget.note.isLocked)
                GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _isResizing = true;
                      _resizeStartHeight = widget.note.height;
                      _resizeStartY = details.globalPosition.dy;
                    });
                  },
                  onPanUpdate: (details) {
                    if (_isResizing) {
                      final deltaY = details.globalPosition.dy - _resizeStartY;
                      final newHeight = (_resizeStartHeight + deltaY).clamp(150.0, 600.0);
                      widget.onUpdate(widget.note.copyWith(height: newHeight));
                    }
                  },
                  onPanEnd: (details) {
                    setState(() {
                      _isResizing = false;
                    });
                  },
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
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
}

class _DrawingPainter extends CustomPainter {
  final List paths;
  final String noteColor;

  _DrawingPainter(this.paths, this.noteColor);

  Color _getColorFromHex(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFFFFEB3B);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundColor = _getColorFromHex(noteColor);
    
    for (final path in paths) {
      if (path.isEmpty) continue;
      
      final points = (path as List).map((p) {
        return Offset(
          (p['x'] as num).toDouble(),
          (p['y'] as num).toDouble(),
        );
      }).toList();

      if (points.isEmpty) continue;

      final tool = path.first['tool'] ?? 'pencil';
      final colorHex = path.first['color']?.toString() ?? '#000000';
      
      final paint = Paint()
        ..strokeWidth = tool == 'brush' ? 5.0 : (tool == 'eraser' ? 20.0 : 2.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      if (tool == 'eraser') {
        // Для ластика используем цвет фона заметки
        paint
          ..color = backgroundColor
          ..blendMode = BlendMode.clear;
      } else {
        paint.color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
      }

      final pathToDraw = ui.Path();
      pathToDraw.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        pathToDraw.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(pathToDraw, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

