import 'package:flutter/material.dart';
import '../widgets/main_header.dart';
import '../widgets/sidebar.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/note_sticker.dart';
import '../widgets/note_editor.dart';
import '../models/note_model.dart';
import '../data/database_instance.dart';
import '../data/repositories/note_repository.dart';
import '../data/user_session.dart';
import 'tasks_page.dart';
import 'chat_page.dart';
import 'plan_page.dart';
import 'settings_page.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  bool _isSidebarOpen = false;
  bool _isEditorOpen = false;
  NoteModel? _editingNote;
  List<NoteModel> _notes = [];
  late final NoteRepository _noteRepository;
  int? _frontNoteId;
  bool _isAligning = false;

  @override
  void initState() {
    super.initState();
    _noteRepository = NoteRepository(appDatabase);
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    final notes = await _noteRepository.loadNotes(userId);
    if (mounted) {
      setState(() {
        _notes = notes;
      });
    }
  }

  void _toggleSidebar() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }

  void _navigateTo(Widget page, {bool slideFromRight = false}) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: page,
        ),
      ),
    );
  }

  void _openEditor({NoteModel? note}) {
    setState(() {
      _editingNote = note;
      _isEditorOpen = true;
    });
  }

  void _closeEditor() {
    setState(() {
      _isEditorOpen = false;
      _editingNote = null;
    });
  }

  Future<void> _saveNote(NoteModel note) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    await _noteRepository.saveNote(note, userId);
    await _loadNotes();
    _closeEditor();
  }

  Future<void> _saveNoteWithoutReload(NoteModel note) async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    await _noteRepository.saveNote(note, userId);
  }

  Future<void> _deleteNote(NoteModel note) async {
    if (note.id == null) return;
    await _noteRepository.deleteNote(note.id!);
    await _loadNotes();
  }

  void _updateNote(NoteModel note) {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      setState(() {
        _notes[index] = note;
      });
      _saveNote(note);
    }
  }

  void _bringNoteToFront(int? noteId) {
    setState(() {
      _frontNoteId = noteId;
    });
  }

  Future<void> _alignNotes() async {
    if (_notes.isEmpty) return;
    
    final padding = 10.0;
    final spacing = 5.0; // Уменьшено расстояние в 2 раза
    final verticalSpacing = 5.0; // Вертикальное расстояние между стикерами
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = _getCrossAxisCount(context);
    final extraPadding = crossAxisCount == 1 ? 40.0 : 0.0;
    // Учитываем увеличенную ширину стикера (+20px)
    final stickerWidth = ((screenWidth - padding * 2 - spacing * (crossAxisCount - 1) - extraPadding) / crossAxisCount) + 20;
    final itemWidth = (screenWidth - padding * 2 - spacing * (crossAxisCount - 1) - extraPadding) / crossAxisCount;
    
    // Группируем стикеры по столбцам для правильного расчета Y позиций
    final List<List<NoteModel>> columns = List.generate(crossAxisCount, (_) => []);
    for (int i = 0; i < _notes.length; i++) {
      final col = i % crossAxisCount;
      columns[col].add(_notes[i]);
    }
    
    // Собираем все изменения перед одним обновлением
    final Map<int, NoteModel> updates = {};
    
    // Выравниваем все стикеры в ряд с плавной анимацией
    for (int col = 0; col < columns.length; col++) {
      double currentY = padding;
      for (final note in columns[col]) {
        final x = padding + col * (stickerWidth + spacing);
        final y = currentY;
        
        final index = _notes.indexWhere((n) => n.id == note.id);
        if (index != -1) {
          updates[index] = _notes[index].copyWith(x: x, y: y);
        }
        
        // Увеличиваем Y на высоту текущего стикера + вертикальное расстояние
        currentY += note.height + verticalSpacing;
      }
    }
    
    // Применяем все изменения одним setState (включая флаг выравнивания)
    if (updates.isNotEmpty) {
      setState(() {
        _isAligning = true;
        updates.forEach((index, note) {
          _notes[index] = note;
        });
      });
      
      // Отключаем флаг выравнивания после завершения анимации
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _isAligning = false;
          });
          
          // Сохраняем все изменения после завершения анимации, чтобы не мешать плавному движению
          for (final note in updates.values) {
            _saveNoteWithoutReload(note);
          }
        }
      });
    }
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 768) {
      return 1; // Мобильные - 1 колонка
    } else if (width < 1024) {
      return 2; // Планшеты - 2 колонки
    } else {
      return 3; // ПК - 3 колонки
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final headerHeight = 60.0;
    final workspaceBarHeight = 36.0;
    final bottomNavHeight = 80.0;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Основной контент
          Padding(
            padding: EdgeInsets.only(
              top: topPadding - 10,
            ),
            child: Column(
              children: [
                // Хедер
                MainHeader(
                  title: 'Заметки',
                  onMenuTap: _toggleSidebar,
                  onSearchTap: () {},
                  onSettingsTap: () {
                    // Действие для кнопки совместной работы
                  },
                  onGreetingToggle: null,
                  searchIconPath: 'assets/icon/change.png',
                  settingsIconPath: 'assets/icon/add-user.png',
                  disableSettingsSpin: true,
                ),
                // Название пространства
                Container(
                  height: workspaceBarHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.centerLeft,
                  child: const Text(
                    'Личное пространство',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF999999),
                    ),
                  ),
                ),
                // Контент заметок
                Expanded(
                  child: _notes.isEmpty
                      ? _buildEmptyState()
                      : _buildNotesGrid(),
                ),
              ],
            ),
          ),
          // Сайдбар
          Sidebar(
            isOpen: _isSidebarOpen,
            onClose: _toggleSidebar,
            onTasksTap: () {
              _navigateTo(const TasksPage(animateNavIn: true), slideFromRight: false);
            },
            onChatTap: () {
              _navigateTo(const ChatPage());
            },
          ),
          // Нижняя навигация
          BottomNavigation(
            currentIndex: 3,
            onTasksTap: () {
              _navigateTo(const TasksPage(animateNavIn: true));
            },
            onPlanTap: () {
              _navigateTo(const PlanPage());
            },
            onGptTap: () {},
            onNotesTap: () {}, // Уже на странице заметок
            onAddTask: () {
              _openEditor();
            },
            isSidebarOpen: _isSidebarOpen,
            isEditorOpen: _isEditorOpen,
          ),
          // Редактор заметок (поверх всего, когда открыт)
          if (_isEditorOpen)
            NoteEditor(
              note: _editingNote,
              onSave: _saveNote,
              onClose: _closeEditor,
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Transform.translate(
        offset: const Offset(0, -50),
        child: Text(
          'Создайте первую заметку',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w400,
            color: Colors.black.withOpacity(0.4),
          ),
        ),
      ),
    );
  }

  Widget _buildNotesGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _getCrossAxisCount(context);
        final padding = 10.0;
        final spacing = 10.0;
        final screenWidth = constraints.maxWidth;
        // Уменьшаем ширину заметок, добавляя больше отступов для мобильных
        final extraPadding = crossAxisCount == 1 ? 40.0 : 0.0;
        final itemWidth = (screenWidth - padding * 2 - spacing * (crossAxisCount - 1) - extraPadding) / crossAxisCount;

        // Инициализируем позиции для новых заметок
        final notesWithPositions = _notes.map((note) {
          if (note.x == 0 && note.y == 0) {
            // Вычисляем начальную позицию в сетке
            final index = _notes.indexOf(note);
            final row = index ~/ crossAxisCount;
            final col = index % crossAxisCount;
            final x = padding + col * (itemWidth + spacing);
            final y = padding + row * 200.0;
            return note.copyWith(
              x: x,
              y: y,
              width: note.width == 0 ? itemWidth : note.width,
            );
          }
          return note.copyWith(
            width: note.width == 0 ? itemWidth : note.width,
          );
        }).toList();
        
        // Сортируем заметки: выбранная заметка должна быть последней (отображаться поверх других)
        // Также учитываем иерархию: чем раньше создана заметка, тем выше она будет (больше z-index)
        notesWithPositions.sort((a, b) {
          if (a.id == _frontNoteId) return 1; // Выбранная заметка идет последней
          if (b.id == _frontNoteId) return -1;
          // Сортируем по дате создания: более старые заметки идут позже (будут выше в z-index)
          // compareTo возвращает отрицательное для более старых дат, поэтому инвертируем
          final aCreated = a.createdAt ?? DateTime.now();
          final bCreated = b.createdAt ?? DateTime.now();
          return bCreated.compareTo(aCreated); // Старые заметки идут позже (больше z-index)
        });

        // Вычисляем максимальную высоту для скролла
        double maxHeight = 0;
        for (final note in notesWithPositions) {
          final bottom = note.y + note.height;
          if (bottom > maxHeight) {
            maxHeight = bottom;
          }
        }
        // Добавляем padding снизу и дополнительные 40px
        final contentHeight = maxHeight + padding + 100;

        return SingleChildScrollView(
          child: Container(
            padding: EdgeInsets.all(padding),
            height: contentHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: notesWithPositions.map((note) {
                return NoteSticker(
                  key: ValueKey(note.id ?? note.hashCode),
                  note: note,
                  onDelete: () => _deleteNote(note),
                  onEdit: () => _openEditor(note: note),
                  onUpdate: _updateNote,
                  onBringToFront: () => _bringNoteToFront(note.id),
                  onAlign: _alignNotes,
                  isAligning: _isAligning,
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _NotesGridPainter extends CustomPainter {
  final int crossAxisCount;
  final double itemWidth;
  final double spacing;

  _NotesGridPainter({
    required this.crossAxisCount,
    required this.itemWidth,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Можно добавить визуальную сетку для отладки
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

