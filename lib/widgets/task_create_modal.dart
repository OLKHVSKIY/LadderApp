import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../models/attached_file.dart';
import 'apple_calendar.dart';
import 'custom_snackbar.dart';
import 'file_attachment_picker.dart';

class TaskCreateModal extends StatefulWidget {
  final VoidCallback onClose;
  final Function(Task) onSave;
  final Task? initialTask;
  final bool isEdit;
  final DateTime? initialDate;

  const TaskCreateModal({
    super.key,
    required this.onClose,
    required this.onSave,
    this.initialTask,
    this.isEdit = false,
    this.initialDate,
  });

  @override
  State<TaskCreateModal> createState() => _TaskCreateModalState();
}

class _TaskCreateModalState extends State<TaskCreateModal> with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  int _selectedPriority = 1;
  bool _isDateRange = false;
  DateTime _selectedDate = DateTime.now();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isStartDateCalendarOpen = false;
  bool _isEndDateCalendarOpen = false;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  String _previousTitleText = '';
  String _previousDescriptionText = '';
  List<AttachedFile> _attachedFiles = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialTask != null) {
      final t = widget.initialTask!;
      _titleController.text = t.title;
      _descriptionController.text = t.description ?? '';
      _tagsController.text = t.tags.join(' ');
      _selectedPriority = t.priority;
      _selectedDate = t.date;
      _startDate = t.date;
      _endDate = t.endDate;
      _isDateRange = t.endDate != null;
      _attachedFiles = t.attachedFiles ?? [];
    } else if (widget.initialDate != null) {
      // Если передана начальная дата (выбранная дата из календаря), используем её
      _selectedDate = widget.initialDate!;
      _startDate = widget.initialDate!;
    }
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
    
    // Инициализируем предыдущие значения
    _previousTitleText = _titleController.text;
    _previousDescriptionText = _descriptionController.text;
    
    // Добавляем слушатели для ограничения количества строк
    _titleController.addListener(_limitTitleLines);
    _descriptionController.addListener(_limitDescriptionLines);
  }
  
  void _limitTitleLines() {
    if (!mounted) return;
    final text = _titleController.text;
    
    // Используем TextPainter для определения реального количества строк
    final textStyle = const TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 0.8 - 32; // Примерная ширина поля
    
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(minWidth: 0, maxWidth: maxWidth);
    
    final lineHeight = tp.preferredLineHeight;
    final actualLines = (tp.size.height / lineHeight).ceil();
    
    // Если превышен лимит строк, блокируем ввод и вибрируем
    if (actualLines > 3) {
      // Откатываем к предыдущему значению
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _titleController.text != _previousTitleText) {
          _titleController.value = TextEditingValue(
            text: _previousTitleText,
            selection: TextSelection.collapsed(offset: _previousTitleText.length),
          );
          // Вибрация при попытке ввести больше 3 строк
          HapticFeedback.mediumImpact();
        }
      });
    } else {
      // Сохраняем текущее значение как предыдущее
      _previousTitleText = text;
    }
  }
  
  void _limitDescriptionLines() {
    if (!mounted) return;
    final text = _descriptionController.text;
    
    // Используем TextPainter для определения реального количества строк
    final textStyle = const TextStyle(fontSize: 14);
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 0.8 - 32; // Примерная ширина поля
    
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(minWidth: 0, maxWidth: maxWidth);
    
    final lineHeight = tp.preferredLineHeight;
    final actualLines = (tp.size.height / lineHeight).ceil();
    
    // Если превышен лимит строк, блокируем ввод и вибрируем
    if (actualLines > 8) {
      // Откатываем к предыдущему значению
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _descriptionController.text != _previousDescriptionText) {
          _descriptionController.value = TextEditingValue(
            text: _previousDescriptionText,
            selection: TextSelection.collapsed(offset: _previousDescriptionText.length),
          );
          // Вибрация при попытке ввести больше 8 строк
          HapticFeedback.mediumImpact();
        }
      });
    } else {
      // Сохраняем текущее значение как предыдущее
      _previousDescriptionText = text;
    }
  }
  
  void _limitTextFieldLines(TextEditingController controller, String value, double maxWidth, int maxLines) {
    if (!mounted) return;
    
    // Используем TextPainter для определения реального количества строк с учетом автоматических переносов
    final textStyle = const TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
    final tp = TextPainter(
      text: TextSpan(text: value, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(minWidth: 0, maxWidth: maxWidth - 32); // Учитываем padding (16px с каждой стороны)
    
    final lineHeight = tp.preferredLineHeight;
    final actualLines = (tp.size.height / lineHeight).ceil();
    
    if (actualLines > maxLines) {
      // Находим позицию, где заканчивается maxLines-я строка
      double targetY = (maxLines - 1) * lineHeight + lineHeight / 2;
      final position = tp.getPositionForOffset(Offset(0, targetY));
      
      // Обрезаем текст до этой позиции
      final limitedText = value.substring(0, position.offset);
      
      if (controller.text != limitedText) {
        controller.value = TextEditingValue(
          text: limitedText,
          selection: TextSelection.collapsed(offset: limitedText.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    CustomSnackBar.show(context, msg);
  }

  void _handleClose() {
    _animationController.reverse().then((_) {
      widget.onClose();
    });
  }

  void _handleSave() {
    if (_titleController.text.trim().isEmpty) {
      return;
    }

    final tags = _tagsController.text
        .split(' ')
        .where((tag) => tag.trim().isNotEmpty)
        .map((tag) => tag.startsWith('#') ? tag : '#$tag')
        .toList();

    final task = Task(
      id: widget.initialTask?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      priority: _selectedPriority,
      tags: tags,
      date: _isDateRange ? (_startDate ?? _selectedDate) : _selectedDate,
      endDate: _isDateRange ? (_endDate ?? _startDate ?? _selectedDate) : null,
      isCompleted: widget.initialTask?.isCompleted ?? false,
      attachedFiles: _attachedFiles.isNotEmpty ? _attachedFiles : null,
    );

    widget.onSave(task);
    _handleClose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        opacity: 1.0,
        child: Stack(
          children: [
            GestureDetector(
              onTap: _handleClose,
              child: Container(
                color: Colors.black.withOpacity(0.4),
              ),
            ),
            SlideTransition(
              position: _slideAnimation,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.9,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                    // Заголовок
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.isEdit ? 'Редактировать задачу' : 'Новая задача',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          GestureDetector(
                            onTap: _handleClose,
                            child: const Icon(
                              Icons.close,
                              size: 24,
                              color: Color(0xFF999999),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Форма
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Название
                            LayoutBuilder(
                              builder: (context, constraints) {
                                return _buildTextField(
                                  label: 'Название',
                                  controller: _titleController,
                                  hint: '',
                                  maxLength: 70,
                                  maxWidth: constraints.maxWidth,
                                  maxLinesLimit: 3,
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                            // Описание
                            LayoutBuilder(
                              builder: (context, constraints) {
                                return _buildTextArea(
                                  label: 'Описание',
                                  controller: _descriptionController,
                                  hint: '(Необязательно)',
                                  maxLength: 200,
                                  maxWidth: constraints.maxWidth,
                                  maxLinesLimit: 8,
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                            // Приоритет
                            _buildPrioritySelector(),
                            const SizedBox(height: 24),
                            // Хештеги
                            _buildTextField(
                              label: 'Хештеги',
                              controller: _tagsController,
                              hint: 'Например: #работа #дом',
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Вводите хештеги через пробел',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Прикрепленные файлы
                            FileAttachmentPicker(
                              initialFiles: _attachedFiles,
                              onFilesChanged: (files) {
                                setState(() {
                                  _attachedFiles = files;
                                });
                              },
                            ),
                            const SizedBox(height: 24),
                            // Тип даты
                            _buildDateTypeSelector(),
                            const SizedBox(height: 24),
                            // Выбор даты
                            _buildDateSelector(),
                            const SizedBox(height: 40),
                            // Кнопки
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _handleClose,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      side: const BorderSide(
                                        color: Color(0xFF6D6D6D),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(19),
                                      ),
                                    ),
                                    child: const Text(
                                      'Отмена',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF666666),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _handleSave,
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      backgroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(19),
                                      ),
                                    ),
                                    child: const Text(
                                      'Создать',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int? maxLength,
    double? maxWidth,
    int? maxLinesLimit,
  }) {
    const borderColor = Color(0xFFB0B0B0);
    const labelColor = Color(0xFF666666);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: borderColor, width: 1),
              color: Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: TextField(
                controller: controller,
                maxLength: maxLength,
                maxLines: maxLinesLimit ?? 1,
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: hint,
                  hintStyle: const TextStyle(color: Color(0xFF999999), fontSize: 16),
                  border: InputBorder.none,
                  counterText: null,
                ),
                style: const TextStyle(fontSize: 18, color: Colors.black),
                cursorColor: Colors.black,
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: -11,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                style: const TextStyle(
                  color: labelColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextArea({
    required String label,
    required TextEditingController controller,
    required String hint,
    int? maxLength,
    double? maxWidth,
    int? maxLinesLimit,
  }) {
    const borderColor = Color(0xFFB0B0B0);
    const labelColor = Color(0xFF666666);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: borderColor, width: 1),
              color: Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: TextField(
                controller: controller,
                maxLength: maxLength,
                maxLines: maxLinesLimit ?? 8,
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: hint,
                  hintStyle: const TextStyle(color: Color(0xFF999999), fontSize: 16),
                  border: InputBorder.none,
                  counterText: null,
                ),
                style: const TextStyle(fontSize: 18, color: Colors.black),
                cursorColor: Colors.black,
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: -11,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                style: const TextStyle(
                  color: labelColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Приоритет',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF666666),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [1, 2, 3].map((priority) {
              final isSelected = _selectedPriority == priority;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPriority = priority;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          _getPriorityIcon(priority),
                          width: 20,
                          height: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$priority',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? Colors.black : const Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDateTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Дата',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF666666),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isDateRange = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !_isDateRange ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: !_isDateRange
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: const Center(
                      child: Text(
                        'Один день',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isDateRange = true;
                      _startDate = _selectedDate;
                      _endDate = _selectedDate;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isDateRange ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _isDateRange
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: const Center(
                      child: Text(
                        'Период',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelector() {
    if (_isDateRange) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Выберите период',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    DateTime selected = _startDate ?? DateTime.now();
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (ctx) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(ctx).viewInsets.bottom,
                            left: 20,
                            right: 20,
                            top: 20,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Выберите дату начала',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              AppleCalendar(
                                initialDate: _startDate ?? DateTime.now(),
                                onDateSelected: (d) {
                                  selected = d;
                                },
                                onClose: () {},
                                tasks: const [],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: MediaQuery.of(ctx).size.width * 0.6,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    setState(() {
                                      _startDate = selected;
                                    });
                                  },
                                  child: const Text('Выбрать'),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E5E5)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'С',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF666666),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _startDate != null
                              ? '${_startDate!.day} ${_getMonthName(_startDate!.month)} ${_startDate!.year}'
                              : 'Выберите дату',
                          style: TextStyle(
                            fontSize: _startDate != null ? 18 : 14,
                            fontWeight: FontWeight.w500,
                            color: _startDate != null ? Colors.black : const Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    if (_startDate == null) {
                      _showMessage('Сначала выберите дату начала');
                      return;
                    }
                    DateTime selected = _endDate ?? _startDate!;
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (ctx) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(ctx).viewInsets.bottom,
                            left: 20,
                            right: 20,
                            top: 20,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Выберите дату окончания',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              AppleCalendar(
                                initialDate: _endDate ?? _startDate!,
                                onDateSelected: (d) {
                                  selected = d;
                                },
                                onClose: () {},
                                tasks: const [],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: MediaQuery.of(ctx).size.width * 0.6,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    setState(() {
                                      _endDate = selected;
                                    });
                                  },
                                  child: const Text('Выбрать'),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E5E5)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'По',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF666666),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _endDate != null
                              ? '${_endDate!.day} ${_getMonthName(_endDate!.month)} ${_endDate!.year}'
                              : 'Выберите дату',
                          style: TextStyle(
                            fontSize: _endDate != null ? 18 : 14,
                            fontWeight: FontWeight.w500,
                            color: _endDate != null ? Colors.black : const Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Выберите дату',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              DateTime selected = _selectedDate;
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom,
                      left: 20,
                      right: 20,
                      top: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Выберите дату',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        AppleCalendar(
                          initialDate: _selectedDate,
                          onDateSelected: (d) {
                            selected = d;
                          },
                          onClose: () {},
                          tasks: const [],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: MediaQuery.of(ctx).size.width * 0.6,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              setState(() {
                                _selectedDate = selected;
                              });
                            },
                            child: const Text('Выбрать'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  );
                },
              );
            },
            child: GestureDetector(
              onTap: () async {
                DateTime selected = _selectedDate;
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (ctx) {
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(ctx).viewInsets.bottom,
                        left: 20,
                        right: 20,
                        top: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Выберите дату',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          AppleCalendar(
                            initialDate: _selectedDate,
                            onDateSelected: (d) {
                              selected = d;
                            },
                            onClose: () {},
                            tasks: const [],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: MediaQuery.of(ctx).size.width * 0.6,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                setState(() {
                                  _selectedDate = selected;
                                });
                              },
                              child: const Text('Выбрать'),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    );
                  },
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${_selectedDate.day}',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_getMonthName(_selectedDate.month)} ${_selectedDate.year}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                    const Icon(
                      Icons.calendar_today,
                      size: 20,
                      color: Color(0xFF999999),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  String _getPriorityIcon(int priority) {
    switch (priority) {
      case 1:
        return 'assets/icon/thunder-red.png';
      case 2:
        return 'assets/icon/thunder-yellow.png';
      case 3:
        return 'assets/icon/thunder-blue.png';
      default:
        return 'assets/icon/thunder-red.png';
    }
  }

  String _getMonthName(int month) {
    const months = [
      'янв.',
      'фев.',
      'мар.',
      'апр.',
      'май',
      'июн.',
      'июл.',
      'авг.',
      'сен.',
      'окт.',
      'ноя.',
      'дек.',
    ];
    return months[month - 1];
  }
}

