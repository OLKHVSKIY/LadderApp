import 'package:flutter/material.dart';

class BottomNavigation extends StatefulWidget {
  final int currentIndex;
  final VoidCallback? onAddTask;
  final VoidCallback? onTasksTap;
  final VoidCallback? onPlanTap;
  final VoidCallback? onGptTap;
  final VoidCallback? onNotesTap;
  final Function(int)? onIndexChanged;
  final double activeIndicatorWidth;
  final double activeIndicatorHeight;
  final bool isSidebarOpen;
  final bool isEditorOpen;

  const BottomNavigation({
    super.key,
    required this.currentIndex,
    this.onAddTask,
    this.onTasksTap,
    this.onPlanTap,
    this.onGptTap,
    this.onNotesTap,
    this.onIndexChanged,
    this.activeIndicatorWidth = 77, // Ширина овала по умолчанию
    this.activeIndicatorHeight = 59, // Высота овала по умолчанию
    this.isSidebarOpen = false,
    this.isEditorOpen = false,
  });

  @override
  State<BottomNavigation> createState() => _BottomNavigationState();
}

class _BottomNavigationState extends State<BottomNavigation> {
  final GlobalKey _stackKey = GlobalKey();
  double? _dragOffset;
  double? _initialDragX;
  double? _initialLeftPosition;
  bool _isDragging = false;
  bool _previousShouldHide = false;
  bool _isInitialBuild = true;
  
  @override
  void didUpdateWidget(BottomNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Обновляем предыдущее состояние только если виджет действительно обновляется
    // (не пересоздается при переходе между страницами)
    final oldShouldHide = oldWidget.isSidebarOpen || oldWidget.isEditorOpen;
    final newShouldHide = widget.isSidebarOpen || widget.isEditorOpen;
    if (oldShouldHide != newShouldHide) {
      _previousShouldHide = oldShouldHide;
      _isInitialBuild = false;
    }
    
    // Если изменился currentIndex (нажали на кнопку), сбрасываем состояние перетаскивания
    if (oldWidget.currentIndex != widget.currentIndex) {
      setState(() {
        _dragOffset = null;
        _initialDragX = null;
        _initialLeftPosition = null;
        _isDragging = false;
      });
    }
  }

  int? _calculateButtonIndex(double centerX, BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final containerLeft = 22.0;
    final paddingHorizontal = 20.0;
    final buttonSpacing = 85.0;
    final buttonGap = 5.0;
    final containerWidth = screenWidth - containerLeft * 2;
    final contentWidth = containerWidth - paddingHorizontal * 2;
    final buttonWidth = (contentWidth - buttonSpacing - buttonGap * 2) / 4;
    
    // Вычисляем позицию центра овала относительно начала контента (после padding)
    final relativeX = centerX - containerLeft - paddingHorizontal;
    
    // Границы центров кнопок
    if (relativeX < buttonWidth / 2 + buttonWidth / 2) return 0; // Задачи
    if (relativeX < buttonWidth + buttonGap + buttonWidth / 2 + buttonWidth / 2) return 1; // GPT
    if (relativeX < buttonWidth * 2 + buttonGap + buttonSpacing + buttonWidth / 2 + buttonWidth / 2) return 2; // План
    if (relativeX < buttonWidth * 3 + buttonGap * 2 + buttonSpacing + buttonWidth / 2 + buttonWidth / 2) return 3; // Заметки
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final navHeight = 60.0;
    final navBottom = 15.0;
    
    final shouldHide = widget.isSidebarOpen || widget.isEditorOpen;
    final targetBottom = shouldHide
        ? -(navHeight + navBottom + bottomPadding + 20)
        : navBottom;
    
    // При первой сборке виджета устанавливаем позицию сразу без анимации
    if (_isInitialBuild) {
      _isInitialBuild = false;
      _previousShouldHide = shouldHide;
      // Используем Positioned вместо AnimatedPositioned для мгновенной установки позиции
      return Positioned(
        bottom: targetBottom,
        left: 22,
        right: 22,
        child: _buildNavigationContent(),
      );
    }
    
    // Проверяем, изменилось ли состояние скрытия
    final stateChanged = _previousShouldHide != shouldHide;
    
    // Анимируем только если состояние действительно изменилось
    if (stateChanged) {
      _previousShouldHide = shouldHide;
    }
    
    return AnimatedPositioned(
      duration: stateChanged ? const Duration(milliseconds: 300) : Duration.zero,
      curve: Curves.easeOutCubic,
      bottom: targetBottom,
      left: 22,
      right: 22,
      child: _buildNavigationContent(),
    );
  }
  
