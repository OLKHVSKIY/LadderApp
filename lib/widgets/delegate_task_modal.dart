import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';
import 'custom_snackbar.dart';
import 'glass.dart';

class DelegateTaskModal extends StatefulWidget {
  final Task task;
  final Function(String email, bool deleteFromMe) onDelegate;

  const DelegateTaskModal({
    super.key,
    required this.task,
    required this.onDelegate,
  });

  @override
  State<DelegateTaskModal> createState() => _DelegateTaskModalState();
}

class _DelegateTaskModalState extends State<DelegateTaskModal> {
  final TextEditingController _emailController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _emailFieldKey = GlobalKey();
  bool _deleteFromMe = false;

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_onEmailFocusChanged);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocusNode.removeListener(_onEmailFocusChanged);
    _emailFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onEmailFocusChanged() {
    if (_emailFocusNode.hasFocus) {
      // Прокручиваем к полю ввода при фокусе
      Future.delayed(const Duration(milliseconds: 350), () {
        if (_emailFieldKey.currentContext != null && _scrollController.hasClients) {
          final RenderBox? renderBox = _emailFieldKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final offset = renderBox.localToGlobal(Offset.zero);
            final position = _scrollController.position;
            final targetOffset = offset.dy + position.pixels - (position.viewportDimension * 0.4);
            
            _scrollController.animateTo(
              targetOffset.clamp(0.0, position.maxScrollExtent),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
      });
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  void _handleDelegate() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      CustomSnackBar.show(context, tr('Введите email получателя'));
      return;
    }
    if (!_isValidEmail(email)) {
      CustomSnackBar.show(context, tr('Введите корректный email'));
      return;
    }
    HapticFeedback.mediumImpact();
    widget.onDelegate(email, _deleteFromMe);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = screenHeight - keyboardHeight;
    final maxHeight = availableHeight * 0.9; // Максимальная высота 90% доступной области
    
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Невидимая область для обработки клика вне шторки
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          // Шторка с контентом
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: GestureDetector(
                onTap: () {}, // Предотвращаем закрытие при клике на контент
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  child: Material(
                    color: colors.surface,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    // Заголовок
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Text(
                            tr('Поделиться задачей'),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          GlassCircleButton(
                            onTap: () => Navigator.of(context).pop(),
                            size: 32,
                            iconSize: 16,
                          ),
                        ],
                      ),
                    ),
                    // Контент с прокруткой
                    Flexible(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Информация о задаче
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.task.title,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  if (widget.task.description != null && widget.task.description!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.task.description!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    tr('Дата: {0}', ['${widget.task.date.day.toString().padLeft(2, '0')}.${widget.task.date.month.toString().padLeft(2, '0')}.${widget.task.date.year}']),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Поле для email в стиле страницы входа
                            _buildEmailField(),
                            const SizedBox(height: 24),
                            // Чекбокс "Удалить у меня"
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _deleteFromMe = !_deleteFromMe;
                                });
                                HapticFeedback.lightImpact();
                              },
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: _deleteFromMe ? colors.inverseSurface : Colors.transparent,
                                      border: Border.all(
                                        color: _deleteFromMe ? colors.inverseSurface : colors.border,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: _deleteFromMe
                                        ? Icon(
                                            Icons.check,
                                            size: 16,
                                            color: colors.onInverseSurface,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      tr('Удалить у меня'),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    // Кнопка делегирования
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border(
                          top: BorderSide(color: colors.divider),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleDelegate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.inverseSurface,
                            foregroundColor: colors.onInverseSurface,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            tr('Поделиться'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    final colors = AppColors.of(context);
    final borderColor = colors.textPrimary;
    return Padding(
      key: _emailFieldKey,
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: borderColor, width: 1),
              color: colors.surface,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: TextField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: 'whom@example.com',
                  hintStyle: TextStyle(color: colors.textTertiary, fontSize: 16),
                  border: InputBorder.none,
                ),
                style: TextStyle(fontSize: 18, color: colors.textPrimary),
                cursorColor: borderColor,
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: -11,
            child: Container(
              color: colors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                tr('Email получателя'),
                style: TextStyle(
                  color: borderColor,
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
}
