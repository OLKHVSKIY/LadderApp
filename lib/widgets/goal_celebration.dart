import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Универсальный оверлей-празднование для целей: достижение вехи или
/// «ранней победы» первой недели. По центру всплывает карточка с иконкой,
/// заголовком и подписью — с лёгким масштабированием, свечением и серией
/// вибраций. Закрывается сама (или по тапу).
class GoalCelebration extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onDismiss;

  const GoalCelebration({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.onDismiss,
  });

  @override
  State<GoalCelebration> createState() => _GoalCelebrationState();
}

class _GoalCelebrationState extends State<GoalCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _glow;
  late final Animation<double> _scale;
  Timer? _dismissTimer;
  final List<Timer> _hapticTimers = [];

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _scale = CurvedAnimation(parent: _entrance, curve: Curves.elasticOut);
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _entrance.forward();
    _playHaptics();
    _dismissTimer = Timer(const Duration(milliseconds: 2600), _close);
  }

  // Короткая радостная серия вибраций.
  void _playHaptics() {
    final rnd = Random();
    var t = 0;
    const total = 900;
    while (t < total) {
      _hapticTimers.add(Timer(Duration(milliseconds: t), () {
        final roll = rnd.nextDouble();
        if (roll < 0.4) {
          HapticFeedback.mediumImpact();
        } else if (roll < 0.75) {
          HapticFeedback.lightImpact();
        } else {
          HapticFeedback.selectionClick();
        }
      }));
      t += 60 + rnd.nextInt(70);
    }
  }

  void _close() {
    if (!mounted) return;
    _entrance.reverse().whenComplete(() {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _glow.dispose();
    _dismissTimer?.cancel();
    for (final t in _hapticTimers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: AnimatedBuilder(
          animation: _entrance,
          builder: (context, child) {
            final v = _entrance.value.clamp(0.0, 1.0);
            return Opacity(
              opacity: v,
              child: Container(
                color: Colors.black.withValues(alpha: 0.18 * v),
                child: child,
              ),
            );
          },
          child: Center(
            child: ScaleTransition(
              scale: _scale,
              child: _buildCard(colors),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(AppColors colors) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 48),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.30),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              decoration: BoxDecoration(
                color: colors.isDark
                    ? colors.surface.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: widget.color.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIcon(),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (widget.subtitle != null &&
                      widget.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) {
        final g = _glow.value;
        return Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.14),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.25 + 0.25 * g),
                blurRadius: 18 + 10 * g,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(widget.icon, size: 40, color: widget.color),
        );
      },
    );
  }
}
