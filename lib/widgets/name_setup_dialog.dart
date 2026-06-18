import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_translations.dart';
import '../utils/name_validator.dart';

/// Показывает окно ввода имени в стиле Apple Liquid Glass.
///
/// Возвращает введённое (валидное) имя или null, если окно закрыли без
/// сохранения. При [dismissible] == false (первый вход) закрыть без ввода
/// имени нельзя.
Future<String?> showNameDialog(
  BuildContext context, {
  String? initialName,
  bool dismissible = false,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'name_dialog',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, a1, a2) => _NameDialog(
      initialName: initialName,
      dismissible: dismissible,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      // Плавное появление и закрытие: разные кривые для входа/выхода,
      // без отскока (easeOutBack давал рывок при закрытии).
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      // Один контроллер кривой гонит сразу blur фона, прозрачность и масштаб
      // окна — всё нарастает и затухает РАЗОМ, как единое целое. Фон слегка
      // размывается синхронно с появлением окна.
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final v = curved.value.clamp(0.0, 1.0);
          return BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 6 * v, sigmaY: 6 * v),
            child: Opacity(
              opacity: v,
              child: Transform.scale(
                scale: 0.94 + 0.06 * v,
                child: child,
              ),
            ),
          );
        },
      );
    },
  );
}

class _NameDialog extends StatefulWidget {
  final String? initialName;
  final bool dismissible;

  const _NameDialog({this.initialName, required this.dismissible});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text;
    final err = NameValidator.validate(raw);
    if (err != null) {
      HapticFeedback.lightImpact();
      setState(() => _error = tr(err));
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return PopScope(
      canPop: widget.dismissible,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: bottomInset > 0 ? bottomInset + 16 : 0,
            ),
            child: Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  // Панель — обычный полупрозрачный контейнер (без own-layer
                  // Liquid Glass и BackdropFilter): такой блок входит в общее
                  // дерево слоёв вместе с текстом и эмодзи, поэтому при
                  // scale+fade всё появляется/исчезает РАЗОМ, а не «стеклянный
                  // блок последним». Барьер уже затемняет фон, так что
                  // тёмная стеклоподобная заливка с белой подсветкой смотрится
                  // премиально и в стиле Apple.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.16),
                          Colors.white.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '👋',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 40),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr('Как вас зовут?'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr('Так вас будут видеть в приложении'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 22),
                          // Поле ввода
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _error != null
                                    ? const Color(0xFFFF6B6B)
                                        .withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.28),
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 13),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              textAlign: TextAlign.center,
                              textInputAction: TextInputAction.done,
                              textCapitalization: TextCapitalization.words,
                              maxLength: NameValidator.inputMaxLength,
                              onChanged: (_) {
                                if (_error != null) {
                                  setState(() => _error = null);
                                }
                              },
                              onSubmitted: (_) => _submit(),
                              cursorColor: Colors.white,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                counterText: '',
                                border: InputBorder.none,
                                hintText: tr('Ваше имя'),
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFF8A80),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          // Кнопка подтверждения
                          GestureDetector(
                            onTap: _submit,
                            child: Container(
                              height: 50,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                widget.dismissible
                                    ? tr('Сохранить')
                                    : tr('Продолжить'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
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
          ),
        ),
      ),
    );
  }
}
