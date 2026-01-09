import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import 'custom_snackbar.dart';

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
      CustomSnackBar.show(context, 'Введите email получателя');
      return;
    }
    if (!_isValidEmail(email)) {
      CustomSnackBar.show(context, 'Введите корректный email');
      return;
    }
    HapticFeedback.mediumImpact();
    widget.onDelegate(email, _deleteFromMe);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Material(
                    color: Colors.white,
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
                          const Text(
                            'Поделиться задачей',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.black87,
                              ),
                            ),
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
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.task.title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                  ),
                                  if (widget.task.description != null && widget.task.description!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.task.description!,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    'Дата: ${widget.task.date.day}.${widget.task.date.month}.${widget.task.date.year}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
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
                                      color: _deleteFromMe ? Colors.black : Colors.transparent,
                                      border: Border.all(
                                        color: _deleteFromMe ? Colors.black : Colors.grey[400]!,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: _deleteFromMe
                                        ? const Icon(
                                            Icons.check,
                                            size: 16,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Удалить у меня',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black87,
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
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Colors.grey[200]!),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleDelegate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Поделиться',
                            style: TextStyle(
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
    const borderColor = Colors.black;
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
              color: Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: TextField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  hintText: 'you@example.com',
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Email получателя',
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
