import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';

/// Внутри-приложенческое «празднование» серии при отметке задачи.
///
/// Сверху экрана выезжает баннер: загорается огонь, цифра стрика
/// «перематывается» (как одометр) с прошлого значения на новое, и в этот
/// момент проигрывается беспорядочная вибрация. Сам себя закрывает.
class StreakCelebration extends StatefulWidget {
  final int fromValue;
  final int toValue;
  final VoidCallback onDismiss;

  const StreakCelebration({
    super.key,
    required this.fromValue,
    required this.toValue,
    required this.onDismiss,
  });

  @override
  State<StreakCelebration> createState() => _StreakCelebrationState();
}

class _StreakCelebrationState extends State<StreakCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _entrance; // выезд сверху + проявление
  late final AnimationController _flicker; // мерцание огня
  late final AnimationController _ignite; // «поджиг» огня
  late final Animation<double> _slide;

  late int _displayValue;
  Timer? _rollTimer;
  Timer? _dismissTimer;
  final List<Timer> _hapticTimers = [];

  @override
  void initState() {
    super.initState();
    _displayValue = widget.fromValue;

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slide = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _ignite = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _entrance.forward();
    _ignite.forward();
    _playChaoticHaptics();

    // Перемотка счётчика — после того как огонь разгорелся.
    _rollTimer = Timer(const Duration(milliseconds: 520), () {
      if (mounted) setState(() => _displayValue = widget.toValue);
    });
    // Авто-закрытие.
    _dismissTimer = Timer(const Duration(milliseconds: 2400), _close);
  }

  // Беспорядочная вибрация: импульсы разной силы и со случайными интервалами,
  // как будто огонь разгорается.
  void _playChaoticHaptics() {
    const pattern = [0, 50, 95, 160, 215, 255, 330, 410, 470, 560, 640];
    final rnd = Random();
    for (final d in pattern) {
      _hapticTimers.add(
        Timer(Duration(milliseconds: d + rnd.nextInt(28)), () {
          switch (rnd.nextInt(4)) {
            case 0:
              HapticFeedback.lightImpact();
              break;
            case 1:
              HapticFeedback.mediumImpact();
              break;
            case 2:
              HapticFeedback.heavyImpact();
              break;
            default:
              HapticFeedback.selectionClick();
          }
        }),
      );
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
    _flicker.dispose();
    _ignite.dispose();
    _rollTimer?.cancel();
    _dismissTimer?.cancel();
    for (final t in _hapticTimers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: _close,
          child: AnimatedBuilder(
            animation: _slide,
            builder: (context, child) {
              final v = _slide.value;
              return Opacity(
                opacity: v.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - v) * -120),
                  child: child,
                ),
              );
            },
            child: Center(child: _buildBanner(colors)),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(AppColors colors) {
    return Material(
      type: MaterialType.transparency,
      child: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF7A00).withValues(alpha: 0.30),
              blurRadius: 26,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: colors.isDark
                    ? colors.surface.withValues(alpha: 0.82)
                    : Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFFFF7A00).withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFlame(),
                  const SizedBox(width: 12),
                  _buildRollingNumber(colors),
                  const SizedBox(width: 8),
                  Text(
                    tr('дней подряд'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildFlame() {
    return AnimatedBuilder(
      animation: Listenable.merge([_ignite, _flicker]),
      builder: (context, _) {
        final ignite = Curves.elasticOut.transform(_ignite.value.clamp(0.0, 1.0));
        final f = _flicker.value; // 0..1
        final scale = (0.3 + 0.7 * ignite) * (0.95 + 0.1 * f);
        final glow = (0.35 + 0.4 * f) * ignite;
        return SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF7A00).withValues(alpha: glow),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: scale,
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xFFFF5722), Color(0xFFFFC107)],
                  ).createShader(rect),
                  child: const Icon(
                    Icons.local_fire_department,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRollingNumber(AppColors colors) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        // Растущий счётчик: новая цифра приходит снизу, старая уезжает вверх.
        final isIncoming = child.key == ValueKey<int>(_displayValue);
        final begin =
            isIncoming ? const Offset(0, 0.9) : const Offset(0, -0.9);
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(begin: begin, end: Offset.zero).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
        );
      },
      child: Text(
        '$_displayValue',
        key: ValueKey<int>(_displayValue),
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: colors.textPrimary,
          height: 1,
        ),
      ),
    );
  }
}
