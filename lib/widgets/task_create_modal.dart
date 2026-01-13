import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/task.dart';
import '../models/attached_file.dart';
import 'apple_calendar.dart';
import 'custom_snackbar.dart';

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

class _TaskCreateModalState extends State<TaskCreateModal> with TickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();
  int _selectedPriority = 0; // 0 = не выбран, 1 = красный, 2 = желтый, 3 = синий
  DateTime _selectedDate = DateTime.now();
  late AnimationController _animationController;
  late AnimationController _wavesAnimationController;
  AnimationController? _buttonsSlideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _wavesAnimation;
  Animation<Offset> _buttonsSlideAnimation = const AlwaysStoppedAnimation(Offset.zero);
  String _previousTitleText = '';
  String _previousDescriptionText = '';
  List<AttachedFile> _attachedFiles = [];
  bool _isTagsExpanded = false;
  final ScrollController _chipsScrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechInitialized = false;
  String _selectedField = ''; // 'title' or 'description'

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
      _attachedFiles = t.attachedFiles ?? [];
    } else if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
    }
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _wavesAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
    _buttonsSlideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _wavesAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _wavesAnimationController,
      curve: Curves.easeInOut,
    ));
    _buttonsSlideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _buttonsSlideController!,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
    
    // Отслеживание фокуса полей
    _titleFocusNode.addListener(_onTitleFocusChange);
    _descriptionFocusNode.addListener(_onDescriptionFocusChange);
    
    _previousTitleText = _titleController.text;
    _previousDescriptionText = _descriptionController.text;
    
    _titleController.addListener(_limitTitleLines);
    _descriptionController.addListener(_limitDescriptionLines);
    
    // Фокусируемся на поле названия после анимации
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _titleFocusNode.requestFocus();
          }
        });
      }
    });
  }
  
  void _limitTitleLines() {
    if (!mounted) return;
    final text = _titleController.text;
    
    // Проверка на максимальное количество символов (70)
    if (text.length > 70) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _titleController.text != _previousTitleText) {
          _titleController.value = TextEditingValue(
            text: _previousTitleText,
            selection: TextSelection.collapsed(offset: _previousTitleText.length),
          );
          HapticFeedback.mediumImpact();
        }
      });
      return;
    }
    
    final textStyle = const TextStyle(fontSize: 24, fontWeight: FontWeight.w600);
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth - 40; // Учитываем padding 20px с каждой стороны
    
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(minWidth: 0, maxWidth: maxWidth);
    
    final lineHeight = tp.preferredLineHeight;
    final actualLines = (tp.size.height / lineHeight).ceil();
    
    // Проверка на максимальное количество строк (3)
    if (actualLines > 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _titleController.text != _previousTitleText) {
          _titleController.value = TextEditingValue(
            text: _previousTitleText,
            selection: TextSelection.collapsed(offset: _previousTitleText.length),
          );
          HapticFeedback.mediumImpact();
        }
      });
    } else {
      _previousTitleText = text;
    }
  }
  
  void _limitDescriptionLines() {
    if (!mounted) return;
    final text = _descriptionController.text;
    
    // Проверка на максимальное количество символов (200)
    if (text.length > 200) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _descriptionController.text != _previousDescriptionText) {
          _descriptionController.value = TextEditingValue(
            text: _previousDescriptionText,
            selection: TextSelection.collapsed(offset: _previousDescriptionText.length),
          );
          HapticFeedback.mediumImpact();
        }
      });
      return;
    }
    
    final textStyle = const TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth - 40; // Учитываем padding 20px с каждой стороны
    
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(minWidth: 0, maxWidth: maxWidth);
    
    final lineHeight = tp.preferredLineHeight;
    final actualLines = (tp.size.height / lineHeight).ceil();
    
    // Проверка на максимальное количество строк (8)
    if (actualLines > 8) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _descriptionController.text != _previousDescriptionText) {
          _descriptionController.value = TextEditingValue(
            text: _previousDescriptionText,
            selection: TextSelection.collapsed(offset: _previousDescriptionText.length),
          );
          HapticFeedback.mediumImpact();
        }
      });
    } else {
      _previousDescriptionText = text;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _wavesAnimationController.dispose();
    _buttonsSlideController?.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _titleFocusNode.dispose();
    _descriptionFocusNode.dispose();
    _chipsScrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  void _onTitleFocusChange() {
    if (_titleFocusNode.hasFocus) {
      setState(() {
        _selectedField = 'title';
      });
    }
  }

  void _onDescriptionFocusChange() {
    if (_descriptionFocusNode.hasFocus) {
      setState(() {
        _selectedField = 'description';
      });
    }
  }

  Future<bool> _initializeSpeech() async {
    if (_speechInitialized) {
      return true;
    }
    
    try {
      bool available = await _speech.initialize(
        onError: (error) {
          debugPrint('Speech recognition error: $error');
          if (mounted) {
            setState(() {
              _speechInitialized = false;
              _isListening = false;
            });
          }
        },
        onStatus: (status) {
          debugPrint('Speech recognition status: $status');
          if (status == 'listening') {
            // Запись успешно началась - подтверждаем состояние
            if (mounted && !_isListening) {
              setState(() {
                _isListening = true;
              });
              _wavesAnimationController.repeat();
            }
          } else if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() {
                _isListening = false;
              });
              _wavesAnimationController.stop();
              _buttonsSlideController?.reverse();
            }
          } else if (status == 'error') {
            if (mounted) {
              setState(() {
                _isListening = false;
              });
              _wavesAnimationController.stop();
              _buttonsSlideController?.reverse();
            }
          }
        },
      );
      
      if (mounted) {
        setState(() {
          _speechInitialized = available;
        });
      }
      
      if (!available) {
        debugPrint('Speech recognition not available');
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('Error initializing speech recognition: $e');
      if (mounted) {
        setState(() {
          _speechInitialized = false;
        });
      }
      return false;
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    CustomSnackBar.show(context, msg);
  }

  void _handleClose() {
    // Закрываем клавиатуру перед анимацией
    FocusScope.of(context).unfocus();
    // Задержка для синхронизации с закрытием клавиатуры
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _animationController.reverse().then((_) {
          widget.onClose();
        });
      }
    });
  }

  void _handleSave() {
    if (_titleController.text.trim().isEmpty) {
      return;
    }

    // Если приоритет не выбран, используем 2 по умолчанию
    final priority = _selectedPriority == 0 ? 2 : _selectedPriority;

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
      priority: priority,
      tags: tags,
      date: _selectedDate,
      endDate: null,
      isCompleted: widget.initialTask?.isCompleted ?? false,
      attachedFiles: _attachedFiles.isNotEmpty ? _attachedFiles : null,
    );

    widget.onSave(task);
    _handleClose();
  }

  void _togglePriority() {
    setState(() {
      if (_selectedPriority == 0) {
        _selectedPriority = 1;
      } else if (_selectedPriority == 1) {
        _selectedPriority = 2;
      } else if (_selectedPriority == 2) {
        _selectedPriority = 3;
      } else {
        _selectedPriority = 1;
      }
    });
  }

  Color _getPriorityColor() {
    switch (_selectedPriority) {
      case 1:
        return Colors.red;
      case 2:
        return const Color(0xFFFFB800); // Более видимый желтый вместо кислотного
      case 3:
        return const Color(0xFF0066FF);
      default:
        return const Color(0xFF666666); // Серый для нейтрального
    }
  }

  String _getPriorityIconPath() {
    switch (_selectedPriority) {
      case 1:
        return 'assets/icon/thunder-red.png';
      case 2:
        return 'assets/icon/thunder-yellow.png';
      case 3:
        return 'assets/icon/thunder-blue.png';
      default:
        return 'assets/icon/thunder-red.png'; // Для нейтрального используем серый через ColorFilter
    }
  }

  String _getPriorityText() {
    if (_selectedPriority == 0) {
      return 'Приоритет';
    }
    return 'Приоритет $_selectedPriority';
  }

  String _getMonthName(int month) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return months[month - 1];
  }

  String _getDayName(int weekday) {
    const days = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
    return days[weekday - 1];
  }

  Future<void> _openCalendar() async {
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
                  if (Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                  if (mounted) {
                    setState(() {
                      _selectedDate = d;
                    });
                  }
                },
                onClose: () {
                  if (Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                },
                tasks: const [],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _handleDictate() async {
    if (_selectedField.isEmpty) {
      // Если поле не выбрано, просто возвращаемся
      return;
    }

    // Проверяем инициализацию
    if (!_speechInitialized) {
      bool initialized = await _initializeSpeech();
      if (!initialized) {
        _showMessage('Распознавание речи недоступно. Убедитесь, что приложение перезапущено.');
        return;
      }
    }

    if (_isListening) {
      // Останавливаем запись
      try {
        await _speech.stop();
        setState(() {
          _isListening = false;
        });
        _wavesAnimationController.stop();
        _buttonsSlideController?.reverse();
      } catch (e) {
        debugPrint('Error stopping speech: $e');
        setState(() {
          _isListening = false;
        });
        _wavesAnimationController.stop();
      }
    } else {
      // Вибрация при начале записи
      HapticFeedback.mediumImpact();
      
      // Начинаем запись
      try {
        await _speech.listen(
          onResult: (result) {
            String text = result.recognizedWords;
            if (_selectedField == 'title') {
              _titleController.text = text;
            } else if (_selectedField == 'description') {
              _descriptionController.text = text;
            }
          },
          localeId: 'ru_RU',
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
          partialResults: true,
        );
        
        // Устанавливаем состояние сразу, статус подтвердится через onStatus
        setState(() {
          _isListening = true;
        });
        _wavesAnimationController.repeat();
        _buttonsSlideController?.forward();
      } catch (e) {
        debugPrint('Error starting speech: $e');
        _showMessage('Ошибка при запуске записи');
        setState(() {
          _isListening = false;
        });
      }
    }
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
                color: Colors.black.withValues(alpha: 0.4),
              ),
            ),
            SlideTransition(
              position: _slideAnimation,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      // Заголовок с датой
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_selectedDate.day} ${_getMonthName(_selectedDate.month)} • ${_getDayName(_selectedDate.weekday)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Поле ввода названия без бордеров
                            TextField(
                              controller: _titleController,
                              focusNode: _titleFocusNode,
                              autofocus: true,
                              maxLines: 3,
                              minLines: 1,
                              maxLength: 70,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                                height: 1.2,
                              ),
                              decoration: const InputDecoration(
                                isCollapsed: true,
                                hintText: 'Сходить в магазин..',
                                hintStyle: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF999999),
                                  height: 1.2,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                counterText: '',
                              ),
                              cursorColor: Colors.black,
                            ),
                            const SizedBox(height: 10),
                            // Поле ввода описания без бордеров
                            TextField(
                              controller: _descriptionController,
                              focusNode: _descriptionFocusNode,
                              maxLines: 8,
                              minLines: 1,
                              maxLength: 200,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: Colors.black,
                                height: 1.4,
                              ),
                              decoration: const InputDecoration(
                                isCollapsed: true,
                                hintText: 'Описание',
                                hintStyle: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF999999),
                                  height: 1.4,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                counterText: '',
                              ),
                              cursorColor: Colors.black,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Овалы с функциями
                      Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: SingleChildScrollView(
                          controller: _chipsScrollController,
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              // Овал с датой
                              _buildOvalChip(
                                icon: Icons.calendar_today,
                                text: '${_selectedDate.day} ${_getMonthName(_selectedDate.month)}',
                                onTap: _openCalendar,
                              ),
                              const SizedBox(width: 8),
                              // Овал с приоритетом
                              _buildPriorityChip(),
                              const SizedBox(width: 8),
                              // Овал прикрепить
                              _buildAttachmentChip(),
                              const SizedBox(width: 8),
                              // Овал хештеги
                              _buildTagsChip(),
                              const SizedBox(width: 20), // Отступ справа для красоты
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Нижняя панель с действиями
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Row(
                          children: [
                            // Выпадающий список "Входящие"
                            GestureDetector(
                              onTap: () {
                                // TODO: Реализовать выбор папки
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.folder_outlined,
                                    size: 18,
                                    color: Color(0xFF999999),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Мои заметки',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF999999),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 18,
                                    color: Color(0xFF999999),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            // Кнопки диктовки
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Кнопка "Продиктовать" с анимацией волн (всегда на месте)
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Анимированные волны (Positioned чтобы не влияли на layout)
                                      if (_isListening)
                                        ...List.generate(3, (index) {
                                          return AnimatedBuilder(
                                            animation: _wavesAnimation,
                                            builder: (context, child) {
                                              final delay = index * 0.2;
                                              final animationValue = ((_wavesAnimation.value + delay) % 1.0);
                                              final size = 48 + (animationValue * 30);
                                              return Positioned(
                                                left: (48 - size) / 2,
                                                top: (48 - size) / 2,
                                                child: Container(
                                                  width: size,
                                                  height: size,
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.withOpacity(0.3 * (1 - animationValue)),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        }),
                                      // Кнопка микрофона (всегда видна)
                                      GestureDetector(
                                        onTap: _handleDictate,
                                        child: Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: _isListening ? Colors.red.shade700 : Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.mic,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Кнопка остановки записи (появляется справа при записи)
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  child: _isListening
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          key: const ValueKey('stop_button'),
                                          children: [
                                            const SizedBox(width: 12),
                                            GestureDetector(
                                              onTap: _handleDictate,
                                              child: Container(
                                                width: 48,
                                                height: 48,
                                                decoration: const BoxDecoration(
                                                  color: Colors.black,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 24,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : const SizedBox.shrink(key: ValueKey('empty')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Кнопка сохранения
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _handleSave,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(21),
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
                      ),
                      ],
                      ),
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

  Widget _buildOvalChip({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: const Color(0xFF666666),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityChip() {
    final priorityColor = _getPriorityColor();
    final iconPath = _getPriorityIconPath();
    
    return GestureDetector(
      onTap: _togglePriority,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: _selectedPriority > 0
              ? Border(
                  left: BorderSide(
                    color: priorityColor,
                    width: 4,
                  ),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _selectedPriority == 0
                ? ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      const Color(0xFF666666),
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      'assets/icon/thunder-red.png',
                      width: 18,
                      height: 18,
                    ),
                  )
                : Image.asset(
                    iconPath,
                    width: 18,
                    height: 18,
                  ),
            const SizedBox(width: 8),
            Text(
              _getPriorityText(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _selectedPriority > 0 ? priorityColor : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    try {
      FocusScope.of(context).unfocus();
      HapticFeedback.mediumImpact();
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final newFiles = <AttachedFile>[];
        
        for (var platformFile in result.files) {
          if (platformFile.path != null || platformFile.bytes != null) {
            String? filePath;
            int fileSize = 0;
            
            if (platformFile.path != null) {
              filePath = platformFile.path;
              final file = File(filePath!);
              if (await file.exists()) {
                fileSize = await file.length();
              }
            } else if (platformFile.bytes != null) {
              final tempDir = await getTemporaryDirectory();
              final fileName = platformFile.name;
              final tempFile = File(path.join(tempDir.path, fileName));
              await tempFile.writeAsBytes(platformFile.bytes!);
              filePath = tempFile.path;
              fileSize = platformFile.bytes!.length;
            }

            if (filePath != null) {
              final extension = path.extension(platformFile.name).toLowerCase().replaceFirst('.', '');
              final fileType = _getFileType(extension);
              
              final attachedFile = AttachedFile(
                fileName: platformFile.name,
                filePath: filePath,
                fileType: fileType,
                fileSize: fileSize,
              );
              
              newFiles.add(attachedFile);
            }
          }
        }

        if (newFiles.isNotEmpty) {
          setState(() {
            _attachedFiles.addAll(newFiles);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Ошибка при выборе файла: $e');
      }
    }
  }

  String _getFileType(String extension) {
    final imageTypes = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
    final docTypes = ['doc', 'docx'];
    final excelTypes = ['xls', 'xlsx'];
    final pptTypes = ['ppt', 'pptx'];
    
    if (imageTypes.contains(extension)) return 'image';
    if (extension == 'pdf') return 'pdf';
    if (docTypes.contains(extension)) return 'word';
    if (excelTypes.contains(extension)) return 'excel';
    if (pptTypes.contains(extension)) return 'powerpoint';
    if (extension == 'txt') return 'text';
    if (extension == 'rtf') return 'rtf';
    return 'other';
  }

  Widget _buildAttachmentChip() {
    return GestureDetector(
      onTap: _pickFiles,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.attach_file,
              size: 18,
              color: Color(0xFF666666),
            ),
            const SizedBox(width: 8),
            Text(
              _attachedFiles.isEmpty ? 'Прикрепить' : 'Прикреплено (${_attachedFiles.length})',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsChip() {
    if (_isTagsExpanded) {
      // Прокручиваем влево, чтобы поле было видно
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chipsScrollController.hasClients) {
          _chipsScrollController.animateTo(
            _chipsScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.tag,
              size: 18,
              color: Color(0xFF666666),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _tagsController,
                autofocus: true,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF666666),
                ),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  hintText: 'продукты',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF999999),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) {
                  setState(() {
                    _isTagsExpanded = false;
                  });
                },
                onEditingComplete: () {
                  setState(() {
                    _isTagsExpanded = false;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isTagsExpanded = false;
                });
              },
              child: const Icon(
                Icons.check,
                size: 18,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _isTagsExpanded = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tag,
              size: 18,
              color: Color(0xFF666666),
            ),
            SizedBox(width: 8),
            Text(
              'Хештеги',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
