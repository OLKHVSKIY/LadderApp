import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../models/habit.dart';
import '../models/event.dart';
import '../models/attached_file.dart';
import '../models/note_model.dart';
import '../data/repositories/note_repository.dart';
import 'apple_calendar.dart';
import 'custom_snackbar.dart';
import '../data/database_instance.dart';
import '../data/app_database.dart' as db;
import '../data/user_session.dart';
import 'package:drift/drift.dart' as dr;
import 'glass.dart';
import 'event_image_cropper.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

class TaskCreateModal extends StatefulWidget {
  final VoidCallback onClose;
  final Function(Task, int?) onSave; // Теперь принимает также screenId
  final Task? initialTask;
  final bool isEdit;
  final DateTime? initialDate;
  final int? currentScreenId; // ID текущего экрана (null = "Мои задачи")
  // Создание/редактирование привычки. Если onSaveHabit задан — в шторке
  // появляется переключатель «Задача / Привычка». initialHabit открывает
  // шторку сразу в режиме привычки для редактирования.
  final Function(Habit, int?)? onSaveHabit;
  final Habit? initialHabit;
  // Создание/редактирование события. Если onSaveEvent задан — в переключателе
  // режимов появляется сегмент «Событие». initialEvent открывает шторку сразу
  // в режиме события для редактирования.
  final Function(Event, int?)? onSaveEvent;
  final Event? initialEvent;
  // Открыть событие в режиме просмотра (поля заблокированы, кнопка
  // «Редактировать»). Тап по событию — просмотр; «Редактировать» из меню — сразу
  // редактирование.
  final bool eventViewMode;

