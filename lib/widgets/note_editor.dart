import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../models/note_model.dart';

class NoteEditor extends StatefulWidget {
  final NoteModel? note;
  final Function(NoteModel) onSave;
  final VoidCallback onClose;

  const NoteEditor({
    super.key,
    this.note,
    required this.onSave,
    required this.onClose,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  TextSelection _selection = const TextSelection.collapsed(offset: 0);
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;
  TextAlign _textAlign = TextAlign.left;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.note?.content ?? widget.note?.title ?? '',
    );
    _controller.addListener(_updateSelection);
  }

  void _updateSelection() {
    setState(() {
      _selection = _controller.selection;
      _updateFormattingState();
    });
  }

  void _updateFormattingState() {
    // Обновляем состояние форматирования на основе выделения
    // Пока упрощенная версия - проверяем весь текст
    final text = _controller.text;
    if (text.isEmpty) {
      setState(() {
        _isBold = false;
        _isItalic = false;
        _isUnderline = false;
      });
      return;
    }
  }

  Widget _parseAndDisplayText(String text) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    // Удаляем HTML-теги выравнивания и применяем найденное выравнивание
    TextAlign? align;
    String cleanedText = text;

    // Ищем все div теги с выравниванием (поддерживаем одинарные и двойные кавычки)
    final divPattern = RegExp('<div\\s+style=["\']text-align:\\s*(\\w+)["\']>(.*?)</div>', dotAll: true);
    
