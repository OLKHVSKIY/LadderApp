import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../utils/app_paths.dart';
import '../l10n/app_translations.dart';

/// Открыть Apple-style выбор области картинки для баннера события.
/// Возвращает ОТНОСИТЕЛЬНЫЙ путь ('event_images/<файл>.png') сохранённой
/// обрезанной картинки или null, если отменили.
Future<String?> showEventImageCropper(
  BuildContext context, {
  required File source,
}) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _EventImageCropper(source: source),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    ),
  );
}

class _EventImageCropper extends StatefulWidget {
  final File source;
  const _EventImageCropper({required this.source});

  @override
  State<_EventImageCropper> createState() => _EventImageCropperState();
}

class _EventImageCropperState extends State<_EventImageCropper> {
  final GlobalKey _captureKey = GlobalKey();
  final TransformationController _controller = TransformationController();

  ui.Image? _image; // декодированная картинка (для пропорций)
  bool _saving = false;
  bool _centered = false; // выставили ли начальное центрирование

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _image?.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final bytes = await widget.source.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  // Соотношение сторон рамки = как у баннера события (ширина карточки × 88).
  double _bannerAspect(double screenWidth) {
    final bannerWidth = screenWidth - 20; // отступы скролла на странице задач
    return bannerWidth / 88.0;
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      final boundary = _captureKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final dir = Directory(
          p.join(AppPaths.documentsPath, AppPaths.eventImagesDir));
      if (!await dir.exists()) await dir.create(recursive: true);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(byteData.buffer.asUint8List());
      // Возвращаем ОТНОСИТЕЛЬНЫЙ путь (стабилен при переустановке).
      if (mounted) {
        Navigator.of(context)
            .pop(p.join(AppPaths.eventImagesDir, fileName));
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final aspect = _bannerAspect(screenWidth);
    final cropW = screenWidth - 32;
    final cropH = cropW / aspect;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Верхняя панель: Отмена / Заголовок / Готово.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      tr('Отмена'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tr('Выбрать область'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    onPressed: (_image == null || _saving) ? null : _confirm,
                    child: _saving
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : Text(
                            tr('Готово'),
                            style: const TextStyle(
                              color: Color(0xFFFF9500),
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _image == null
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : _buildCropArea(cropW, cropH),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 8),
              child: Text(
                tr('Двигайте и масштабируйте'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCropArea(double cropW, double cropH) {
    final img = _image!;
    final imgW = img.width.toDouble();
    final imgH = img.height.toDouble();

    // Масштабируем картинку, чтобы она ПОЛНОСТЬЮ закрывала рамку (cover):
    // меньшую сторону подгоняем под рамку, другая выходит за неё → её можно
    // двигать. Граница перемещения (boundaryMargin: zero) не даёт показать
    // пустоту за краями картинки.
    final coverScale = (cropW / imgW) > (cropH / imgH)
        ? cropW / imgW
        : cropH / imgH;
    final displayW = imgW * coverScale;
    final displayH = imgH * coverScale;

    // Изначально центрируем переполнение картинки в рамке (как в Apple).
    if (!_centered) {
      _centered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final dx = (cropW - displayW) / 2;
        final dy = (cropH - displayH) / 2;
        _controller.value = Matrix4.identity()..translateByDouble(dx, dy, 0, 1);
      });
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: cropW,
        height: cropH,
        child: Stack(
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: SizedBox(
                width: cropW,
                height: cropH,
                child: InteractiveViewer(
                  transformationController: _controller,
                  constrained: false,
                  clipBehavior: Clip.none,
                  boundaryMargin: EdgeInsets.zero,
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: SizedBox(
                    width: displayW,
                    height: displayH,
                    child: Image.file(widget.source, fit: BoxFit.fill),
                  ),
                ),
              ),
            ),
            // Сетка-направляющая поверх (не попадает в снимок — рисуется
            // в отдельном слое над RepaintBoundary).
            const Positioned.fill(
              child: IgnorePointer(
                child: _GridOverlay(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Тонкая сетка-«трети» поверх области кадрирования (стиль Apple).
class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    // Вертикальные трети.
    for (int i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Горизонтальные трети.
    for (int i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Рамка.
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(16),
      ),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