  Widget _buildNavigationContent() {
    return Container(
      height: 62, // Фиксированная высота панели
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: const Color(0xFF878585).withOpacity(0.22),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          key: _stackKey,
          clipBehavior: Clip.none,
          children: [
            // Активные индикаторы (ПОД контентом)
            ..._buildActiveIndicators(context),
            
            // Содержимое панели навигации
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Задачи
                  Expanded(
                    child: _buildNavItemContent(
                      iconPath: 'assets/icon/checklist.png',
                      label: 'Задачи',
                      isActive: widget.currentIndex == 0,
                      onTap: widget.onTasksTap,
                      iconSize: 23, // Увеличиваем на 1px
                      spacing: 3, // Уменьшаем на 1px, чтобы текст остался на месте
                    ),
                  ),
                  const SizedBox(width: 5),
                  // GPT (переименован в Список)
                  Expanded(
                    child: _buildNavItemContent(
                      iconPath: 'assets/icon/notes.png',
                      label: 'Список',
                    isActive: widget.currentIndex == 1,
                    onTap: widget.onGptTap,
                    ),
                  ),
                  // Пустое место для кнопки
                  const SizedBox(width: 85),
                  // План (Цели)
                  Expanded(
                    child: _buildNavItemContent(
                      iconPath: 'assets/icon/draft.png',
                      label: 'Цели',
                      isActive: widget.currentIndex == 2,
                      onTap: widget.onPlanTap,
                      iconSize: 23, // Увеличиваем на 1px
                      spacing: 3, // Уменьшаем на 1px, чтобы текст остался на месте
                    ),
                  ),
                  const SizedBox(width: 5),
                  // Заметки
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _buildNavItemContent(
                        iconPath: 'assets/icon/notes-icon.png',
                        label: 'Заметки',
                        isActive: widget.currentIndex == 3,
                        onTap: widget.onNotesTap,
                        iconSize: 26, // Увеличиваем размер иконки Заметок
                        spacing: 2, // Уменьшаем отступ между иконкой и текстом на 2px
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Кнопка добавления (в центре внутри панели)
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: widget.onAddTask,
                  child: Container(
                    width: 63,
                    height: 63,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
            // Невидимый слой для перехвата событий перетаскивания
            ..._buildDragHandler(context),
          ],
        ),
    );
  }

  // Вычисляет процент перекрытия овала с кнопкой
  double _calculateOverlap(double ovalLeft, double ovalRight, double buttonLeft, double buttonRight, double ovalWidth) {
    // Вычисляем область перекрытия
    final overlapLeft = ovalLeft > buttonLeft ? ovalLeft : buttonLeft;
    final overlapRight = ovalRight < buttonRight ? ovalRight : buttonRight;
    
    // Если нет перекрытия
    if (overlapLeft >= overlapRight) {
      return 0.0;
    }
    
    // Вычисляем длину перекрытия
    final overlapWidth = overlapRight - overlapLeft;
    
    // Возвращаем процент перекрытия относительно ширины овала
    return overlapWidth / ovalWidth;
  }

  // Метод для построения невидимого обработчика перетаскивания
  List<Widget> _buildDragHandler(BuildContext context) {
    if (widget.currentIndex < 0 || widget.currentIndex > 3) {
      return [];
    }
    
    final screenWidth = MediaQuery.of(context).size.width;
    final containerLeft = 22.0;
    final paddingHorizontal = 20.0;
    final buttonSpacing = 85.0;
    final buttonGap = 5.0;
    final containerWidth = screenWidth - containerLeft * 2;
    final contentWidth = containerWidth - paddingHorizontal * 2;
    final buttonWidth = (contentWidth - buttonSpacing - buttonGap * 2) / 4;
    
    double leftPosition = 0;
    
    // Вычисляем позицию центра каждой кнопки
    switch (widget.currentIndex) {
      case 0: // Задачи - первая кнопка
        leftPosition = paddingHorizontal + buttonWidth / 2 - widget.activeIndicatorWidth / 2;
        break;
      case 1: // GPT - вторая кнопка (после SizedBox(5))
        leftPosition = paddingHorizontal + buttonWidth + buttonGap + buttonWidth / 2 - widget.activeIndicatorWidth / 2;
        break;
      case 2: // План - третья кнопка (после SizedBox(85))
        leftPosition = paddingHorizontal + buttonWidth * 2 + buttonGap + buttonSpacing + buttonWidth / 2 - widget.activeIndicatorWidth / 2 - 2;
        break;
      case 3: // Заметки - четвертая кнопка (после SizedBox(5))
        leftPosition = paddingHorizontal + buttonWidth * 3 + buttonGap * 2 + buttonSpacing + buttonWidth / 2 - widget.activeIndicatorWidth / 2;
        break;
    }
    
    // Вычисляем текущую позицию с учетом перетаскивания
    double currentLeft = leftPosition;
    if (_dragOffset != null && _initialLeftPosition != null) {
      currentLeft = _initialLeftPosition! + _dragOffset!;
    }
    
    return [
      Positioned(
        left: currentLeft,
        top: (62 - 55) / 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            setState(() {
              _initialDragX = details.localPosition.dx;
              _initialLeftPosition = leftPosition;
              _dragOffset = 0;
              _isDragging = true;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              final deltaX = details.localPosition.dx - (_initialDragX ?? 0);
              _dragOffset = deltaX;
            });
          },
          onPanEnd: (details) {
            final finalLeftPosition = (_initialLeftPosition ?? leftPosition) + (_dragOffset ?? 0);
            final ovalLeft = finalLeftPosition;
            final ovalRight = finalLeftPosition + widget.activeIndicatorWidth;
            
            // Вычисляем позиции кнопок относительно Stack (с учетом padding)
            final buttonLeft0 = paddingHorizontal + 0.0;
            final buttonRight0 = paddingHorizontal + buttonWidth;
            final buttonLeft1 = paddingHorizontal + buttonWidth + buttonGap;
            final buttonRight1 = paddingHorizontal + buttonWidth + buttonGap + buttonWidth;
            final buttonLeft2 = paddingHorizontal + buttonWidth * 2 + buttonGap + buttonSpacing;
            final buttonRight2 = paddingHorizontal + buttonWidth * 2 + buttonGap + buttonSpacing + buttonWidth;
            final buttonLeft3 = paddingHorizontal + buttonWidth * 3 + buttonGap * 2 + buttonSpacing;
            final buttonRight3 = paddingHorizontal + buttonWidth * 3 + buttonGap * 2 + buttonSpacing + buttonWidth;
            
            // Вычисляем перекрытие овала с каждой кнопкой
            final overlaps = [
              _calculateOverlap(ovalLeft, ovalRight, buttonLeft0, buttonRight0, widget.activeIndicatorWidth),
              _calculateOverlap(ovalLeft, ovalRight, buttonLeft1, buttonRight1, widget.activeIndicatorWidth),
              _calculateOverlap(ovalLeft, ovalRight, buttonLeft2, buttonRight2, widget.activeIndicatorWidth),
              _calculateOverlap(ovalLeft, ovalRight, buttonLeft3, buttonRight3, widget.activeIndicatorWidth),
            ];
            
            // Находим максимальное перекрытие
            final maxOverlap = overlaps.reduce((a, b) => a > b ? a : b);
            final maxIndex = overlaps.indexOf(maxOverlap);
            
            // Если овал перекрывает кнопку на 40% или более, переключаемся на неё
            if (maxOverlap >= 0.4) {
              if (maxIndex != widget.currentIndex && widget.onIndexChanged != null) {
                // Сначала сбрасываем перетаскивание, чтобы овал плавно уменьшился
                setState(() {
                  _dragOffset = null;
                  _initialDragX = null;
                  _initialLeftPosition = null;
                  _isDragging = false;
                });
                // Затем переключаемся на новую кнопку (овал плавно переместится)
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (mounted) {
                    widget.onIndexChanged!(maxIndex);
                  }
                });
                return;
              }
            }
            
            setState(() {
              _dragOffset = null;
              _initialDragX = null;
              _initialLeftPosition = null;
              _isDragging = false;
            });
          },
          onPanCancel: () {
            setState(() {
              _dragOffset = null;
              _initialDragX = null;
              _initialLeftPosition = null;
              _isDragging = false;
            });
          },
          child: Container(
            width: widget.activeIndicatorWidth,
            height: 55,
            color: Colors.transparent, // Невидимый, но перехватывает события
          ),
        ),
      ),
    ];
  }

  // Метод для построения активных индикаторов
  List<Widget> _buildActiveIndicators(BuildContext context) {
    if (widget.currentIndex < 0 || widget.currentIndex > 3) {
      return [];
    }
    
    final screenWidth = MediaQuery.of(context).size.width;
    final containerLeft = 22.0;
    final paddingHorizontal = 20.0;
    final buttonSpacing = 85.0;
    final buttonGap = 5.0;
    final containerWidth = screenWidth - containerLeft * 2;
    final contentWidth = containerWidth - paddingHorizontal * 2;
    final buttonWidth = (contentWidth - buttonSpacing - buttonGap * 2) / 4;
    
    double leftPosition = 0;
    
    // Вычисляем позицию центра каждой кнопки
    switch (widget.currentIndex) {
      case 0: // Задачи - первая кнопка
        leftPosition = paddingHorizontal + buttonWidth / 2 - widget.activeIndicatorWidth / 2;
        break;
      case 1: // GPT - вторая кнопка (после SizedBox(5))
        leftPosition = paddingHorizontal + buttonWidth + buttonGap + buttonWidth / 2 - widget.activeIndicatorWidth / 2;
        break;
      case 2: // План - третья кнопка (после SizedBox(85))
        leftPosition = paddingHorizontal + buttonWidth * 2 + buttonGap + buttonSpacing + buttonWidth / 2 - widget.activeIndicatorWidth / 2 - 2;
        break;
      case 3: // Заметки - четвертая кнопка (после SizedBox(5))
        leftPosition = paddingHorizontal + buttonWidth * 3 + buttonGap * 2 + buttonSpacing + buttonWidth / 2 - widget.activeIndicatorWidth / 2;
        break;
    }
    
    // Применяем смещение при перетаскивании
    if (_dragOffset != null) {
      leftPosition += _dragOffset!;
    }
    
    // Вычисляем текущую позицию с учетом перетаскивания
    double currentLeft = leftPosition;
    if (_dragOffset != null && _initialLeftPosition != null) {
      currentLeft = _initialLeftPosition! + _dragOffset!;
    }
    
    // Вычисляем размер овала (увеличивается при удержании)
    final baseWidth = widget.activeIndicatorWidth;
    final baseHeight = 55.0;
    final scale = _isDragging ? 1.15 : 1.0;
    final currentWidth = baseWidth * scale;
    final currentHeight = baseHeight * scale;
    
    return [
      AnimatedPositioned(
        duration: _dragOffset != null ? Duration.zero : const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
        left: currentLeft - (currentWidth - baseWidth) / 2, // Компенсируем увеличение размера
        top: (62 - currentHeight) / 2, // Центрируем вертикально
        child: IgnorePointer(
          ignoring: true, // Игнорируем события касания, чтобы они проходили к кнопкам
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: currentWidth,
            height: currentHeight,
            decoration: BoxDecoration(
              color: const Color(0xFFEFEEF2).withOpacity(0.77),
              borderRadius: BorderRadius.circular(40),
            ),
          ),
        ),
      ),
    ];
  }

  // Контент элемента навигации (без индикатора)
  Widget _buildNavItemContent({
    required String iconPath,
    required String label,
    required bool isActive,
    VoidCallback? onTap,
    double iconSize = 22, // Размер иконки по умолчанию
    double spacing = 4, // Отступ между иконкой и текстом по умолчанию
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 49,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                isActive ? Colors.black : const Color(0xFF999999),
                BlendMode.srcIn,
              ),
              child: Image.asset(
                iconPath,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(height: spacing),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                color: isActive ? Colors.black : const Color(0xFF999999),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
