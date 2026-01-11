import 'package:flutter/material.dart';
import '../models/note_model.dart';
import '../models/task.dart';
import '../models/goal_model.dart';
import '../data/database_instance.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/note_repository.dart';
import '../data/user_session.dart';

class NoteCreateModal extends StatefulWidget {
  final VoidCallback onClose;
  final Function(NoteModel) onSave;
  final Function(String title, String color, String? icon, String? linkedElementType, String? linkedElementId) onAttach; // Колбэк для прикрепления заметки к списку

  const NoteCreateModal({
    super.key,
    required this.onClose,
    required this.onSave,
    required this.onAttach,
  });

  @override
  State<NoteCreateModal> createState() => _NoteCreateModalState();
}

class _NoteCreateModalState extends State<NoteCreateModal> with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  
  // Состояние формы
  String _selectedColor = '#FFEB3B';
  String? _selectedIcon;
  String? _linkedElementId;
  String? _linkedElementType; // 'task', 'goal', 'note'
  bool _isLinkDropdownOpen = false;
  bool _isIconPickerOpen = false;
  
  // Данные для списка связей
  List<Task> _tasks = [];
  List<GoalModel> _goals = [];
  List<NoteModel> _notes = [];
  bool _isLoadingLinks = false;
  
  late TaskRepository _taskRepository;
  late PlanRepository _planRepository;
  late NoteRepository _noteRepository;

  @override
  void initState() {
    super.initState();
    _taskRepository = TaskRepository(appDatabase);
    _planRepository = PlanRepository(appDatabase);
    _noteRepository = NoteRepository(appDatabase);
    
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
    _loadLinks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    setState(() {
      _isLoadingLinks = true;
    });
    
    final userId = UserSession.currentUserId;
    if (userId == null) {
      setState(() {
        _isLoadingLinks = false;
      });
      return;
    }
    
    try {
      // Загружаем все задачи (незавершенные)
      final allTasks = await _taskRepository.searchAllTasks();
      final activeTasks = allTasks.where((task) => !task.isCompleted).toList();
      
      // Загружаем цели
      final goals = await _planRepository.loadGoals(userId);
      
      // Загружаем заметки
      final notes = await _noteRepository.loadNotes(userId);
      
      if (mounted) {
        setState(() {
          _tasks = activeTasks;
          _goals = goals;
          _notes = notes;
          _isLoadingLinks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLinks = false;
        });
      }
    }
  }

  void _handleClose() {
    _animationController.reverse().then((_) {
      widget.onClose();
    });
  }

  Color _getColorFromHex(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFFFFEB3B);
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
                      // Индикатор перетаскивания
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E5E5),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      // Заголовок
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Новая заметка',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            GestureDetector(
                              onTap: _handleClose,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Color(0xFF666666),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE5E5E5)),
                      // Форма
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Блок "Связать с элементом"
                              _buildLinkElementBlock(),
                              const SizedBox(height: 24),
                              // Выбор цвета (14 цветов)
                              _buildColorPicker(),
                              const SizedBox(height: 32),
                              // Блок с иконкой и названием
                              _buildIconAndTitleBlock(),
                              const SizedBox(height: 24),
                              // Инструменты
                              _buildToolsBlock(),
                              SizedBox(height: _isLinkDropdownOpen ? 32 : 24),
                              // Кнопка "Прикрепить"
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    widget.onAttach(
                                      _titleController.text.trim(),
                                      _selectedColor,
                                      _selectedIcon,
                                      _linkedElementType,
                                      _linkedElementId,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Прикрепить',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
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

  Widget _buildLinkElementBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _isLinkDropdownOpen = !_isLinkDropdownOpen;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E5E5)),
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _linkedElementType == null
                        ? 'Связать с элементом'
                        : _getLinkedElementTitle(),
                    style: TextStyle(
                      fontSize: 16,
                      color: _linkedElementType == null
                          ? const Color(0xFF999999)
                          : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _isLinkDropdownOpen ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF999999),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: _isLinkDropdownOpen
              ? Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E5E5)),
                      ),
                      child: _isLoadingLinks
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _tasks.isEmpty && _goals.isEmpty && _notes.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Center(
                                    child: Text(
                                      'Нет элементов для связи',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF999999),
                                      ),
                                    ),
                                  ),
                                )
                              : ListView(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  children: [
                                    // Задачи
                                    if (_tasks.isNotEmpty) ...[
                                      _buildLinkSectionHeader('Задачи'),
                                      ..._tasks.map((task) => _buildLinkItem(
                                            title: task.title,
                                            type: 'task',
                                            id: task.id,
                                          )),
                                    ],
                                    // Цели
                                    if (_goals.isNotEmpty) ...[
                                      _buildLinkSectionHeader('Цели'),
                                      ..._goals.map((goal) => _buildLinkItem(
                                            title: goal.title,
                                            type: 'goal',
                                            id: goal.dbId?.toString(),
                                          )),
                                    ],
                                    // Заметки
                                    if (_notes.isNotEmpty) ...[
                                      _buildLinkSectionHeader('Заметки'),
                                      ..._notes.map((note) => _buildLinkItem(
                                            title: note.title,
                                            type: 'note',
                                            id: note.id?.toString(),
                                          )),
                                    ],
                                  ],
                                ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildLinkSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF666666),
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _buildLinkItem({required String title, required String type, String? id}) {
    final isSelected = _linkedElementType == type && _linkedElementId == id;
    return InkWell(
      onTap: () {
        setState(() {
          _linkedElementType = type;
          _linkedElementId = id;
          _isLinkDropdownOpen = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isSelected ? const Color(0xFFF5F5F5) : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check,
                size: 18,
                color: Color(0xFF007AFF),
              ),
          ],
        ),
      ),
    );
  }

  String _getLinkedElementTitle() {
    if (_linkedElementType == 'task') {
      final task = _tasks.firstWhere((t) => t.id == _linkedElementId, orElse: () => _tasks.first);
      return task.title;
    } else if (_linkedElementType == 'goal') {
      final goal = _goals.firstWhere((g) => g.dbId?.toString() == _linkedElementId, orElse: () => _goals.first);
      return goal.title;
    } else if (_linkedElementType == 'note') {
      final note = _notes.firstWhere((n) => n.id?.toString() == _linkedElementId, orElse: () => _notes.first);
      return note.title;
    }
    return '';
  }

  Widget _buildColorPicker() {
    final colors = [
      '#FFEB3B', '#FF9800', '#F44336', '#E91E63',
      '#9C27B0', '#673AB7', '#3F51B5', '#2196F3',
      '#03A9F4', '#00BCD4', '#009688', '#4CAF50',
      '#8BC34A', '#CDDC39',
    ]; // 14 цветов

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Цвет',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF666666),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.map((color) {
            final isSelected = _selectedColor == color;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedColor = color;
                });
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _getColorFromHex(color),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildIconAndTitleBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Блок выбора иконки
            GestureDetector(
              onTap: () {
                setState(() {
                  _isIconPickerOpen = !_isIconPickerOpen;
                });
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white,
                ),
                child: _selectedIcon != null
                    ? Icon(
                        _getIconData(_selectedIcon!),
                        size: 28,
                        color: Colors.black,
                      )
                    : const Icon(Icons.add, color: Color(0xFF999999), size: 24),
              ),
            ),
            const SizedBox(width: 12),
            // Поле ввода названия (стиль как на экране входа)
            Expanded(
              child: _buildTitleField(),
            ),
          ],
        ),
        // Выбор иконки
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: _isIconPickerOpen
              ? Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildIconPicker(),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildIconPicker() {
    final iconCategories = {
      'Общее': [
        Icons.circle,
        Icons.star,
        Icons.favorite,
        Icons.flag,
      ],
      'Работа': [
        Icons.work,
        Icons.business_center,
        Icons.assignment,
        Icons.meeting_room,
      ],
      'Учеба': [
        Icons.school,
        Icons.menu_book,
        Icons.edit_note,
        Icons.quiz,
      ],
      'Отдых': [
        Icons.spa,
        Icons.beach_access,
        Icons.nightlife,
        Icons.local_cafe,
      ],
      'Развлечения': [
        Icons.movie,
        Icons.music_note,
        Icons.sports_esports,
        Icons.fitness_center,
      ],
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: iconCategories.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF666666),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entry.value.map((icon) {
                    final iconKey = '${entry.key}_${icon.codePoint}';
                    final isSelected = _selectedIcon == iconKey;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedIcon = iconKey;
                          _isIconPickerOpen = false;
                        });
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFF5F5F5)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? Colors.black
                                : const Color(0xFFE5E5E5),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 22,
                          color: Colors.black,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (entry.key != iconCategories.keys.last)
                const Divider(height: 1, color: Color(0xFFE5E5E5)),
            ],
          );
        }).toList(),
      ),
    );
  }

  IconData _getIconData(String iconKey) {
    // Парсим iconKey формата "Категория_код"
    final parts = iconKey.split('_');
    if (parts.length < 2) return Icons.circle;
    final codePoint = int.tryParse(parts.last);
    if (codePoint == null) return Icons.circle;
    return IconData(codePoint, fontFamily: 'MaterialIcons');
  }

  Widget _buildTitleField() {
    const borderColor = Colors.black;
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
                controller: _titleController,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  hintText: 'Название заметки',
                  hintStyle: TextStyle(color: Color(0xFF999999), fontSize: 16),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18, color: Colors.black),
                cursorColor: borderColor,
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: -11,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Название',
                style: TextStyle(
                  color: Colors.black,
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

  Widget _buildToolsBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Инструменты',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF666666),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildToolChip('Текст', Icons.text_fields),
            _buildToolChip('Задачи', Icons.checklist),
            _buildToolChip('Картинка', Icons.image),
            _buildToolChip('Тег', Icons.tag),
            _buildToolChip('Место', Icons.location_on),
          ],
        ),
      ],
    );
  }

  Widget _buildToolChip(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        // TODO: Реализовать функциональность инструментов
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF666666)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
