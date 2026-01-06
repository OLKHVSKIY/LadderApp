import 'dart:ui';

import 'package:flutter/material.dart';

class AiMenuModal extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback onChat;
  final VoidCallback onPlan;

  const AiMenuModal({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.onChat,
    required this.onPlan,
  });

  @override
  State<AiMenuModal> createState() => _AiMenuModalState();
}

class _AiMenuModalState extends State<AiMenuModal> with TickerProviderStateMixin {
  late final AnimationController _modalController;
  late final AnimationController _iconController;
  late final Animation<double> _modalScale;
  late final Animation<double> _modalOpacity;
  late final Animation<double> _iconScale;
  late final Animation<Offset> _modalSlide;

  @override
  void initState() {
    super.initState();

    _modalController = AnimationController(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
      vsync: this,
    );

    _iconController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);

    _modalScale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _modalController, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
    );
    _modalOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _modalController, curve: Curves.easeOut, reverseCurve: Curves.easeIn),
    );
    _modalSlide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
      CurvedAnimation(parent: _modalController, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
    );

    _iconScale = Tween<double>(begin: 1, end: 1.08).animate(
      CurvedAnimation(parent: _iconController, curve: Curves.easeInOutQuad),
    );

    if (widget.isOpen) {
      _modalController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant AiMenuModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      _modalController.forward();
    } else if (!widget.isOpen && oldWidget.isOpen) {
      _modalController.reverse();
    }
  }

  @override
  void dispose() {
    _modalController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.isOpen,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        opacity: widget.isOpen ? 1 : 0,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                  ),
                ),
              ),
            ),
            Center(
              child: SlideTransition(
                position: _modalSlide,
                child: FadeTransition(
                  opacity: _modalOpacity,
                  child: ScaleTransition(
                    scale: _modalScale,
                    child: _buildModalContent(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalContent(BuildContext context) {
    return Container(
      width: 375,
      constraints: const BoxConstraints(maxWidth: 395),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 52),
          _buildOptions(context),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        ScaleTransition(
          scale: _iconScale,
          child: Image.asset(
            'assets/icon/ai.png',
            width: 64,
            height: 64,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Выберите тип проекта',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Создайте обычный проект или используйте ИИ для автоматического планирования',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF666666),
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildOptions(BuildContext context) {
    return Column(
      children: [
        _AiOptionButton(
          isPrimary: true,
          title: 'Чат с AI',
          subtitle: 'Общайтесь с AI и получайте помощь',
          onTap: () {
            widget.onClose();
            widget.onChat();
          },
        ),
        const SizedBox(height: 12),
        _AiOptionButton(
          isPrimary: false,
          title: 'AI создание плана',
          subtitle: 'AI создаст план автоматически',
          onTap: () {
            widget.onClose();
            widget.onPlan();
          },
        ),
      ],
    );
  }
}

class _AiOptionButton extends StatefulWidget {
  final bool isPrimary;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AiOptionButton({
    required this.isPrimary,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_AiOptionButton> createState() => _AiOptionButtonState();
}

class _AiOptionButtonState extends State<_AiOptionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.isPrimary ? Colors.black : Colors.white;
    final borderColor = widget.isPrimary ? Colors.black : const Color(0xFFE5E5E5);
    final textColor = widget.isPrimary ? Colors.white : Colors.black;
    final subtitleColor = widget.isPrimary ? Colors.white.withOpacity(0.8) : const Color(0xFF666666);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _isPressed ? 0 : -2, 0),
      decoration: BoxDecoration(
        color: baseColor,
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isPressed
            ? null
            : [
                if (!widget.isPrimary)
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
              ],
      ),
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: () {
            setState(() => _isPressed = false);
            widget.onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: subtitleColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

