import 'package:flutter/material.dart';
import '../services/streak_service.dart';
import '../l10n/app_translations.dart';

/// Блок «серии» (стрик) в шторке приветствия — в стиле Duolingo.
///
/// Сам подгружает данные из [StreakService]. Перезагружается при изменении
/// [reloadToken] (передаём туда число выполненных сегодня задач, чтобы блок
/// обновлялся сразу после отметки задачи).
class StreakBadge extends StatefulWidget {
  final int reloadToken;
  final VoidCallback? onTap;

  const StreakBadge({
    super.key,
    required this.reloadToken,
    this.onTap,
  });

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<StreakBadge>
    with SingleTickerProviderStateMixin {
  StreakInfo? _info;
  late final AnimationController _flicker;

  @override
  void initState() {
    super.initState();
    // Лёгкое «мерцание/колыхание» огня.
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    // Стартуем с последнего известного значения (если есть) — чтобы не было
    // мерцания «неактивно → активно», пока идёт асинхронная загрузка.
    _info = StreakService.cached;
    _load();
  }

  @override
  void didUpdateWidget(StreakBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _load();
    }
  }

  Future<void> _load() async {
    final info = await StreakService.getInfo();
    if (mounted) setState(() => _info = info);
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final current = info?.current ?? 0;
    final active = current > 0;
    final atRisk = info?.atRisk ?? false;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          // Слегка затемнённый блок (чёрная подложка вместо светлой).
          color: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            _buildFlame(active),
            const SizedBox(width: 14),
            Expanded(child: _buildText(current, active, atRisk)),
            if (widget.onTap != null)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: Colors.white.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildText(int current, bool active, bool atRisk) {
    if (!active) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('Начните серию'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tr('Отметьте задачу за день'),
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$current',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tr('дней подряд'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          atRisk ? tr('Отметьте задачу сегодня') : tr('Серия активна'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: atRisk
                ? const Color(0xFFFFD54F)
                : Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  Widget _buildFlame(bool active) {
    return AnimatedBuilder(
      animation: _flicker,
      builder: (context, _) {
        final t = _flicker.value; // 0..1
        final scale = active ? (0.94 + 0.10 * t) : 1.0;
        final glow = active ? (0.35 + 0.35 * t) : 0.0;
        return SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (active)
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF7A00).withValues(alpha: glow),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              Transform.scale(
                scale: scale,
                child: active
                    ? ShaderMask(
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xFFFF5722), Color(0xFFFFC107)],
                        ).createShader(rect),
                        child: const Icon(
                          Icons.local_fire_department,
                          size: 44,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.local_fire_department,
                        size: 44,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