    // Находим все div теги и извлекаем выравнивание из первого
    final matches = divPattern.allMatches(text);
    if (matches.isNotEmpty) {
      final firstMatch = matches.first;
      final alignValue = firstMatch.group(1);
      
      // Удаляем все div теги рекурсивно (на случай вложенных или внутри markdown)
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
        default:
          align = TextAlign.left;
      }
    }

    // Парсим markdown
    return Text.rich(
      _parseMarkdown(cleanedText),
      textAlign: align ?? _textAlign,
      style: const TextStyle(
        fontSize: 16,
        height: 1.6,
        color: Colors.black,
      ),
    );
  }

  // Парсинг markdown в TextSpan с поддержкой вложений
  TextSpan _parseMarkdown(String text) {
    if (text.isEmpty) return const TextSpan(text: '');
    return _parseMarkdownRecursive(text);
  }

  TextSpan _parseMarkdownRecursive(String text) {
    if (text.isEmpty) return const TextSpan(text: '');

    final spans = <TextSpan>[];
    int i = 0;

    while (i < text.length) {
      // **bold**
      if (i < text.length - 1 && text[i] == '*' && text[i + 1] == '*') {
        final close = text.indexOf('**', i + 2);
        if (close != -1) {
          final inner = _parseMarkdownRecursive(text.substring(i + 2, close));
          spans.add(TextSpan(
            children: inner.children ?? [TextSpan(text: inner.text ?? '')],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ));
          i = close + 2;
          continue;
        }
      }

      // *italic*
      if (text[i] == '*' &&
          (i == 0 || text[i - 1] != '*') &&
          (i == text.length - 1 || text[i + 1] != '*')) {
        final close = text.indexOf('*', i + 1);
        if (close != -1 && (close == text.length - 1 || text[close + 1] != '*')) {
          final inner = _parseMarkdownRecursive(text.substring(i + 1, close));
          spans.add(TextSpan(
            children: inner.children ?? [TextSpan(text: inner.text ?? '')],
            style: const TextStyle(fontStyle: FontStyle.italic),
          ));
          i = close + 1;
          continue;
        }
      }

      // __underline__ (двойное подчеркивание)
      if (i < text.length - 1 && text[i] == '_' && text[i + 1] == '_') {
        final close = text.indexOf('__', i + 2);
        if (close != -1) {
          final inner = _parseMarkdownRecursive(text.substring(i + 2, close));
          spans.add(TextSpan(
            children: inner.children ?? [TextSpan(text: inner.text ?? '')],
            style: const TextStyle(decoration: TextDecoration.underline),
          ));
          i = close + 2;
          continue;
        }
      }

      // _strikethrough_ (одинарное подчеркивание трактуем как перечеркивание)
      if (text[i] == '_' &&
          (i == 0 || text[i - 1] != '_') &&
          (i == text.length - 1 || text[i + 1] != '_')) {
        final close = text.indexOf('_', i + 1);
        if (close != -1 && (close == text.length - 1 || text[close + 1] != '_')) {
          final inner = _parseMarkdownRecursive(text.substring(i + 1, close));
          spans.add(TextSpan(
            children: inner.children ?? [TextSpan(text: inner.text ?? '')],
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ));
          i = close + 1;
          continue;
        }
      }

      // Обычный текст
      int next = text.length;
      for (int j = i; j < text.length; j++) {
        if (j < text.length - 1 && text[j] == '*' && text[j + 1] == '*') {
          next = j;
          break;
        } else if (text[j] == '*' && (j == 0 || text[j - 1] != '*') && (j == text.length - 1 || text[j + 1] != '*')) {
          next = j;
          break;
        } else if (j < text.length - 1 && text[j] == '_' && text[j + 1] == '_') {
          next = j;
          break;
        } else if (text[j] == '_' && (j == 0 || text[j - 1] != '_') && (j == text.length - 1 || text[j + 1] != '_')) {
          next = j;
          break;
        }
      }

      spans.add(TextSpan(text: text.substring(i, next == text.length ? text.length : next)));
      i = next == text.length ? text.length : next;
    }

    return TextSpan(children: spans, style: const TextStyle(color: Colors.black));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _applyFormatting(String format) {
    final text = _controller.text;
    if (text.isEmpty) return;

    int start = _selection.start;
    int end = _selection.end;

    // Если нет выделения, применяем ко всему тексту
    if (start == end) {
      start = 0;
      end = text.length;
    }

    if (start < 0 || end > text.length || start > end) return;

    String selectedText = text.substring(start, end);
    String formattedText = '';
    int offset = 0;

    switch (format) {
      case 'bold':
        // Проверяем, уже ли выделен жирным
        if (selectedText.startsWith('**') && selectedText.endsWith('**') && selectedText.length > 4) {
          formattedText = selectedText.substring(2, selectedText.length - 2);
          offset = -4;
        } else {
          formattedText = '**$selectedText**';
          offset = 4;
        }
        break;
      case 'italic':
        // Проверяем, уже ли выделен курсивом
        if (selectedText.startsWith('*') && selectedText.endsWith('*') && selectedText.length > 2 && !selectedText.startsWith('**')) {
          formattedText = selectedText.substring(1, selectedText.length - 1);
          offset = -2;
        } else {
          formattedText = '*$selectedText*';
          offset = 2;
        }
        break;
      case 'underline':
        // Проверяем, уже ли подчеркнут (поддерживаем и одинарное, и двойное подчеркивание)
        if (selectedText.startsWith('_') && selectedText.endsWith('_') && selectedText.length > 2) {
          // Удаляем одинарное подчеркивание
          if (!selectedText.startsWith('__') || !selectedText.endsWith('__')) {
            formattedText = selectedText.substring(1, selectedText.length - 1);
            offset = -2;
          } else {
            // Удаляем двойное подчеркивание
            formattedText = selectedText.substring(2, selectedText.length - 2);
            offset = -4;
          }
        } else {
          // Используем одинарное подчеркивание _text_
          formattedText = '_${selectedText}_';
          offset = 2;
        }
        break;
    }

    final newText = text.replaceRange(start, end, formattedText);
    final newOffset = start + formattedText.length;

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );

    // Обновляем состояние кнопок
    _updateFormattingState();
  }

  void _applyAlignment(TextAlign align) {
    final text = _controller.text;
    if (text.isEmpty) return;

    int start = _selection.start;
    int end = _selection.end;

    // Если нет выделения, не применяем выравнивание
    if (start == end) {
      // Просто обновляем состояние для отображения активной кнопки
      setState(() {
        _textAlign = align;
      });
      return;
    }

    if (start < 0 || end > text.length || start > end) return;

    String selectedText = text.substring(start, end);
    if (selectedText.isEmpty) return;

    // Определяем значение выравнивания
    String alignValue = '';
    switch (align) {
      case TextAlign.left:
        alignValue = 'left';
        break;
      case TextAlign.center:
        alignValue = 'center';
        break;
      case TextAlign.right:
        alignValue = 'right';
        break;
      case TextAlign.justify:
        alignValue = 'justify';
        break;
      default:
        alignValue = 'left';
    }

    // Убираем все существующие div-теги с выравниванием (рекурсивно)
    String cleanedText = selectedText;
    RegExp divPattern = RegExp(r'<div\s+style=["'']text-align:\s*\w+["'']>(.*?)</div>', dotAll: true);
    
    // Убираем все вложенные div-теги с выравниванием до тех пор, пока они есть
    int iterations = 0;
    while (divPattern.hasMatch(cleanedText) && iterations < 10) {
      cleanedText = cleanedText.replaceAllMapped(divPattern, (match) {
        final innerText = match.group(1) ?? '';
        return innerText;
      });
      iterations++;
    }
    
    // Проверяем, обернут ли весь текст в один div с нужным выравниванием
    final outerDivPatternStr = '^\\s*<div\\s+style=["'']text-align:\\s*$alignValue["'']>(.*?)</div>\\s*\$';
    final outerDivPattern = RegExp(outerDivPatternStr, dotAll: true);
    final outerMatch = outerDivPattern.firstMatch(cleanedText.trim());
    
    if (outerMatch != null) {
      // Если весь текст уже обернут в div с нужным выравниванием, убираем обертку
      cleanedText = outerMatch.group(1) ?? cleanedText;
    } else {
      // Оборачиваем весь очищенный текст одним div-тегом с нужным выравниванием
      cleanedText = '<div style="text-align: $alignValue">$cleanedText</div>';
    }
    
    selectedText = cleanedText;

    final newText = text.replaceRange(start, end, selectedText);
    final newOffset = start + selectedText.length;

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }

  void _applyList(String type) {
    final text = _controller.text;
    if (text.isEmpty) {
      // Если текст пустой, добавляем первый элемент списка
      final prefix = type == 'bullet' ? '• ' : '1. ';
      _controller.value = TextEditingValue(
        text: prefix,
        selection: TextSelection.collapsed(offset: prefix.length),
      );
      return;
    }

    final lines = text.split('\n');
    final startOffset = _selection.start;
    final endOffset = _selection.end;
    
    // Находим строки, которые попадают в выделение
    int currentOffset = 0;
    int startLine = 0;
    int endLine = 0;
    
    for (int i = 0; i < lines.length; i++) {
      final lineLength = lines[i].length + 1; // +1 для символа новой строки
      if (currentOffset <= startOffset && startOffset < currentOffset + lineLength) {
        startLine = i;
      }
      if (currentOffset <= endOffset && endOffset < currentOffset + lineLength) {
        endLine = i;
        break;
      }
      currentOffset += lineLength;
    }

    // Применяем форматирование списка
    int numberCounter = 1;
    for (int i = startLine; i <= endLine && i < lines.length; i++) {
      final line = lines[i];
      final trimmedLine = line.trim();
      
      if (trimmedLine.isEmpty) {
        // Пустая строка - добавляем маркер списка
        if (type == 'bullet') {
          lines[i] = '• ';
        } else {
          lines[i] = '$numberCounter. ';
          numberCounter++;
        }
      } else {
        // Проверяем, есть ли уже маркер списка
        final hasBullet = trimmedLine.startsWith('• ');
        final hasNumber = RegExp(r'^\d+\. ').hasMatch(trimmedLine);
        
        if (type == 'bullet') {
          if (hasNumber) {
            // Убираем нумерацию и добавляем маркер
            lines[i] = '• ${trimmedLine.replaceFirst(RegExp(r'^\d+\. '), '')}';
          } else if (!hasBullet) {
            // Добавляем маркер
            lines[i] = '• $trimmedLine';
          } else {
            // Убираем маркер
            lines[i] = trimmedLine.replaceFirst('• ', '');
          }
        } else {
          if (hasBullet) {
            // Убираем маркер и добавляем нумерацию
            lines[i] = '$numberCounter. ${trimmedLine.replaceFirst('• ', '')}';
            numberCounter++;
          } else if (!hasNumber) {
            // Добавляем нумерацию
            lines[i] = '$numberCounter. $trimmedLine';
            numberCounter++;
          } else {
            // Убираем нумерацию
            lines[i] = trimmedLine.replaceFirst(RegExp(r'^\d+\. '), '');
          }
        }
      }
    }

    final newText = lines.join('\n');
    final newOffset = _selection.start + (newText.length - text.length);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset.clamp(0, newText.length)),
    );
  }

  void _handleSave() {
    final screenWidth = MediaQuery.of(context).size.width;
    final defaultWidth = screenWidth < 768 
        ? screenWidth - 60  // Уменьшено с 40 до 60 для мобильных
        : screenWidth < 1024 
            ? (screenWidth - 60) / 2 - 10
            : (screenWidth - 60) / 3 - 10;

    final note = (widget.note ?? NoteModel(
      title: _controller.text.split('\n').first,
      content: _controller.text,
      x: 0,
      y: 0,
      width: defaultWidth.clamp(200.0, screenWidth < 768 ? screenWidth - 60 : 395.0),
      height: 150,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    )).copyWith(
      title: _controller.text.split('\n').first,
      content: _controller.text,
      updatedAt: DateTime.now(),
    );
    widget.onSave(note);
  }


  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            // Убираем клавиатуру при тапе вне поля ввода
            FocusScope.of(context).unfocus();
          },
          behavior: HitTestBehavior.translucent,
          child: Container(
            color: Colors.black.withOpacity(0.4),
            child: GestureDetector(
              onTap: () {}, // Предотвращаем закрытие при клике на модалку
              child: DraggableScrollableSheet(
                initialChildSize: 0.9,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
              return GestureDetector(
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity != null && details.primaryVelocity! > 1000) {
                    // Свайп вниз - закрываем и сбрасываем содержимое
                    _controller.clear();
                    widget.onClose();
                  }
                },
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  child: Column(
                    children: [
                      // Панель инструментов
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8F8F8),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE5E5E5), width: 1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    // Группа форматирования текста
                                    _buildToolbarGroup([
                                      _buildToolbarButton(
                                        icon: Icons.format_bold,
                                        isActive: _isBold,
                                        onTap: () {
                                          _applyFormatting('bold');
                                          setState(() {
                                            _isBold = !_isBold;
                                          });
                                        },
                                      ),
                                      _buildToolbarButton(
                                        icon: Icons.format_italic,
                                        isActive: _isItalic,
                                        onTap: () {
                                          _applyFormatting('italic');
                                          setState(() {
                                            _isItalic = !_isItalic;
                                          });
                                        },
                                      ),
                                      _buildToolbarButton(
                                        icon: Icons.format_underlined,
                                        isActive: _isUnderline,
                                        onTap: () {
                                          _applyFormatting('underline');
                                          setState(() {
                                            _isUnderline = !_isUnderline;
                                          });
                                        },
                                      ),
                                    ]),
                                    const SizedBox(width: 12),
                                    // Группа выравнивания
                                    _buildToolbarGroup([
                                      _buildToolbarButton(
                                        icon: Icons.format_align_left,
                                        isActive: _textAlign == TextAlign.left,
                                        onTap: () => _applyAlignment(TextAlign.left),
                                      ),
                                      _buildToolbarButton(
                                        icon: Icons.format_align_center,
                                        isActive: _textAlign == TextAlign.center,
                                        onTap: () => _applyAlignment(TextAlign.center),
                                      ),
                                      _buildToolbarButton(
                                        icon: Icons.format_align_right,
                                        isActive: _textAlign == TextAlign.right,
                                        onTap: () => _applyAlignment(TextAlign.right),
                                      ),
                                      _buildToolbarButton(
                                        icon: Icons.format_align_justify,
                                        isActive: _textAlign == TextAlign.justify,
                                        onTap: () => _applyAlignment(TextAlign.justify),
                                      ),
                                    ]),
                                    const SizedBox(width: 12),
                                    // Группа списков
                                    _buildToolbarGroup([
                                      _buildToolbarButton(
                                        icon: Icons.format_list_bulleted,
                                        onTap: () => _applyList('bullet'),
                                      ),
                                      _buildToolbarButton(
                                        icon: Icons.format_list_numbered,
                                        onTap: () => _applyList('number'),
                                      ),
                                    ]),
                                  ],
                                ),
                              ),
                            ),
                            // Кнопка сохранения (галочка в черном круге)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: GestureDetector(
                                onTap: () {
                                  _handleSave();
                                  widget.onClose();
                                },
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Область редактирования
                      Expanded(
                        child: Stack(
                          children: [
                            // Текстовое поле с форматированием
                            Container(
                              padding: const EdgeInsets.all(20),
                              child: Stack(
                                children: [
                                  // Форматированный текст (для отображения)
                                  if (!_focusNode.hasFocus && _controller.text.isNotEmpty)
                                    Positioned.fill(
                                      child: SingleChildScrollView(
                                        child: _parseAndDisplayText(_controller.text),
                                      ),
                                    ),
                                  // Поле ввода (для редактирования)
                                  TextField(
                                    controller: _controller,
                                    focusNode: _focusNode,
                                    maxLines: null,
                                    expands: true,
                                    textAlign: _textAlign,
                                    style: TextStyle(
                                      fontSize: 16,
                                      height: 1.6,
                                      color: _focusNode.hasFocus ? Colors.black : Colors.transparent,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Начните писать...',
                                      hintStyle: TextStyle(
                                        color: Color(0xFF999999),
                                      ),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                  ),
              );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbarGroup(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.only(right: 12),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFFE5E5E5), width: 1),
        ),
      ),
      child: Row(
        children: children,
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    bool isActive = false,
    Color? color,
    required VoidCallback onTap,
  }) {
    final buttonColor = color ?? (isActive ? Colors.black : const Color(0xFF666666));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isActive ? const Color(0xFFE5E5E5) : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 18,
          color: buttonColor,
        ),
      ),
    );
  }
}

