import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/main_header.dart';
import '../widgets/sidebar.dart';
import 'plan_page.dart';
import 'tasks_page.dart';
import 'settings_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  bool _isSidebarOpen = false;
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  void _toggleSidebar() {
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

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _controller.clear();
      _isSending = true;
    });

    // Имитация ответа ассистента
    Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _messages.add(_ChatMessage(
          text: 'Принял. Что ещё нужно сделать?',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isSending = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top - 10,
            ),
            child: Column(
              children: [
                MainHeader(
                  title: 'Чат с AI',
                  onMenuTap: _toggleSidebar,
                  onSearchTap: () {},
                  onSettingsTap: () {
                    _navigateTo(const SettingsPage(), slideFromRight: true);
                  },
                  onGreetingToggle: null,
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Container(
                        color: Colors.white,
                        child: Stack(
                          children: [
                            // Сообщения / пустое состояние
                            Positioned.fill(
                              child: _messages.isEmpty
                                  ? _buildEmptyState()
                                  : _buildMessages(),
                            ),
                            // Поле ввода
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _buildInput(),
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
          Sidebar(
            isOpen: _isSidebarOpen,
            onClose: _toggleSidebar,
            onTasksTap: () {
              _navigateTo(const TasksPage(animateNavIn: true), slideFromRight: false);
            },
            onChatTap: () {
              // Уже на чате — просто закрываем
              _toggleSidebar();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      child: ListView.separated(
        reverse: true,
        itemCount: _messages.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final msg = _messages[_messages.length - 1 - index];
          return _MessageBubble(message: msg);
        },
      ),
    );
  }

  Widget _buildInput() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE5E5E5), width: 1),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: Scrollbar(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.logicalKeysPressed.contains(
                              LogicalKeyboardKey.shiftLeft) &&
                          !HardwareKeyboard.instance.logicalKeysPressed.contains(
                              LogicalKeyboardKey.shiftRight)) {
                        _sendMessage();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      minLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      textInputAction: TextInputAction.send,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Colors.black,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        hintText: 'Напишите сообщение...',
                        hintStyle: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: Color(0xFF999999),
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 0),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _sendMessage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _controller.text.trim().isEmpty
                      ? const Color(0xFFCCCCCC)
                      : Colors.black,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 155),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          Text(
            'Чат с AI',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          Text(
            'Спрашивайте, получайте подсказки и планируйте задачи с помощью AI',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              color: Color(0xFF666666),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bgColor = isUser ? Colors.black : const Color(0xFFF5F5F5);
    final textColor = isUser ? Colors.white : Colors.black;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
      bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        textDirection: isUser ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isUser ? Colors.black : const Color(0xFFF5F5F5),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              isUser ? 'Я' : 'AI',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isUser ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: radius,
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

