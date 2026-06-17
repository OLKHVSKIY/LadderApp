import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../models/event.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';
import '../utils/app_paths.dart';

/// Секция событий на странице задач: события (дни рождения и т.п.), выпавшие
/// на выбранный день. Событие не закрывается галочкой — оно просто отображается.
/// Тап по карточке открывает редактирование, долгое нажатие — меню.
class EventsSection extends StatefulWidget {
  final List<Event> events;
  final ValueChanged<Event> onView; // тап по карточке — просмотр события
  final ValueChanged<Event> onEdit; // «Редактировать» из меню — редактирование
  final ValueChanged<int> onDelete; // eventId

  const EventsSection({
    super.key,
    required this.events,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<EventsSection> createState() => _EventsSectionState();
}

class _EventsSectionState extends State<EventsSection> {
  bool _expanded = true;
  OverlayEntry? _menuOverlay;

  @override
  void dispose() {
    _menuOverlay?.remove();
    _menuOverlay = null;
    super.dispose();
  }

  void _toggleExpanded() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  void _showMenu(Event e, Offset position) {
    HapticFeedback.mediumImpact();
    _menuOverlay?.remove();
    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;
    const menuWidth = 200.0;
    double left = position.dx;
    if (left + menuWidth > screenSize.width - 12) {
      left = screenSize.width - 12 - menuWidth;
    }
    if (left < 12) left = 12;
    double top = position.dy;
    if (top + 110 > screenSize.height - 12) {
      top = screenSize.height - 12 - 110;
    }
    _menuOverlay = OverlayEntry(
      builder: (_) => _EventMenu(
        left: left,
        top: top,
        width: menuWidth,
        onEdit: () {
          _menuOverlay?.remove();
          _menuOverlay = null;
          widget.onEdit(e);
        },
        onDelete: () {
          _menuOverlay?.remove();
          _menuOverlay = null;
          HapticFeedback.heavyImpact();
          widget.onDelete(e.id!);
        },
        onClose: () {
          _menuOverlay?.remove();
          _menuOverlay = null;
        },
      ),
    );
    overlay.insert(_menuOverlay!);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (widget.events.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _toggleExpanded,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Text(
                    tr('События'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.events.length}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 240),
                    turns: _expanded ? 0.0 : -0.25,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    children: [
                      for (final e in widget.events)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _EventRow(
                            key: ValueKey(e.id),
                            event: e,
                            onTap: () => widget.onView(e),
                            onLongPress: (pos) => _showMenu(e, pos),
                          ),
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatefulWidget {
  final Event event;
  final VoidCallback onTap;
  final ValueChanged<Offset> onLongPress;

  const _EventRow({
    super.key,
    required this.event,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  Offset _pressPosition = Offset.zero;

  // Тёмный ли текст нужен поверх картинки (true = картинка светлая → чёрный текст).
  // null = ещё не посчитали (или картинки нет) → по умолчанию белый текст.
  bool? _useDarkText;
  String? _analyzedPath;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.04,
      vsync: this,
    );
    _analyzeImage();
  }

  @override
  void didUpdateWidget(covariant _EventRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.event.imagePath != oldWidget.event.imagePath) {
      _analyzeImage();
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  // Считаем среднюю яркость картинки и выбираем цвет текста.
  Future<void> _analyzeImage() async {
    final path = AppPaths.resolveEventImage(widget.event.imagePath);
    if (path == null || !File(path).existsSync()) {
      _analyzedPath = null;
      if (mounted && _useDarkText != null) setState(() => _useDarkText = null);
      return;
    }
    if (path == _analyzedPath) return;
    _analyzedPath = path;
    try {
      final bytes = await File(path).readAsBytes();
      // Уменьшаем картинку до 24x24 — для оценки яркости этого достаточно.
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 24,
        targetHeight: 24,
      );
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (data == null) return;
      final pixels = data.buffer.asUint8List();
      double total = 0;
      int count = 0;
      for (int i = 0; i + 3 < pixels.length; i += 4) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        // Воспринимаемая яркость по формуле luma.
        total += 0.299 * r + 0.587 * g + 0.114 * b;
        count++;
      }
      if (count == 0) return;
      final avg = total / count;
      final dark = avg > 140; // светлая картинка → тёмный текст
      if (mounted && path == _analyzedPath && _useDarkText != dark) {
        setState(() => _useDarkText = dark);
      }
    } catch (_) {
      // не удалось декодировать — оставляем белый текст по умолчанию
    }
  }

  String _subtitle() {
    final e = widget.event;
    final parts = <String>[
      tr(e.repeatYearly ? 'Каждый год' : 'Один раз'),
    ];
    if (e.notifyDayBefore && e.notifyOnDay) {
      parts.add(tr('За 1 день и в день'));
    } else if (e.notifyDayBefore) {
      parts.add(tr('За 1 день'));
    } else if (e.notifyOnDay) {
      parts.add(tr('В день'));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final e = widget.event;
    final resolvedImage = AppPaths.resolveEventImage(e.imagePath);
    final hasImage =
        resolvedImage != null && File(resolvedImage).existsSync();

    final Widget content;
    if (hasImage) {
      // Картинка — фон карточки, текст лежит поверх неё.
      // Цвет текста подстраивается под яркость картинки.
      final dark = _useDarkText ?? false; // ещё не посчитали → белый текст
      final textColor = dark ? Colors.black : Colors.white;
      content = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: double.infinity,
          height: 88,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(resolvedImage), fit: BoxFit.cover),
              // Лёгкая подложка слева под текстом — добавляет читаемости.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: dark
                        ? [
                            Colors.white.withValues(alpha: 0.55),
                            Colors.white.withValues(alpha: 0.0),
                          ]
                        : [
                            Colors.black.withValues(alpha: 0.55),
                            Colors.black.withValues(alpha: 0.0),
                          ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textColor.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            // Иконка-заглушка, когда картинки нет.
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 46,
                height: 46,
                color: const Color(0xFFFF2D55).withValues(alpha: 0.14),
                child: const Icon(
                  CupertinoIcons.star_fill,
                  size: 22,
                  color: Color(0xFFFF2D55),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (d) {
        _pressPosition = d.globalPosition;
        _pressController.forward();
      },
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onLongPress: () => widget.onLongPress(_pressPosition),
      child: AnimatedBuilder(
        animation: _pressController,
        builder: (context, child) => Transform.scale(
          scale: 1 - _pressController.value,
          child: child,
        ),
        child: content,
      ),
    );
  }
}

// Контекстное меню события (стиль iOS 26, как меню задач/привычек).
class _EventMenu extends StatefulWidget {
  final double left;
  final double top;
  final double width;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const _EventMenu({
    required this.left,
    required this.top,
    required this.width,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<_EventMenu> createState() => _EventMenuState();
}

class _EventMenuState extends State<_EventMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
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

  // Плавно сворачиваем меню обратно, затем выполняем действие.
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
              top: widget.top,
              child: Material(
                color: Colors.transparent,
                elevation: colors.isDark ? 0 : 10,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(18),
                child: GestureDetector(
                  onTap: () {},
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      alignment: Alignment.topLeft,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.isDark
                                  ? colors.surface.withValues(alpha: 0.72)
                                  : const Color(0xFFF6F7F8)
                                      .withValues(alpha: 0.92),
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
                                children: [
                                  _item(CupertinoIcons.pencil,
                                      tr('Редактировать'),
                                      () => _close(widget.onEdit)),
                                  _divider(),
                                  _item(CupertinoIcons.delete, tr('Удалить'),
                                      () => _close(widget.onDelete),
                                      color: const Color(0xFFFF3B30)),
                                ],
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

  Widget _divider() {
    final colors = AppColors.of(context);
    return Container(
      height: 0.5,
      color: colors.isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.07),
    );
  }

  Widget _item(IconData icon, String text, VoidCallback onTap, {Color? color}) {
    final itemColor = color ?? AppColors.of(context).textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 18, color: itemColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: itemColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