  const TaskCreateModal({
    super.key,
    required this.onClose,
    required this.onSave,
    this.initialTask,
    this.isEdit = false,
    this.initialDate,
    this.currentScreenId,
    this.onSaveHabit,
    this.initialHabit,
    this.onSaveEvent,
    this.initialEvent,
    this.eventViewMode = false,
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
  // Свайп-вниз для закрытия шторки: текущее смещение и контроллер «доводки».
  double _dragDy = 0.0;
  late AnimationController _dragController;
  // Крестик закрытия (вверху справа) разворачивается в подтверждение отмены.
  bool _cancelConfirmOpen = false;
  late AnimationController _cancelController;
  // Шаг планирования времени задачи (после ввода названия и тапа «Создать»).
  bool _schedulingStep = false;
  // Начало задачи в минутах от полуночи (шаг 15 мин) и длительность в минутах.
  int _scheduleStartMinutes = 10 * 60;
  int _durationMinutes = 15;
  // Значения длительности (мин) для блока «Продолжительность». Мутабельны:
  // в шторке настройки можно добавить кастомную / удалить чип / сбросить.
  // В блоке отображается до 5 активных шаблонов; в запасе всего до 8.
  // Лишние (неактивные) хранятся в _inactiveDurations и в шторке имеют «+».
  static const int _maxDurationOptions = 5; // отображаемых (активных)
  static const int _maxDurationPool = 8; // всего в запасе
  static const List<int> _defaultDurationOptions = [15, 30, 45, 60, 90];
  List<int> _durationOptions = List<int>.from(_defaultDurationOptions);
  List<int> _inactiveDurations = [];
  static const String _durationOptionsPrefKey = 'duration_options';
  static const String _inactiveDurationsPrefKey = 'duration_options_inactive';
  // Задача на весь день: блоки «Время» и «Продолжительность» скрываются.
  bool _allDay = false;
  // Подробный режим времени (начало→конец, шаг 1 мин). Запоминается в prefs.
  bool _detailedTime = false;
  static const String _detailedTimePrefKey = 'time_picker_detailed';
  // Меню-троеточие у секции «Время».
  final GlobalKey _timeMenuKey = GlobalKey();
  OverlayEntry? _timeMenuOverlay;
  // Колёса подробного режима (начало ч/мин, конец ч/мин).
  late final FixedExtentScrollController _detStartHourCtrl;
  late final FixedExtentScrollController _detStartMinCtrl;
  late final FixedExtentScrollController _detEndHourCtrl;
  late final FixedExtentScrollController _detEndMinCtrl;
  String _previousTitleText = '';
  String _previousDescriptionText = '';
  List<AttachedFile> _attachedFiles = [];
  bool _isTagsExpanded = false;
  final ScrollController _chipsScrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechInitialized = false;
  String _selectedField = ''; // 'title' or 'description'
  int? _selectedScreenId; // null = "Мои задачи", иначе ID кастомного экрана
  List<db.CustomTaskScreen> _screens = [];
  // Режим повтора задачи (русский ключ перевода). 'Не повторять' = одна задача.
  String _repeatMode = 'Не повторять';
  final GlobalKey _repeatChipKey = GlobalKey();
  OverlayEntry? _repeatMenuOverlay;

  // Режим привычки.
  bool _isHabit = false;
  int _habitMask = Habit.maskDaily;
  int _habitColorIndex = 0;
  int _habitIconIndex = 0;
  final GlobalKey _scheduleChipKey = GlobalKey();
  OverlayEntry? _scheduleMenuOverlay;
  DateTime _habitStartDate = DateTime.now();
  DateTime? _habitEndDate;
  final GlobalKey _periodChipKey = GlobalKey();
  OverlayEntry? _periodMenuOverlay;
  // Выбор экрана — выпадающее меню в стиле остальных меню шторки.
  final GlobalKey _screenChipKey = GlobalKey();
  OverlayEntry? _screenMenuOverlay;

  // Цвет и иконка задачи (выбираются в отдельной шторке «Цвет и иконка»).
  int _taskColorIndex = 0; // персиковый по умолчанию
  int _taskIconIndex = 0;

  // Палитра цветов задачи (персиковый первый — дефолт).
  static const List<int> _taskColors = [
    0xFFFFB59A, // персиковый
    0xFFFF3B30, // красный
    0xFFFF7A45, // коралловый
    0xFFFF9500, // оранжевый
    0xFFFFCC00, // жёлтый
    0xFF34C759, // зелёный
    0xFF30D158, // лаймовый
    0xFF00C7BE, // бирюзовый
    0xFF32ADE6, // голубой
    0xFF007AFF, // синий
    0xFF5856D6, // индиго
    0xFFAF52DE, // фиолетовый
    0xFFFF2D55, // розовый
    0xFFA2845E, // коричневый
    0xFF8E8E93, // серый
  ];

  // Иконки задачи.
  static const List<IconData> _taskIcons = [
    CupertinoIcons.check_mark_circled,
    CupertinoIcons.star_fill,
    CupertinoIcons.flag_fill,
    CupertinoIcons.bell_fill,
    CupertinoIcons.heart_fill,
    CupertinoIcons.bolt_fill,
    CupertinoIcons.flame_fill,
    CupertinoIcons.book_fill,
    CupertinoIcons.briefcase_fill,
    CupertinoIcons.cart_fill,
    CupertinoIcons.house_fill,
    CupertinoIcons.airplane,
    CupertinoIcons.car_fill,
    CupertinoIcons.gift_fill,
    CupertinoIcons.money_dollar_circle_fill,
    CupertinoIcons.creditcard_fill,
    CupertinoIcons.phone_fill,
    CupertinoIcons.mail_solid,
    CupertinoIcons.chat_bubble_2_fill,
    CupertinoIcons.calendar,
    CupertinoIcons.clock_fill,
    CupertinoIcons.alarm_fill,
    CupertinoIcons.drop_fill,
    CupertinoIcons.sportscourt_fill,
    CupertinoIcons.sun_max_fill,
    CupertinoIcons.moon_fill,
    CupertinoIcons.bed_double_fill,
    CupertinoIcons.paintbrush_fill,
    CupertinoIcons.music_note,
    CupertinoIcons.camera_fill,
    CupertinoIcons.game_controller_solid,
    CupertinoIcons.bag_fill,
    CupertinoIcons.heart_circle_fill,
    CupertinoIcons.lightbulb_fill,
    CupertinoIcons.pencil,
    CupertinoIcons.doc_text_fill,
    CupertinoIcons.lock_fill,
  ];

  // Режим события.
  bool _isEvent = false;
  // Режим просмотра события (поля заблокированы, кнопка «Редактировать»).
  // По «Редактировать» переключается в false — открывается редактор.
  bool _eventView = false;
  bool _eventRepeatYearly = false;
  bool _eventNotifyDayBefore = false;
  bool _eventNotifyOnDay = true; // по умолчанию уведомление в день события
  String? _eventImagePath;

  // Показывать переключатель режимов (Задача / Привычка / Событие). Только при
  // создании с нуля — не при редактировании уже существующей сущности.
  // Открыта ли шторка «Цвет и иконка». Пока открыта — скрываем нативный
  // сегмент Задача/Привычка/Событие (platform-view просвечивает чёрным сквозь
  // размытие шторки).
  bool _colorSheetOpen = false;

  bool get _showModeToggle =>
      (widget.onSaveHabit != null || widget.onSaveEvent != null) &&
      !widget.isEdit &&
      widget.initialHabit == null &&
      widget.initialEvent == null &&
      !_colorSheetOpen;

  @override
  void initState() {
    super.initState();
    _selectedScreenId = widget.currentScreenId; // По умолчанию текущий экран
    // Загружаем экраны асинхронно после инициализации
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScreens();
    });
    if (widget.initialEvent != null) {
      final e = widget.initialEvent!;
      _isEvent = true;
      _eventView = widget.eventViewMode;
      _titleController.text = e.title;
      _descriptionController.text = e.description ?? '';
      _selectedDate = e.date;
      _eventRepeatYearly = e.repeatYearly;
      _eventNotifyDayBefore = e.notifyDayBefore;
      _eventNotifyOnDay = e.notifyOnDay;
      _eventImagePath = e.imagePath;
    } else if (widget.initialHabit != null) {
      final h = widget.initialHabit!;
      _isHabit = true;
      _titleController.text = h.title;
      _descriptionController.text = h.description ?? '';
      _habitMask = h.scheduleMask;
      _habitColorIndex = HabitPalette.colorIndex(h.colorValue);
      _habitIconIndex = h.iconIndex;
      _habitStartDate = h.startDate ?? DateTime.now();
      _habitEndDate = h.endDate;
    } else if (widget.initialTask != null) {
      final t = widget.initialTask!;
      _titleController.text = t.title;
      _descriptionController.text = t.description ?? '';
      _tagsController.text = t.tags.join(' ');
      _selectedPriority = t.priority;
      _selectedDate = t.date;
      _attachedFiles = t.attachedFiles ?? [];
      // Восстанавливаем время начала и длительность из существующей задачи.
      _scheduleStartMinutes = t.date.hour * 60 + t.date.minute;
      if (t.endDate != null) {
        final diff = t.endDate!.difference(t.date).inMinutes;
        if (diff > 0) _durationMinutes = diff;
      }
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
    _dragController = AnimationController(
      duration: const Duration(milliseconds: 240),
      vsync: this,
    );
    _cancelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 240),
      vsync: this,
    );
    // Для новой задачи — начало в ближайшие 15 минут от текущего времени.
    if (widget.initialTask == null) {
      final now = DateTime.now();
      _scheduleStartMinutes = ((now.hour * 60 + now.minute) ~/ 15 + 1) * 15;
      if (_scheduleStartMinutes >= 24 * 60) _scheduleStartMinutes = 23 * 60 + 45;
    }
    // Колёса подробного режима — стартовые позиции из начала/конца задачи.
    final endTotal = _scheduleStartMinutes + _durationMinutes;
    _detStartHourCtrl =
        FixedExtentScrollController(initialItem: _scheduleStartMinutes ~/ 60);
    _detStartMinCtrl =
        FixedExtentScrollController(initialItem: _scheduleStartMinutes % 60);
    _detEndHourCtrl =
        FixedExtentScrollController(initialItem: (endTotal ~/ 60) % 24);
    _detEndMinCtrl = FixedExtentScrollController(initialItem: endTotal % 60);
    // Запомненный выбор типа времени + кастомные шаблоны длительности.
    SharedPreferences.getInstance().then((prefs) {
      final detailed = prefs.getBool(_detailedTimePrefKey) ?? false;
      final stored = prefs.getStringList(_durationOptionsPrefKey);
      final opts = stored
          ?.map((e) => int.tryParse(e))
          .whereType<int>()
          .toList();
      final storedInactive = prefs.getStringList(_inactiveDurationsPrefKey);
      final inactive = storedInactive
          ?.map((e) => int.tryParse(e))
          .whereType<int>()
          .toList();
      if (!mounted) return;
      setState(() {
        _detailedTime = detailed;
        if (opts != null && opts.isNotEmpty) {
          _durationOptions = opts.take(_maxDurationOptions).toList();
        }
        if (inactive != null) {
          _inactiveDurations = inactive
              .take(_maxDurationPool - _durationOptions.length)
              .toList();
        }
      });
    });
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
    _dragController.dispose();
    _cancelController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _titleFocusNode.dispose();
    _descriptionFocusNode.dispose();
    _chipsScrollController.dispose();
    _speech.stop();
    _repeatMenuOverlay?.remove();
    _repeatMenuOverlay = null;
    _scheduleMenuOverlay?.remove();
    _scheduleMenuOverlay = null;
    _periodMenuOverlay?.remove();
    _periodMenuOverlay = null;
    _screenMenuOverlay?.remove();
    _screenMenuOverlay = null;
    _timeMenuOverlay?.remove();
    _timeMenuOverlay = null;
    _detStartHourCtrl.dispose();
    _detStartMinCtrl.dispose();
    _detEndHourCtrl.dispose();
    _detEndMinCtrl.dispose();
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
    // Не закрываем клавиатуру - пользователь может продолжать вводить текст
    // Задержка для синхронизации с анимацией
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _animationController.reverse().then((_) {
          widget.onClose();
        });
      }
    });
  }

  // Разворачивает крестик в карточку-подтверждение отмены.
  void _openCancelConfirm() {
    setState(() => _cancelConfirmOpen = true);
    _cancelController.forward();
  }

  // Сворачивает карточку-подтверждение обратно в крестик.
  void _closeCancelConfirm() {
    _cancelController.reverse().whenComplete(() {
      if (mounted) setState(() => _cancelConfirmOpen = false);
    });
  }

  // Палец потянул шторку вниз — двигаем её за пальцем (только вниз).
  void _onSheetDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragDy = (_dragDy + details.delta.dy).clamp(0.0, double.infinity);
    });
  }

  // Отпустили: достаточно утянули или резкий флик вниз — закрываем,
  // иначе плавно возвращаем шторку на место.
  void _onSheetDragEnd(DragEndDetails details, double sheetHeight) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldClose = _dragDy > 140 || velocity > 700;
    final from = _dragDy;
    final to = shouldClose ? sheetHeight : 0.0;
    final tween = Tween<double>(begin: from, end: to);
    final anim = tween.animate(
      CurvedAnimation(parent: _dragController, curve: Curves.easeOutCubic),
    );
    void listener() => setState(() => _dragDy = anim.value);
    anim.addListener(listener);
    _dragController
      ..reset()
      ..forward().whenComplete(() {
        anim.removeListener(listener);
        if (shouldClose) {
          widget.onClose();
        } else {
          _dragDy = 0.0;
        }
      });
  }

  // Нижняя кнопка: для просмотра события — в редактирование; для задачи —
  // сначала шаг планирования времени; для привычки/события — сразу сохранение.
  void _handlePrimaryButton() {
    if (_eventView) {
      setState(() => _eventView = false);
      return;
    }
    if (!_isHabit && !_isEvent) {
      if (_titleController.text.trim().isEmpty) return;
      FocusScope.of(context).unfocus();
      setState(() => _schedulingStep = true);
      return;
    }
    _handleSave();
  }

  // Возврат с шага планирования времени к редактированию названия/описания.
  // Клавиатура появляется снова (фокус на поле названия).
  void _backToEditing() {
    setState(() => _schedulingStep = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocusNode.requestFocus();
    });
  }

  void _handleSave() {
    if (_titleController.text.trim().isEmpty) {
      return;
    }

    // Режим события — собираем Event и отдаём через onSaveEvent.
    if (_isEvent) {
      final event = Event(
        id: widget.initialEvent?.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        date: _selectedDate,
        repeatYearly: _eventRepeatYearly,
        notifyDayBefore: _eventNotifyDayBefore,
        notifyOnDay: _eventNotifyOnDay,
        imagePath: _eventImagePath,
      );
      widget.onSaveEvent?.call(event, _selectedScreenId);
      _handleClose();
      return;
    }

    // Режим привычки — собираем Habit и отдаём через onSaveHabit.
    if (_isHabit) {
      final habit = Habit(
        id: widget.initialHabit?.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        colorValue: HabitPalette.colors[_habitColorIndex],
        iconIndex: _habitIconIndex,
        scheduleMask: _habitMask,
        startDate: _habitStartDate,
        endDate: _habitEndDate,
      );
      widget.onSaveHabit?.call(habit, _selectedScreenId);
      _handleClose();
      return;
    }

    // Если приоритет не выбран, используем 2 по умолчанию
    final priority = _selectedPriority == 0 ? 2 : _selectedPriority;

    final tags = _tagsController.text
        .split(' ')
        .where((tag) => tag.trim().isNotEmpty)
        .map((tag) => tag.startsWith('#') ? tag : '#$tag')
        .toList();

    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    // С учётом повтора создаём отдельную задачу на каждую дату.
    final dates = _repeatDates();
    final baseId = DateTime.now().millisecondsSinceEpoch;
    final startH = _scheduleStartMinutes ~/ 60;
    final startM = _scheduleStartMinutes % 60;
    final createdTasks = <Task>[];
    for (var i = 0; i < dates.length; i++) {
      final d = dates[i];
      // Время начала из выбранного блока «Время», конец = старт + длительность.
      final start = DateTime(d.year, d.month, d.day, startH, startM);
      final task = Task(
        id: widget.initialTask?.id ?? '${baseId}_$i',
        title: _titleController.text.trim(),
        description: description,
        priority: priority,
        tags: tags,
        date: start,
        endDate: start.add(Duration(minutes: _durationMinutes)),
        isCompleted: widget.initialTask?.isCompleted ?? false,
        attachedFiles: _attachedFiles.isNotEmpty ? _attachedFiles : null,
      );
      widget.onSave(task, _selectedScreenId);
      createdTasks.add(task);
    }
    // Синхронизация со страницей «Список»: на каждую НОВУЮ задачу создаём
    // заметку-блок на таймлайне в том же интервале, с выбранным цветом и
    // иконкой. При редактировании заметку не дублируем.
    if (widget.initialTask == null) {
      unawaited(_createTimelineNotes(createdTasks));
    }
    _handleClose();
  }

  // Создаёт на таймлайне «Списка» заметку-блок для каждой созданной задачи
  // (тот же интервал времени, выбранный цвет и иконка задачи).
  Future<void> _createTimelineNotes(List<Task> tasks) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final colorInt = _taskColors[_taskColorIndex];
    final colorHex =
        '#${(colorInt & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final iconKey = 'cupertino:${_taskIcons[_taskIconIndex].codePoint}';
    final repo = NoteRepository(appDatabase);
    for (final task in tasks) {
      final end = task.endDate ??
          task.date.add(Duration(minutes: _durationMinutes));
      final noteData = {
        'type': 'timeline',
        'startTime': task.date.toIso8601String(),
        'endTime': end.toIso8601String(),
        'color': colorHex,
        'icon': iconKey,
        'description': task.description ?? '',
        'linkedElementType': 'task',
        'linkedElementId': task.id,
        'notify': true,
        'allDay': _allDay,
      };
      final note = NoteModel(
        title: task.title,
        content: jsonEncode(noteData),
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        color: colorHex,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      try {
        await repo.saveNote(note, userId);
      } catch (_) {
        // Игнорируем ошибки сохранения отдельной заметки.
      }
    }
  }

  // Список дат с учётом выбранного режима повтора (ближайшие 30 дней).
  List<DateTime> _repeatDates() {
    // При редактировании повтор не применяем — сохраняем одну дату.
    if (widget.initialTask != null || _repeatMode == 'Не повторять') {
      return [_selectedDate];
    }
    final dates = <DateTime>[];
    for (var i = 0; i < 30; i++) {
      final d = _selectedDate.add(Duration(days: i));
      switch (_repeatMode) {
        case 'Каждый день':
          dates.add(d);
          break;
        case 'По будням':
          if (d.weekday >= DateTime.monday && d.weekday <= DateTime.friday) {
            dates.add(d);
          }
          break;
        case 'Каждую неделю':
          if (d.weekday == _selectedDate.weekday) dates.add(d);
          break;
      }
    }
    return dates.isEmpty ? [_selectedDate] : dates;
  }

  Future<void> _loadScreens() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    try {
      final screens = await (appDatabase.select(appDatabase.customTaskScreens)
            ..where((tbl) => tbl.userId.equals(userId))
            ..orderBy([(tbl) => dr.OrderingTerm.asc(tbl.id)]))
          .get();
      
      if (mounted) {
        setState(() {
          _screens = screens;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки экранов: $e');
    }
  }

  String _getSelectedScreenName() {
    if (_selectedScreenId == null) {
      return tr('Мои задачи');
    }
    try {
      final screen = _screens.firstWhere(
        (s) => s.id == _selectedScreenId,
      );
      return screen.name;
    } catch (e) {
      return tr('Мои задачи');
    }
  }

  void _removeScreenMenu() {
    _screenMenuOverlay?.remove();
    _screenMenuOverlay = null;
  }

  // Выпадающее меню выбора экрана (тот же стиль, что у «Повтор»/«Период»).
  // Открывается ВВЕРХ над чипом, т.к. чип в нижней части шторки.
  void _showScreenMenu() {
    HapticFeedback.lightImpact();
    _removeScreenMenu();
    final overlay = Overlay.of(context);
    final renderBox =
        _screenChipKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPosition = renderBox.localToGlobal(Offset.zero);
    const menuWidth = 220.0;
    final screenSize = MediaQuery.of(context).size;
    double left = anchorPosition.dx;
    if (left + menuWidth > screenSize.width - 12) {
      left = screenSize.width - 12 - menuWidth;
    }
    if (left < 12) left = 12;
    final bottom = screenSize.height - (anchorPosition.dy - 6);

    // Список пунктов: «Мои задачи» (null) + кастомные экраны.
    final names = <String>[tr('Мои задачи'), ..._screens.map((s) => s.name)];
    final ids = <int?>[null, ..._screens.map((s) => s.id)];

    _screenMenuOverlay = OverlayEntry(
      builder: (context) => _RepeatGlassMenu(
        left: left,
        bottom: bottom,
        width: menuWidth,
        options: names,
        currentValue: _getSelectedScreenName(),
        onSelected: (v) {
          _removeScreenMenu();
          final idx = names.indexOf(v);
          setState(() => _selectedScreenId = idx >= 0 ? ids[idx] : null);
        },
        onClose: _removeScreenMenu,
      ),
    );
    overlay.insert(_screenMenuOverlay!);
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
      return tr('Приоритет');
    }
    return tr('Приоритет {0}', [_selectedPriority]);
  }

  String _getMonthName(int month) {
    final months = [
      tr('января'),
      tr('февраля'),
      tr('марта'),
      tr('апреля'),
      tr('мая'),
      tr('июня'),
      tr('июля'),
      tr('августа'),
      tr('сентября'),
      tr('октября'),
      tr('ноября'),
      tr('декабря'),
    ];
    return months[month - 1];
  }

  String _getDayName(int weekday) {
    final days = [tr('Понедельник'), tr('Вторник'), tr('Среда'), tr('Четверг'), tr('Пятница'), tr('Суббота'), tr('Воскресенье')];
    return days[weekday - 1];
  }

  Future<void> _openCalendar() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              Text(
                tr('Выберите дату'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.of(ctx).textPrimary),
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
        _showMessage(tr('Распознавание речи недоступно. Убедитесь, что приложение перезапущено.'));
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
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.dictation,
            cancelOnError: true,
            partialResults: true,
          ),
        );
        
        // Устанавливаем состояние сразу, статус подтвердится через onStatus
        setState(() {
          _isListening = true;
        });
        _wavesAnimationController.repeat();
        _buttonsSlideController?.forward();
      } catch (e) {
        debugPrint('Error starting speech: $e');
        _showMessage(tr('Ошибка при запуске записи'));
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // Просмотр события: компактная шторка (максимум — пол-экрана, минимум —
    // по содержимому), закрывается крестиком без подтверждения.
    final bool eventViewing = _isEvent && _eventView;
    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        opacity: 1.0,
        child: Stack(
          children: [
            GestureDetector(
              onTap: _handleClose,
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: Colors.black.withValues(alpha: 0.4),
              ),
            ),
            SlideTransition(
              position: _slideAnimation,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Transform.translate(
                  // Смещение от свайпа-вниз (палец тянет шторку к закрытию).
                  offset: Offset(0, _dragDy),
                  child: Container(
                  // Просмотр события — шторка по содержимому (не выше пол-экрана).
                  // Иначе — на весь экран (минус системная строка статуса);
                  // +11, чтобы перекрыть грабер страницы Задачи под шторкой.
                  height: eventViewing
                      ? null
                      : MediaQuery.of(context).size.height -
                          MediaQuery.of(context).padding.top +
                          11,
                  constraints: eventViewing
                      ? BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.5,
                        )
                      : null,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (_schedulingStep)
                        _buildSchedulingBody(colors)
                      else
                      Column(
                    mainAxisSize:
                        eventViewing ? MainAxisSize.min : MainAxisSize.max,
                    children: [
                      // Грабер-«язычок» + зона свайпа вниз для закрытия шторки.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: _onSheetDragUpdate,
                        onVerticalDragEnd: (d) => _onSheetDragEnd(
                          d,
                          MediaQuery.of(context).size.height -
                              MediaQuery.of(context).padding.top,
                        ),
                        child: Container(
                          width: double.infinity,
                          color: Colors.transparent,
                          padding: const EdgeInsets.only(top: 10, bottom: 4),
                          child: Center(
                            child: Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colors.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Прокручиваемая часть (заголовок, поля, чипы).
                      Flexible(
                        fit: eventViewing
                            ? FlexFit.loose
                            : FlexFit.tight,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                      // Заголовок с датой. Верхний отступ увеличен, чтобы
                      // крестик закрытия аккуратно вместился над сегментом.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 44, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_showModeToggle) ...[
                              _buildModeToggle(),
                              const SizedBox(height: 41),
                            ],
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Овал выбора цвета и иконки задачи (слева от
                                // даты/названия/описания). Только для задачи.
                                if (!_isHabit && !_isEvent) ...[
                                  _buildTaskIconOval(colors),
                                  const SizedBox(width: 14),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                            Text(
                              _isEvent
                                  ? (widget.initialEvent != null
                                      ? tr('Событие')
                                      : tr('Новое событие'))
                                  : _isHabit
                                      ? (widget.initialHabit != null
                                          ? tr('Привычка')
                                          : tr('Новая привычка'))
                                      : '${_selectedDate.day} ${_getMonthName(_selectedDate.month)} • ${_getDayName(_selectedDate.weekday)}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: colors.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Поле ввода названия без бордеров
                            TextField(
                              controller: _titleController,
                              focusNode: _titleFocusNode,
                              autofocus: !_eventView,
                              readOnly: _eventView,
                              maxLines: 3,
                              minLines: 1,
                              maxLength: 70,
                              // Для задачи на клавиатуре справа снизу — стрелка
                              // «дальше» (продолжить к шагу времени). Для
                              // привычки/события — галочка, закрывает клавиатуру.
                              textInputAction:
                                  (!_isHabit && !_isEvent && !_eventView)
                                      ? TextInputAction.next
                                      : TextInputAction.done,
                              onSubmitted: (_) {
                                if (!_isHabit && !_isEvent && !_eventView) {
                                  _handlePrimaryButton();
                                } else {
                                  FocusScope.of(context).unfocus();
                                }
                              },
                              // Тап вне поля НЕ скрывает клавиатуру (по умолч.
                              // Flutter 3.7+ скрывает) — на этапе ввода имени
                              // клавиатура должна оставаться.
                              onTapOutside: (_) {},
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                                height: 1.2,
                              ),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                hintText: _isEvent
                                    ? tr('День рождения..')
                                    : _isHabit
                                        ? tr('Читать книгу..')
                                        : tr('Сходить в магазин..'),
                                hintStyle: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textTertiary,
                                  height: 1.2,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                counterText: '',
                              ),
                              cursorColor: colors.textPrimary,
                            ),
                            const SizedBox(height: 10),
                            // Поле ввода описания без бордеров
                            TextField(
                              controller: _descriptionController,
                              focusNode: _descriptionFocusNode,
                              readOnly: _eventView,
                              maxLines: 8,
                              minLines: 1,
                              maxLength: 200,
                              onTapOutside: (_) {},
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: colors.textPrimary,
                                height: 1.4,
                              ),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                hintText: tr('Описание'),
                                hintStyle: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  color: colors.textTertiary,
                                  height: 1.4,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                counterText: '',
                              ),
                              cursorColor: colors.textPrimary,
                            ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Овалы с функциями. В режиме просмотра события чипы
                      // заблокированы (только просмотр).
                      IgnorePointer(
                        ignoring: _eventView,
                        child: Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: SingleChildScrollView(
                          controller: _chipsScrollController,
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _isEvent
                                ? [
                                    // Овал с датой
                                    _buildOvalChip(
                                      icon: Icons.calendar_today,
                                      text: '${_selectedDate.day} ${_getMonthName(_selectedDate.month)}',
                                      onTap: _openCalendar,
                                    ),
                                    const SizedBox(width: 8),
                                    // Овал повтора (каждый год / один раз)
                                    _buildEventRepeatChip(),
                                    const SizedBox(width: 8),
                                    // Овал уведомления
                                    _buildEventNotifyChip(),
                                    const SizedBox(width: 8),
                                    // Овал картинки
                                    _buildEventImageChip(),
                                    const SizedBox(width: 20),
                                  ]
                                : _isHabit
                                ? [
                                    // Овал расписания
                                    _buildScheduleChip(),
                                    const SizedBox(width: 8),
                                    // Овал периода
                                    _buildPeriodChip(),
                                    const SizedBox(width: 8),
                                    // Овал цвета
                                    _buildHabitColorChip(),
                                    const SizedBox(width: 8),
                                    // Овал значка
                                    _buildHabitIconChip(),
                                    const SizedBox(width: 20),
                                  ]
                                : [
                                    // Овал с датой
                                    _buildOvalChip(
                                      icon: Icons.calendar_today,
                                      text: '${_selectedDate.day} ${_getMonthName(_selectedDate.month)}',
                                      onTap: _openCalendar,
                                    ),
                                    const SizedBox(width: 8),
                                    // Овал повтора
                                    _buildRepeatChip(),
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
                      ),
                            ],
                          ),
                        ),
                      ),
                      // Нижняя закреплённая секция: плавно поднимается вместе с
                      // клавиатурой (bottom = высота клавиатуры; iOS обновляет
                      // viewInsets покадрово → следует за клавиатурой).
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom > 0
                              ? MediaQuery.of(context).viewInsets.bottom
                              : MediaQuery.of(context).padding.bottom,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                      // Нижняя панель с действиями (голосовой ввод). У события
                      // её нет только в режиме просмотра; в редактировании есть.
                      // Отступ сверху задаёт сама панель (vertical: 12).
                      if (!(_isEvent && _eventView))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Row(
                          children: [
                            // Выбор экрана — для задачи, привычки и события.
                            GestureDetector(
                                key: _screenChipKey,
                                onTap: _showScreenMenu,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_outlined,
                                      size: 18,
                                      color: colors.textTertiary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _getSelectedScreenName(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: colors.textTertiary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 18,
                                      color: colors.textTertiary,
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
                                                    color: Colors.red.withValues(alpha: 0.3 * (1 - animationValue)),
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
                                            GlassCircleButton(
                                              onTap: _handleDictate,
                                              size: 48,
                                              iconSize: 22,
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
                      // В режиме просмотра события нижней панели нет — добавляем
                      // отступ перед кнопкой.
                      if (_isEvent && _eventView) const SizedBox(height: 12),
                      // Кнопка сохранения
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            // В режиме просмотра события кнопка переключает в
                            // редактирование, иначе сохраняет.
                            onPressed: _handlePrimaryButton,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: colors.inverseSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(21),
                              ),
                            ),
                            child: Text(
                              // Просмотр события → «Редактировать»; редактирование
                              // существующего → «Сохранить»; создание задачи →
                              // «Продолжить» (дальше шаг времени); создание
                              // привычки/события → «Создать».
                              _eventView
                                  ? tr('Редактировать')
                                  : (widget.isEdit ||
                                          (_isEvent &&
                                              widget.initialEvent != null))
                                      ? tr('Сохранить')
                                      : (!_isHabit && !_isEvent)
                                          ? tr('Продолжить')
                                          : tr('Создать'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: colors.onInverseSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                          ],
                        ),
                      ),
                    ],
                  ),
                      // Тап мимо подтверждения сворачивает его обратно в крестик.
                      if (_cancelConfirmOpen)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeCancelConfirm,
                          ),
                        ),
                      // Крестик закрытия (вверху справа) → плавно превращается
                      // в подтверждение отмены изменений.
                      Positioned(
                        top: 14,
                        right: 14,
                        child: _buildCancelButton(colors),
                      ),
                    ],
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

  // ───────────────────────── Шаг планирования времени ─────────────────────

  // Фон блоков шага — чуть контрастнее (темнее на светлой теме, светлее на
  // тёмной), чтобы блоки были заметнее.
  Color _blockBg(AppColors colors) => Color.alphaBlend(
        colors.textPrimary.withValues(alpha: 0.025),
        colors.surfaceVariant,
      );

  String _formatHM(int minutes) {
    final m = minutes % (24 * 60);
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

  // Полная подпись длительности: «15 мин» / «1 ч» / «1,5 ч».
  // Часы — десятичной дробью без минут: «1 ч», «1,5 ч», «9,4 ч».
  String _durationLabel(int min) {
    if (min < 60) return '$min ${tr('мин')}';
    if (min % 60 == 0) return '${min ~/ 60} ${tr('ч')}';
    final s = (min / 60).toStringAsFixed(1).replaceAll('.', ',');
    return '$s ${tr('ч')}';
  }

  // Короткая подпись пилюли. Единица «мин» показывается ТОЛЬКО у выбранной
  // (нажатой) пилюли (если < 60); часы всегда десятичной дробью.
  String _durationPillLabel(int min, bool selected) {
    if (min < 60) return selected ? '$min ${tr('мин')}' : '$min';
    if (min % 60 == 0) return '${min ~/ 60} ${tr('ч')}';
    final s = (min / 60).toStringAsFixed(1).replaceAll('.', ',');
    return '$s ${tr('ч')}';
  }

  String _shortWeekday(int weekday) {
    const keys = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return tr(keys[weekday - 1]);
  }

  // «Ср, 17 июня 2026 г.»
  String _scheduleDateLabel() {
    return '${_shortWeekday(_selectedDate.weekday)}, ${_selectedDate.day} ${_getMonthName(_selectedDate.month)} ${_selectedDate.year} ${tr('г.')}';
  }

  String _relativeDayLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final diff = sel.difference(today).inDays;
    if (diff == 0) return tr('Сегодня');
    if (diff == 1) return tr('Завтра');
    return _shortWeekday(_selectedDate.weekday);
  }

  // Тело второго шага: цветной заголовок задачи, дата, выбор времени (колесо)
  // и длительности, кнопка «Продолжить».
  Widget _buildSchedulingBody(AppColors colors) {
    final accent = Color(_taskColors[_taskColorIndex]);
    final icon = _taskIcons[_taskIconIndex];
    final startStr = _formatHM(_scheduleStartMinutes);
    final endStr = _formatHM(_scheduleStartMinutes + _durationMinutes);
    final desc = _descriptionController.text.trim();
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Column(
      children: [
        // Цветной заголовок задачи (цвет = выбранный цвет задачи).
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          child: Column(
            children: [
              // Грабер-«язычок» для свайпа вниз.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: _onSheetDragUpdate,
                onVerticalDragEnd: (d) => _onSheetDragEnd(
                  d,
                  MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top,
                ),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  // Кружок с цветом и иконкой задачи.
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(icon, color: Colors.white, size: 36),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    // Тап по названию/описанию возвращает к шагу
                    // редактирования (клавиатура появляется снова).
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _backToEditing,
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$startStr—$endStr (${_durationLabel(_durationMinutes)})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _titleController.text.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ],
                    ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Блоки выбора даты / времени / длительности.
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildScheduleDateBlock(colors),
                const SizedBox(height: 28),
                _buildSectionHeader(
                  colors,
                  tr('Время'),
                  menuKey: _timeMenuKey,
                  onMenuTap: _showTimeMenu,
                ),
                // Колесо времени скрывается для задачи «на весь день».
                _collapsible(
                  !_allDay,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      _detailedTime
                          ? _buildDetailedTimeWheel(colors)
                          : _buildTimeWheel(colors),
                    ],
                  ),
                ),
                // Продолжительность скрывается в режимах «весь день» и «подробно».
                _collapsible(
                  !_allDay && !_detailedTime,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 28),
                      _buildSectionHeader(
                        colors,
                        tr('Продолжительность'),
                        onMenuTap: _openDurationSheet,
                      ),
                      const SizedBox(height: 14),
                      _buildDurationPicker(colors),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Кнопка «Создать» (при редактировании — «Сохранить»).
        Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset > 0 ? bottomInset : 20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _handleSave,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: colors.inverseSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: Text(
                widget.isEdit ? tr('Сохранить') : tr('Создать'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.onInverseSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Плавное сворачивание/разворачивание секции (высота + прозрачность).
  Widget _collapsible(bool visible, Widget child) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: visible ? 1.0 : 0.0,
        child: visible
            ? child
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }

  // Заголовок секции («Время» / «Продолжительность») + кнопка-троеточие.
  // menuKey/onMenuTap задаются только у секции «Время» (открывают меню).
  Widget _buildSectionHeader(
    AppColors colors,
    String title, {
    Key? menuKey,
    VoidCallback? onMenuTap,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const Spacer(),
        GestureDetector(
          key: menuKey,
          onTap: onMenuTap ?? () => HapticFeedback.selectionClick(),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceVariant.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.ellipsis,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // Блок выбранной даты — тап открывает уже существующий календарь.
  Widget _buildScheduleDateBlock(AppColors colors) {
    return GestureDetector(
      onTap: _openCalendar,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _blockBg(colors),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(CupertinoIcons.calendar,
                  size: 18, color: colors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _scheduleDateLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _relativeDayLabel(),
              style: TextStyle(fontSize: 15, color: colors.textTertiary),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right,
                size: 16, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }

  // Колесо выбора времени (Apple-стиль, шаг 15 мин). Выбранная строка —
  // диапазон «начало—конец» на цветной пилюле.
  Widget _buildTimeWheel(AppColors colors) {
    final selectedIndex = _scheduleStartMinutes ~/ 15;
    const itemExtent = 40.0;
    return Container(
      height: 268,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _blockBg(colors),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Stack(
        children: [
          // Неподвижная пилюля-подсветка строго по центру (не дёргается).
          Center(
            child: Container(
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 31),
              decoration: BoxDecoration(
                color: colors.inverseSurface,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          // Плавное затухание строк к верхнему/нижнему краю (как у Apple-колеса).
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.28, 0.72, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListWheelScrollView.useDelegate(
              controller:
                  FixedExtentScrollController(initialItem: selectedIndex),
              itemExtent: itemExtent,
              // Плоское колесо (без 3D-цилиндра) — центральное время стоит
              // строго по центру и не «плавает» при скролле.
              diameterRatio: 100,
              perspective: 0.001,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (raw) {
                final i = raw % 96;
                HapticFeedback.selectionClick();
                SystemSound.play(SystemSoundType.click);
                setState(() => _scheduleStartMinutes = i * 15);
              },
              // Бесконечная прокрутка — время идёт по кругу.
              childDelegate: ListWheelChildLoopingListDelegate(
                children: List.generate(96, (i) {
                  final isSel = i * 15 == _scheduleStartMinutes;
                  final s = _formatHM(i * 15);
                  return Center(
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        color: isSel
                            ? colors.onInverseSurface
                            : colors.textSecondary,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Подробное колесо времени: начало (ч·мин) → конец (ч·мин), шаг 1 минута.
  Widget _buildDetailedTimeWheel(AppColors colors) {
    final startTotal = _scheduleStartMinutes;
    final endTotal = (_scheduleStartMinutes + _durationMinutes) % (24 * 60);
    final startH = startTotal ~/ 60;
    final startM = startTotal % 60;
    final endH = endTotal ~/ 60;
    final endM = endTotal % 60;
    return Container(
      height: 268,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _blockBg(colors),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Stack(
        children: [
          // Неподвижная пилюля-подсветка строго по центру.
          Center(
            child: Container(
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colors.inverseSurface,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          // Статичная стрелка «начало → конец» по центру.
          Center(
            child: Icon(
              CupertinoIcons.arrow_right,
              size: 18,
              color: colors.onInverseSurface,
            ),
          ),
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.28, 0.72, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Row(
              children: [
                Expanded(
                  child: _numberWheel(
                    colors,
                    controller: _detStartHourCtrl,
                    count: 24,
                    value: startH,
                    pad2: false,
                    onChanged: (h) => _applyDetailStart(h * 60 + startM),
                  ),
                ),
                Expanded(
                  child: _numberWheel(
                    colors,
                    controller: _detStartMinCtrl,
                    count: 60,
                    value: startM,
                    pad2: true,
                    onChanged: (m) => _applyDetailStart(startH * 60 + m),
                  ),
                ),
                const SizedBox(width: 40),
                Expanded(
                  child: _numberWheel(
                    colors,
                    controller: _detEndHourCtrl,
                    count: 24,
                    value: endH,
                    pad2: false,
                    onChanged: (h) => _applyDetailEnd(h * 60 + endM),
                  ),
                ),
                Expanded(
                  child: _numberWheel(
                    colors,
                    controller: _detEndMinCtrl,
                    count: 60,
                    value: endM,
                    pad2: true,
                    onChanged: (m) => _applyDetailEnd(endH * 60 + m),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Одна колонка чисел (часы/минуты) для подробного колеса.
  Widget _numberWheel(
    AppColors colors, {
    required FixedExtentScrollController controller,
    required int count,
    required int value,
    required bool pad2,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      diameterRatio: 100,
      perspective: 0.001,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (raw) {
        final i = ((raw % count) + count) % count;
        HapticFeedback.selectionClick();
        SystemSound.play(SystemSoundType.click);
        onChanged(i);
      },
      childDelegate: ListWheelChildLoopingListDelegate(
        children: List.generate(count, (i) {
          final isSel = i == value;
          return Center(
            child: Text(
              pad2 ? i.toString().padLeft(2, '0') : i.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                color: isSel ? colors.onInverseSurface : colors.textSecondary,
              ),
            ),
          );
        }),
      ),
    );
  }

  // Изменение начала: конец фиксирован, пересчитываем длительность.
  void _applyDetailStart(int startTotal) {
    startTotal = startTotal.clamp(0, 24 * 60 - 1);
    final endClock = (_scheduleStartMinutes + _durationMinutes) % (24 * 60);
    int dur = (endClock - startTotal) % (24 * 60);
    if (dur <= 0) dur += 24 * 60;
    setState(() {
      _scheduleStartMinutes = startTotal;
      _durationMinutes = dur;
    });
  }

  // Изменение конца: начало фиксировано, пересчитываем длительность.
  void _applyDetailEnd(int endClock) {
    endClock = endClock.clamp(0, 24 * 60 - 1);
    int dur = (endClock - _scheduleStartMinutes) % (24 * 60);
    if (dur <= 0) dur += 24 * 60;
    setState(() => _durationMinutes = dur);
  }

  // Выбор длительности (шага) — горизонтальные пилюли с плавно скользящим
  // активным овалом.
  Widget _buildDurationPicker(AppColors colors) {
    // Активные пилюли равномерно растянуты на всю ширину блока.
    return Container(
      height: 59,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _blockBg(colors),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: _durationOptions.map((min) {
          final selected = min == _durationMinutes;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _durationMinutes = min);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        selected ? colors.inverseSurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    _durationPillLabel(min, selected),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? colors.onInverseSurface
                          : colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Сохранить активные и запасные шаблоны длительности в prefs.
  void _persistDurationOptions() {
    SharedPreferences.getInstance().then((p) {
      p.setStringList(_durationOptionsPrefKey,
          _durationOptions.map((e) => e.toString()).toList());
      p.setStringList(_inactiveDurationsPrefKey,
          _inactiveDurations.map((e) => e.toString()).toList());
    });
  }

  // Шторка настройки продолжительности: колесо (ч/мин) + редактируемые шаблоны.
  // Закрытие крестиком фиксирует выбранное на колесе значение как новый шаблон.
  Future<void> _openDurationSheet() async {
    HapticFeedback.lightImpact();
    int hours = _durationMinutes ~/ 60;
    int minutes = _durationMinutes % 60;
    final hourCtrl = FixedExtentScrollController(initialItem: hours);
    final minCtrl = FixedExtentScrollController(initialItem: minutes);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = AppColors.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // Кнопка «Добавить»: добавляет значение колеса в запас.
            // Если активных < 5 — сразу в активные (и выбирается), иначе в
            // неактивные (запас), пока всего < 8.
            void addDuration() {
              final total = hours * 60 + minutes;
              if (total <= 0) return;
              if (_durationOptions.contains(total)) {
                setState(() => _durationMinutes = total);
                setSheet(() {});
                return;
              }
              if (_inactiveDurations.contains(total)) {
                HapticFeedback.heavyImpact();
                _showMessage(tr('Эта продолжительность уже есть'));
                return;
              }
              if (_durationOptions.length < _maxDurationOptions) {
                setState(() {
                  _durationOptions = [..._durationOptions, total];
                  _durationMinutes = total;
                  _persistDurationOptions();
                });
                setSheet(() {});
                HapticFeedback.lightImpact();
              } else if (_durationOptions.length + _inactiveDurations.length <
                  _maxDurationPool) {
                setState(() {
                  _inactiveDurations = [..._inactiveDurations, total];
                  _persistDurationOptions();
                });
                setSheet(() {});
                HapticFeedback.lightImpact();
              } else {
                HapticFeedback.heavyImpact();
                _showMessage(tr('Достигнут максимум продолжительностей'));
              }
            }

            // × у активного — убрать из показа (в запас).
            void deactivate(int min) {
              HapticFeedback.lightImpact();
              setState(() {
                _durationOptions =
                    _durationOptions.where((e) => e != min).toList();
                if (!_inactiveDurations.contains(min)) {
                  _inactiveDurations = [..._inactiveDurations, min];
                }
                _persistDurationOptions();
              });
              setSheet(() {});
            }

            // + у неактивного — показать (сделать активным), если есть место.
            void activate(int min) {
              if (_durationOptions.length >= _maxDurationOptions) {
                HapticFeedback.heavyImpact();
                _showMessage(tr('Удалите один из активных, чтобы добавить'));
                return;
              }
              HapticFeedback.lightImpact();
              setState(() {
                _inactiveDurations =
                    _inactiveDurations.where((e) => e != min).toList();
                if (!_durationOptions.contains(min)) {
                  _durationOptions = [..._durationOptions, min];
                }
                _persistDurationOptions();
              });
              setSheet(() {});
            }

            return ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.isDark
                        ? colors.surface.withValues(alpha: 0.92)
                        : colors.surface,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 12,
                    bottom: MediaQuery.of(ctx).padding.bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.divider,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            tr('Продолжительность'),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              Navigator.of(ctx).pop();
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.surfaceVariant,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(CupertinoIcons.xmark,
                                  size: 16, color: colors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildDurationSheetWheel(
                        colors,
                        hourCtrl: hourCtrl,
                        minCtrl: minCtrl,
                        hours: hours,
                        minutes: minutes,
                        onHours: (h) => setSheet(() => hours = h),
                        onMinutes: (m) => setSheet(() => minutes = m),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            tr('Шаблоны'),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _durationOptions =
                                    List<int>.from(_defaultDurationOptions);
                                _inactiveDurations = [];
                                _persistDurationOptions();
                              });
                              setSheet(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: colors.surfaceVariant,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(CupertinoIcons.arrow_counterclockwise,
                                      size: 14, color: colors.textSecondary),
                                  const SizedBox(width: 5),
                                  Text(
                                    tr('Сбросить'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          // Активные (отображаются в блоке) — с крестиком.
                          ..._durationOptions.map((min) {
                            return Container(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 10, 10, 10),
                              decoration: BoxDecoration(
                                color: colors.surfaceVariant,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _durationLabel(min),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => deactivate(min),
                                    child: Icon(CupertinoIcons.xmark,
                                        size: 15, color: colors.textTertiary),
                                  ),
                                ],
                              ),
                            );
                          }),
                          // Неактивные (запас) — с плюсом, приглушённые.
                          ..._inactiveDurations.map((min) {
                            return Container(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 10, 10, 10),
                              decoration: BoxDecoration(
                                color: colors.surfaceVariant
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _durationLabel(min),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => activate(min),
                                    child: Icon(CupertinoIcons.plus,
                                        size: 15, color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: addDuration,
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.inverseSurface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            tr('Добавить'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colors.onInverseSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    hourCtrl.dispose();
    minCtrl.dispose();
  }

  // Колесо выбора кастомной продолжительности (часы · минуты) в шторке.
  Widget _buildDurationSheetWheel(
    AppColors colors, {
    required FixedExtentScrollController hourCtrl,
    required FixedExtentScrollController minCtrl,
    required int hours,
    required int minutes,
    required ValueChanged<int> onHours,
    required ValueChanged<int> onMinutes,
  }) {
    return Container(
      height: 220,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _blockBg(colors),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colors.inverseSurface,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.28, 0.72, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Row(
              children: [
                Expanded(
                  child: _durationUnitWheel(
                    colors,
                    controller: hourCtrl,
                    count: 24,
                    value: hours,
                    unit: tr('час.'),
                    onChanged: onHours,
                  ),
                ),
                Expanded(
                  child: _durationUnitWheel(
                    colors,
                    controller: minCtrl,
                    count: 60,
                    value: minutes,
                    unit: tr('мин.'),
                    onChanged: onMinutes,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Колонка чисел с подписью единицы (час./мин.) справа от выбранного.
  Widget _durationUnitWheel(
    AppColors colors, {
    required FixedExtentScrollController controller,
    required int count,
    required int value,
    required String unit,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      diameterRatio: 100,
      perspective: 0.001,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (raw) {
        final i = ((raw % count) + count) % count;
        HapticFeedback.selectionClick();
        SystemSound.play(SystemSoundType.click);
        onChanged(i);
      },
      childDelegate: ListWheelChildLoopingListDelegate(
        children: List.generate(count, (i) {
          final isSel = i == value;
          return Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  i.toString(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                    color:
                        isSel ? colors.onInverseSurface : colors.textSecondary,
                  ),
                ),
                if (isSel) ...[
                  const SizedBox(width: 8),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.onInverseSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  /// Крестик закрытия вверху справа. По тапу карточка-подтверждение «Точно
  /// хочешь отменить эти изменения?» (с красной кнопкой «Отменить изменения»)
  /// появляется СРАЗУ ПОЛНОСТЬЮ, плавно проявляясь (fade + лёгкий scale).
  Widget _buildCancelButton(AppColors colors) {
    const red = Color(0xFFFF3B30);
    return AnimatedBuilder(
      animation: _cancelController,
      builder: (context, _) {
        final v = Curves.easeOutCubic.transform(_cancelController.value);
        final open = _cancelController.value > 0.001;
        // Крестик (свёрнутое состояние) — тёмный круг с белым xmark.
        // В режиме просмотра события и при РЕДАКТИРОВАНИИ существующей
        // задачи/привычки/события (вход по лонгпрессу) закрывает шторку
        // без подтверждения. Подтверждение — только при создании с нуля.
        final bool closeDirectly = _eventView ||
            widget.isEdit ||
            widget.initialHabit != null ||
            widget.initialEvent != null;
        final collapsed = GestureDetector(
          onTap: closeDirectly ? _handleClose : _openCancelConfirm,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.border.withValues(alpha: 0.6),
                width: 0.5,
              ),
            ),
            child: const Icon(
              CupertinoIcons.xmark,
              size: 18,
              color: Colors.white,
            ),
          ),
        );
        // Полная карточка-подтверждение — появляется целиком (fade + scale).
        final card = Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: ui.lerpDouble(0.92, 1.0, v)!,
            alignment: Alignment.topRight,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: colors.border.withValues(alpha: 0.6),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 220,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr('Точно хочешь отменить эти изменения?'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _handleClose,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: red.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            tr('Отменить изменения'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: red,
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
        );
        // Карточка раскрывается «из» крестика (оба прижаты к верхнему-правому
        // углу), крестик ловит тап только когда полностью свёрнут.
        return Stack(
          alignment: Alignment.topRight,
          children: [
            IgnorePointer(ignoring: open, child: collapsed),
            if (open) card,
          ],
        );
      },
    );
  }

  /// Широкий овал-капсула слева от названия/описания задачи. Заливка —
  /// выбранным цветом (персиковый по умолчанию), без рамки, по центру белая
  /// иконка. Тап открывает шторку «Цвет и иконка».
  Widget _buildTaskIconOval(AppColors colors) {
    final accent = Color(_taskColors[_taskColorIndex]);
    final icon = _taskIcons[_taskIconIndex];
    return GestureDetector(
      onTap: _openColorIconSheet,
      child: Container(
        width: 65,
        height: 118,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Center(
          child: Icon(icon, color: Colors.white, size: 34),
        ),
      ),
    );
  }

  /// Шторка выбора цвета и иконки задачи (снизу вверх).
  void _openColorIconSheet() {
    final colors = AppColors.of(context);
    FocusScope.of(context).unfocus();
    setState(() => _colorSheetOpen = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Плавное появление/скрытие шторки.
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 440),
        reverseDuration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void pick(VoidCallback fn) {
              HapticFeedback.selectionClick();
              setSheetState(fn);
              setState(() {});
            }

            // Стекло (liquid glass): скруглённая шапка + размытие фона +
            // полупрозрачная заливка с тонким бликом по верхнему краю.
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.isDark
                        ? colors.surface.withValues(alpha: 0.72)
                        : Colors.white.withValues(alpha: 0.78),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(
                          alpha: colors.isDark ? 0.18 : 0.6,
                        ),
                        width: 1,
                      ),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    24 + MediaQuery.of(sheetContext).padding.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(
                            tr('Цвет и иконка'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          // Крестик в стиле liquid glass (frosted) — без
                          // LiquidGlass-шейдера, чтобы не было чёрного артефакта.
                          GestureDetector(
                            onTap: () => Navigator.of(sheetContext).pop(),
                            behavior: HitTestBehavior.opaque,
                            child: ClipOval(
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 12,
                                  sigmaY: 12,
                                ),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colors.isDark
                                        ? Colors.white.withValues(alpha: 0.16)
                                        : Colors.black.withValues(alpha: 0.05),
                                    border: Border.all(
                                      color: colors.isDark
                                          ? Colors.white.withValues(alpha: 0.22)
                                          : Colors.black.withValues(alpha: 0.08),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.xmark,
                                    size: 14,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      // Цвета — горизонтальный ряд кружков.
                      SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _taskColors.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemBuilder: (_, i) {
                            final c = Color(_taskColors[i]);
                            final selected = i == _taskColorIndex;
                            return GestureDetector(
                              onTap: () => pick(() => _taskColorIndex = i),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? colors.textPrimary
                                        : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        CupertinoIcons.check_mark,
                                        color: Colors.white,
                                        size: 22,
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 40),
                      // Иконки — равномерная сетка на всю ширину (GridView вместо
                      // Wrap, чтобы колонки распределялись ровно и одинаково на
                      // любом размере экрана, без «съезжания» влево).
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 5,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        children: List.generate(_taskIcons.length, (i) {
                          final selected = i == _taskIconIndex;
                          final accent = Color(_taskColors[_taskColorIndex]);
                          return GestureDetector(
                            onTap: () => pick(() => _taskIconIndex = i),
                            child: Container(
                              decoration: BoxDecoration(
                                color: selected
                                    ? accent.withValues(alpha: 0.16)
                                    : colors.surfaceVariant
                                        .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected ? accent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                _taskIcons[i],
                                color:
                                    selected ? accent : colors.textSecondary,
                                size: 24,
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _colorSheetOpen = false);
    });
  }

  Widget _buildOvalChip({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Чипы события =====

  // Повтор: тап переключает «Один раз» ↔ «Каждый год».
  Widget _buildEventRepeatChip() {
    return _buildOvalChip(
      icon: _eventRepeatYearly ? Icons.event_repeat : Icons.event_outlined,
      text: tr(_eventRepeatYearly ? 'Каждый год' : 'Один раз'),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _eventRepeatYearly = !_eventRepeatYearly);
      },
    );
  }

  // Уведомление: тап циклит состояния
  // Без уведомления → За 1 день → В день → За 1 день и в день → ...
  Widget _buildEventNotifyChip() {
    final String label;
    if (_eventNotifyDayBefore && _eventNotifyOnDay) {
      label = 'За 1 день и в день';
    } else if (_eventNotifyDayBefore) {
      label = 'За 1 день';
    } else if (_eventNotifyOnDay) {
      label = 'В день';
    } else {
      label = 'Без уведомления';
    }
    final active = _eventNotifyDayBefore || _eventNotifyOnDay;
    return _buildOvalChip(
      icon: active ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
      text: tr(label),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          // 0:none → 1:before → 2:onDay → 3:both → 0
          final state = (_eventNotifyDayBefore ? 1 : 0) + (_eventNotifyOnDay ? 2 : 0);
          final next = (state + 1) % 4;
          _eventNotifyDayBefore = next == 1 || next == 3;
          _eventNotifyOnDay = next == 2 || next == 3;
        });
      },
    );
  }

  // Картинка из галереи.
  Widget _buildEventImageChip() {
    final has = _eventImagePath != null;
    return _buildOvalChip(
      icon: has ? Icons.image : Icons.add_photo_alternate_outlined,
      text: tr('Картинка'),
      onTap: _pickEventImage,
    );
  }

  Future<void> _pickEventImage() async {
    try {
      FocusScope.of(context).unfocus();
      HapticFeedback.mediumImpact();
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;

      // Готовим исходный файл для кадрирования.
      File source;
      if (picked.path != null) {
        source = File(picked.path!);
      } else if (picked.bytes != null) {
        // Картинка пришла байтами — кладём во временный файл.
        final tmpDir = await getTemporaryDirectory();
        final ext = path.extension(picked.name);
        source = File(path.join(tmpDir.path,
            'pick_${DateTime.now().millisecondsSinceEpoch}$ext'));
        await source.writeAsBytes(picked.bytes!);
      } else {
        return;
      }

      if (!mounted) return;
      // Apple-style выбор области картинки под баннер. Возвращает относительный
      // путь к обрезанной картинке (или null, если отменили).
      final relativePath = await showEventImageCropper(context, source: source);
      if (relativePath != null && mounted) {
        setState(() => _eventImagePath = relativePath);
      }
    } catch (e) {
      if (mounted) _showMessage(tr('Не удалось выбрать картинку: {0}', [e]));
    }
  }

  Widget _buildPriorityChip() {
    final colors = AppColors.of(context);
    final priorityColor = _getPriorityColor();
    final iconPath = _getPriorityIconPath();

    return GestureDetector(
      onTap: _togglePriority,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
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
                      colors.textSecondary,
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
                color: _selectedPriority > 0 ? priorityColor : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepeatChip() {
    final colors = AppColors.of(context);
    final active = _repeatMode != 'Не повторять';
    return GestureDetector(
      key: _repeatChipKey,
      onTap: _showRepeatMenu,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: active
              ? Border(left: BorderSide(color: colors.textPrimary, width: 4))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.repeat,
              size: 18,
              color: active ? colors.textPrimary : colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              active ? tr(_repeatMode) : tr('Повтор'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: active ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _removeRepeatMenu() {
    _repeatMenuOverlay?.remove();
    _repeatMenuOverlay = null;
  }

  void _removeTimeMenu() {
    _timeMenuOverlay?.remove();
    _timeMenuOverlay = null;
  }

  // Меню-троеточие у секции «Время»: раскрывается ВНИЗ из кнопки.
  void _showTimeMenu() {
    HapticFeedback.lightImpact();
    _removeTimeMenu();
    final overlay = Overlay.of(context);
    final renderBox =
        _timeMenuKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPosition = renderBox.localToGlobal(Offset.zero);
    final anchorSize = renderBox.size;
    const menuWidth = 250.0;
    final screenSize = MediaQuery.of(context).size;
    double right = screenSize.width - (anchorPosition.dx + anchorSize.width);
    if (right < 12) right = 12;
    // Раскрытие вниз — отсчёт сверху от нижней грани кнопки.
    final top = anchorPosition.dy + anchorSize.height + 6;
    _timeMenuOverlay = OverlayEntry(
      builder: (context) => _TimeOptionsMenu(
        right: right,
        top: top,
        width: menuWidth,
        detailedSelected: _detailedTime,
        onChangeDate: () {
          _removeTimeMenu();
          _openCalendar();
        },
        onAllDay: () {
          _removeTimeMenu();
          setState(() => _allDay = true);
        },
        onPickStandard: () {
          _removeTimeMenu();
          _setDetailedTime(false);
        },
        onPickDetailed: () {
          _removeTimeMenu();
          _setDetailedTime(true);
        },
        onClose: _removeTimeMenu,
      ),
    );
    overlay.insert(_timeMenuOverlay!);
  }

  // Применить и запомнить выбор типа времени.
  void _setDetailedTime(bool detailed) {
    setState(() {
      _detailedTime = detailed;
      _allDay = false;
    });
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_detailedTimePrefKey, detailed));
  }

  // Стеклянное выпадающее меню повтора (стиль iOS 26, как пикеры в настройках).
  // Открывается ВВЕРХ над чипом, т.к. шторка прижата к низу экрана.
  void _showRepeatMenu() {
    HapticFeedback.lightImpact();
    _removeRepeatMenu();
    final overlay = Overlay.of(context);
    final renderBox = _repeatChipKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPosition = renderBox.localToGlobal(Offset.zero);
    const menuWidth = 200.0;
    final screenSize = MediaQuery.of(context).size;
    double left = anchorPosition.dx;
    if (left + menuWidth > screenSize.width - 12) {
      left = screenSize.width - 12 - menuWidth;
    }
    if (left < 12) left = 12;
    // Клавиатуру НЕ сворачиваем (unfocus убран) — чип остаётся на месте,
    // позицию меряем как есть.
    final bottom = screenSize.height - (anchorPosition.dy - 6);

    const options = ['Не повторять', 'Каждый день', 'По будням', 'Каждую неделю'];
    _repeatMenuOverlay = OverlayEntry(
      builder: (context) => _RepeatGlassMenu(
        left: left,
        bottom: bottom,
        width: menuWidth,
        options: options,
        currentValue: _repeatMode,
        onSelected: (v) {
          _removeRepeatMenu();
          setState(() => _repeatMode = v);
        },
        onClose: _removeRepeatMenu,
      ),
    );
    overlay.insert(_repeatMenuOverlay!);
  }

  // ===== Режим привычки =====

  // Сегментированный переключатель «Задача / Привычка» (стиль iOS).
  Widget _buildModeToggle() {
    // Нативный iOS 26 Liquid Glass UISegmentedControl (на старых ОС/других
    // платформах — адаптивный фолбэк пакета adaptive_platform_ui).
    // Полноширинный SizedBox, чтобы контрол растянулся на всю ширину и сегменты
    // «Задача»/«Привычка» получили одинаковую ширину.
    // Сегменты зависят от того, какие колбэки переданы: всегда есть «Задача»,
    // «Привычка» — если onSaveHabit, «Событие» — если onSaveEvent.
    final labels = <String>[tr('Задача')];
    final modes = <int>[0]; // 0 = задача, 1 = привычка, 2 = событие
    if (widget.onSaveHabit != null) {
      labels.add(tr('Привычка'));
      modes.add(1);
    }
    if (widget.onSaveEvent != null) {
      labels.add(tr('Событие'));
      modes.add(2);
    }
    final currentMode = _isEvent ? 2 : (_isHabit ? 1 : 0);
    final selectedIndex = modes.indexOf(currentMode).clamp(0, modes.length - 1);
    return SizedBox(
      width: double.infinity,
      child: AdaptiveSegmentedControl(
        labels: labels,
        selectedIndex: selectedIndex,
        onValueChanged: (i) {
          final mode = modes[i];
          if (mode != currentMode) {
            HapticFeedback.selectionClick();
            setState(() {
              _isHabit = mode == 1;
              _isEvent = mode == 2;
            });
          }
        },
      ),
    );
  }

  String _scheduleLabel(int mask) {
    switch (mask) {
      case Habit.maskDaily:
        return 'Каждый день';
      case Habit.maskWeekdays:
        return 'По будням';
      case Habit.maskWeekends:
        return 'Выходные';
      default:
        return 'Свой график';
    }
  }

  Widget _buildScheduleChip() {
    final colors = AppColors.of(context);
    return GestureDetector(
      key: _scheduleChipKey,
      onTap: _showScheduleMenu,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border(left: BorderSide(color: colors.textPrimary, width: 4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat, size: 18, color: colors.textPrimary),
            const SizedBox(width: 8),
            Text(
              tr(_scheduleLabel(_habitMask)),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showScheduleMenu() {
    HapticFeedback.lightImpact();
    _scheduleMenuOverlay?.remove();
    _scheduleMenuOverlay = null;
    final overlay = Overlay.of(context);
    final renderBox =
        _scheduleChipKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPosition = renderBox.localToGlobal(Offset.zero);
    const menuWidth = 200.0;
    final screenSize = MediaQuery.of(context).size;
    double left = anchorPosition.dx;
    if (left + menuWidth > screenSize.width - 12) {
      left = screenSize.width - 12 - menuWidth;
    }
    if (left < 12) left = 12;
    // Клавиатуру НЕ сворачиваем (unfocus убран) — чип остаётся на месте,
    // позицию меряем как есть.
    final bottom = screenSize.height - (anchorPosition.dy - 6);

    const options = ['Каждый день', 'По будням', 'Выходные'];
    _scheduleMenuOverlay = OverlayEntry(
      builder: (context) => _RepeatGlassMenu(
        left: left,
        bottom: bottom,
        width: menuWidth,
        options: options,
        currentValue: _scheduleLabel(_habitMask),
        onSelected: (v) {
          _scheduleMenuOverlay?.remove();
          _scheduleMenuOverlay = null;
          setState(() {
            switch (v) {
              case 'По будням':
                _habitMask = Habit.maskWeekdays;
                break;
              case 'Выходные':
                _habitMask = Habit.maskWeekends;
                break;
              default:
                _habitMask = Habit.maskDaily;
            }
          });
        },
        onClose: () {
          _scheduleMenuOverlay?.remove();
          _scheduleMenuOverlay = null;
        },
      ),
    );
    overlay.insert(_scheduleMenuOverlay!);
  }

  // Подпись периода для овала: «Бессрочно», пресет или диапазон дат.
  String _periodLabel() {
    if (_habitEndDate == null) return tr('Бессрочно');
    final start = DateTime(
        _habitStartDate.year, _habitStartDate.month, _habitStartDate.day);
    final end = DateTime(
        _habitEndDate!.year, _habitEndDate!.month, _habitEndDate!.day);
    final days = end.difference(start).inDays + 1;
    switch (days) {
      case 21:
        return tr('21 день');
      case 30:
        return tr('30 дней');
      case 66:
        return tr('66 дней');
      default:
        return '${start.day} ${_getMonthName(start.month)} – '
            '${end.day} ${_getMonthName(end.month)}';
    }
  }

  Widget _buildPeriodChip() {
    final colors = AppColors.of(context);
    return GestureDetector(
      key: _periodChipKey,
      onTap: _showPeriodMenu,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border(left: BorderSide(color: colors.textPrimary, width: 4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_outlined, size: 18, color: colors.textPrimary),
            const SizedBox(width: 8),
            Text(
              _periodLabel(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPeriodMenu() {
    HapticFeedback.lightImpact();
    _periodMenuOverlay?.remove();
    _periodMenuOverlay = null;
    final overlay = Overlay.of(context);
    final renderBox =
        _periodChipKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPosition = renderBox.localToGlobal(Offset.zero);
    const menuWidth = 200.0;
    final screenSize = MediaQuery.of(context).size;
    double left = anchorPosition.dx;
    if (left + menuWidth > screenSize.width - 12) {
      left = screenSize.width - 12 - menuWidth;
    }
    if (left < 12) left = 12;
    // Клавиатуру НЕ сворачиваем (unfocus убран) — чип остаётся на месте,
    // позицию меряем как есть.
    final bottom = screenSize.height - (anchorPosition.dy - 6);

    const options = [
      'Бессрочно',
      '21 день',
      '30 дней',
      '66 дней',
      'Свой период',
    ];
    _periodMenuOverlay = OverlayEntry(
      builder: (context) => _RepeatGlassMenu(
        left: left,
        bottom: bottom,
        width: menuWidth,
        options: options,
        currentValue: _periodCurrentKey(),
        onSelected: (v) {
          _periodMenuOverlay?.remove();
          _periodMenuOverlay = null;
          _applyPeriodOption(v);
        },
        onClose: () {
          _periodMenuOverlay?.remove();
          _periodMenuOverlay = null;
        },
      ),
    );
    overlay.insert(_periodMenuOverlay!);
  }

  // Ключ текущего выбора для подсветки в меню.
  String _periodCurrentKey() {
    if (_habitEndDate == null) return 'Бессрочно';
    final start = DateTime(
        _habitStartDate.year, _habitStartDate.month, _habitStartDate.day);
    final end = DateTime(
        _habitEndDate!.year, _habitEndDate!.month, _habitEndDate!.day);
    final days = end.difference(start).inDays + 1;
    switch (days) {
      case 21:
        return '21 день';
      case 30:
        return '30 дней';
      case 66:
        return '66 дней';
      default:
        return 'Свой период';
    }
  }

  void _applyPeriodOption(String v) {
    if (v == 'Свой период') {
      _pickCustomPeriod();
      return;
    }
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    setState(() {
      switch (v) {
        case '21 день':
          _habitStartDate = start;
          _habitEndDate = start.add(const Duration(days: 20));
          break;
        case '30 дней':
          _habitStartDate = start;
          _habitEndDate = start.add(const Duration(days: 29));
          break;
        case '66 дней':
          _habitStartDate = start;
          _habitEndDate = start.add(const Duration(days: 65));
          break;
        default: // Бессрочно
          _habitStartDate = start;
          _habitEndDate = null;
      }
    });
  }

  Future<void> _pickCustomPeriod() async {
    final now = DateTime.now();
    final initialStart = DateTime(
        _habitStartDate.year, _habitStartDate.month, _habitStartDate.day);
    final initialEnd = _habitEndDate ?? initialStart.add(const Duration(days: 30));
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (range == null) return;
    setState(() {
      _habitStartDate =
          DateTime(range.start.year, range.start.month, range.start.day);
      _habitEndDate = DateTime(range.end.year, range.end.month, range.end.day);
    });
  }

  // Овал выбора цвета — по тапу переключает цвет по палитре (как приоритет).
  Widget _buildHabitColorChip() {
    final colors = AppColors.of(context);
    final color = Color(HabitPalette.colors[_habitColorIndex]);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _habitColorIndex =
              (_habitColorIndex + 1) % HabitPalette.colors.length;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tr('Цвет'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Овал выбора значка — по тапу переключает значок по списку.
  Widget _buildHabitIconChip() {
    final colors = AppColors.of(context);
    final color = Color(HabitPalette.colors[_habitColorIndex]);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _habitIconIndex = (_habitIconIndex + 1) % HabitPalette.icons.length;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HabitPalette.icons[_habitIconIndex], size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              tr('Значок'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
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
        _showMessage(tr('Ошибка при выборе файла: {0}', [e]));
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
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: _pickFiles,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.attach_file,
              size: 18,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              _attachedFiles.isEmpty ? tr('Прикрепить') : tr('Прикреплено ({0})', [_attachedFiles.length]),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsChip() {
    final colors = AppColors.of(context);
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
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tag,
              size: 18,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _tagsController,
                autofocus: true,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: tr('продукты'),
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: colors.textTertiary,
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
              child: Icon(
                Icons.check,
                size: 18,
                color: colors.textSecondary,
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
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tag,
              size: 18,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              tr('Хештеги'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Стеклянное выпадающее меню выбора режима повтора (стиль iOS 26, как пикеры
// темы/языка в настройках). Привязано к чипу повтора и раскрывается вверх.
class _RepeatGlassMenu extends StatefulWidget {
  final double left;
  final double bottom;
  final double width;
  final List<String> options;
  final String currentValue;
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;

  const _RepeatGlassMenu({
    required this.left,
    required this.bottom,
    required this.width,
    required this.options,
    required this.currentValue,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<_RepeatGlassMenu> createState() => _RepeatGlassMenuState();
}

class _RepeatGlassMenuState extends State<_RepeatGlassMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Защита от повторного закрытия (тап по фону + выбор пункта одновременно).
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        reverseCurve: Curves.easeIn,
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _animationController.forward();
  }

  // Плавное закрытие: проигрываем обратную анимацию, затем выполняем действие
  // (удаление overlay в родителе / применение выбора).
  void _close(VoidCallback then) {
    if (_closing) return;
    _closing = true;
    _animationController.reverse().whenComplete(then);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => _close(widget.onClose),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Positioned(
              left: widget.left,
              bottom: widget.bottom,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () {},
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      alignment: Alignment.bottomLeft,
                      // Меню раскрывается ВВЕРХ → тень должна быть только снизу.
                      // ClipRect с bottom-only клиппером режет всё, что выше
                      // верхней грани меню (y<0), поэтому размытый «хвост»
                      // gaussian-тени физически не может выйти за верх и
                      // запачкать верхние углы; по бокам/снизу тень остаётся.
                      child: ClipRect(
                        clipper: _ShadowBottomClipper(),
                        child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: colors.isDark
                              ? null
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.16),
                                    blurRadius: 16,
                                    spreadRadius: -10,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.isDark
                                  ? colors.surface.withValues(alpha: 0.72)
                                  : const Color(0xFFF6F7F8).withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: colors.isDark
                                    ? colors.border.withValues(alpha: 0.6)
                                    : const Color(0xFFD2D4D9),
                                width: colors.isDark ? 0.5 : 1,
                              ),
                            ),
                            child: SizedBox(
                              width: widget.width,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: widget.options.map((option) {
                                  final isSelected = option == widget.currentValue;
                                  return InkWell(
                                    onTap: () =>
                                        _close(() => widget.onSelected(option)),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              tr(option),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                                color: colors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          if (isSelected)
                                            Icon(
                                              CupertinoIcons.check_mark,
                                              size: 16,
                                              color: colors.textPrimary,
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      ),
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
}

// Меню-троеточие секции «Время»: раскрывается ВНИЗ из кнопки.
// Главная страница (Изменить дату / На весь день / Выбор времени ›) и
// подстраница выбора типа времени (Стандартный / Подробно) с плавным
// горизонтальным переходом между ними.
class _TimeOptionsMenu extends StatefulWidget {
  final double right;
  final double top;
  final double width;
  final bool detailedSelected;
  final VoidCallback onChangeDate;
  final VoidCallback onAllDay;
  final VoidCallback onPickStandard;
  final VoidCallback onPickDetailed;
  final VoidCallback onClose;

  const _TimeOptionsMenu({
    required this.right,
    required this.top,
    required this.width,
    required this.detailedSelected,
    required this.onChangeDate,
    required this.onAllDay,
    required this.onPickStandard,
    required this.onPickDetailed,
    required this.onClose,
  });

  @override
  State<_TimeOptionsMenu> createState() => _TimeOptionsMenuState();
}

class _TimeOptionsMenuState extends State<_TimeOptionsMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _closing = false;
  // 0 — главная страница, 1 — подстраница «Выбор времени».
  int _page = 0;

  static const Color _iconColor = Color(0xFFFFB59A);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        reverseCurve: Curves.easeIn,
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _animationController.forward();
  }

  void _close(VoidCallback then) {
    if (_closing) return;
    _closing = true;
    _animationController.reverse().whenComplete(then);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Widget _item(
    AppColors colors, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool chevron = false,
    bool check = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                tr(label),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (chevron)
              Icon(CupertinoIcons.chevron_right,
                  size: 15, color: colors.textTertiary),
            if (check)
              Icon(CupertinoIcons.check_mark,
                  size: 16, color: colors.textPrimary),
          ],
        ),
      ),
    );
  }

  Widget _divider(AppColors colors) => Container(
        height: 0.5,
        color: colors.divider,
      );

  Widget _mainPage(AppColors colors) {
    return Column(
      key: const ValueKey('main'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _item(
          colors,
          icon: CupertinoIcons.calendar,
          label: 'Изменить дату',
          onTap: () => _close(widget.onChangeDate),
        ),
        _divider(colors),
        _item(
          colors,
          icon: CupertinoIcons.clock,
          label: 'Назначить на весь день',
          onTap: () => _close(widget.onAllDay),
        ),
        _divider(colors),
        _item(
          colors,
          icon: CupertinoIcons.time,
          label: 'Выбор времени',
          chevron: true,
          onTap: () => setState(() => _page = 1),
        ),
      ],
    );
  }

  Widget _timePage(AppColors colors) {
    return Column(
      key: const ValueKey('time'),
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _page = 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: [
                Icon(CupertinoIcons.chevron_left,
                    size: 16, color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  tr('Выбор времени'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        _divider(colors),
        _item(
          colors,
          icon: CupertinoIcons.list_bullet,
          label: 'Стандартный',
          check: !widget.detailedSelected,
          onTap: () => _close(widget.onPickStandard),
        ),
        _divider(colors),
        _item(
          colors,
          icon: CupertinoIcons.square_list,
          label: 'Подробно',
          check: widget.detailedSelected,
          onTap: () => _close(widget.onPickDetailed),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => _close(widget.onClose),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Positioned(
              right: widget.right,
              top: widget.top,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () {},
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      alignment: Alignment.topRight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: colors.isDark ? 0.4 : 0.16),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: BackdropFilter(
                            filter:
                                ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.isDark
                                    ? colors.surface.withValues(alpha: 0.82)
                                    : const Color(0xFFF6F7F8)
                                        .withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: colors.isDark
                                      ? colors.border.withValues(alpha: 0.6)
                                      : const Color(0xFFD2D4D9),
                                  width: colors.isDark ? 0.5 : 1,
                                ),
                              ),
                              child: SizedBox(
                                width: widget.width,
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 220),
                                    transitionBuilder: (child, anim) {
                                      final isMain =
                                          child.key == const ValueKey('main');
                                      final begin = Offset(
                                          isMain ? -0.18 : 0.18, 0);
                                      return FadeTransition(
                                        opacity: anim,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: begin,
                                            end: Offset.zero,
                                          ).animate(CurvedAnimation(
                                            parent: anim,
                                            curve: Curves.easeOutCubic,
                                          )),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: _page == 0
                                        ? _mainPage(colors)
                                        : _timePage(colors),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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
}

// Клиппер тени для меню, раскрывающегося вверх: оставляет область строго от
// верхней грани меню (y=0) и ниже, расширяя по бокам/снизу, чтобы размытый
// «хвост» boxShadow был виден только снизу/по бокам, но никогда не выходил
// за верхний край (иначе тень пачкала верхние углы).
class _ShadowBottomClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-40, 0, size.width + 40, size.height + 40);

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) => false;
}
