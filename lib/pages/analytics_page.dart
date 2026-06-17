import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../theme/app_colors.dart';
import '../l10n/app_translations.dart';
import '../models/task.dart';
import '../data/database_instance.dart';
import '../data/user_session.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/plan_repository.dart';
import '../services/streak_service.dart';

/// Страница «Аналитика» — сводка по продуктивности пользователя в стиле Apple.
///
/// Считает метрики на лету из задач (TaskRepository.searchAllTasks),
/// «серии» (StreakService), заметок и целей. Дизайн повторяет iOS: большой
/// сворачивающийся заголовок, сгруппированные «инсетные» карточки на сером
/// фоне, кольцо прогресса и аккуратная типографика.
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  bool _loading = true;

  // Метрики
  int _streakCurrent = 0;
  int _streakBest = 0;
  int _total = 0;
  int _completed = 0;
  int _completedToday = 0;
  int _completedThisWeek = 0;
  int _activeDays = 0;
  int _notesCount = 0;
  int _goalsCount = 0;
  final List<int> _byPriority = [0, 0, 0]; // индексы 0..2 = приоритет 1..3
  final List<int> _byWeekday = List.filled(7, 0); // Пн..Вс — выполнено
  List<MapEntry<String, int>> _topTags = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = UserSession.currentUserId;
    final taskRepo = TaskRepository(appDatabase);
    final noteRepo = NoteRepository(appDatabase);
    final planRepo = PlanRepository(appDatabase);

    final tasks = await taskRepo.searchAllTasks();
    final streak = await StreakService.getInfo();
    final notes = userId != null ? await noteRepo.loadNotes(userId) : [];
    final goals = userId != null ? await planRepo.loadGoals(userId) : [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Начало недели — понедельник.
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    final byPriority = [0, 0, 0];
    final byWeekday = List.filled(7, 0);
    final tagCounts = <String, int>{};
    final activeDaySet = <String>{};
    int completed = 0;
    int completedToday = 0;
    int completedThisWeek = 0;

    for (final Task t in tasks) {
      if (t.priority >= 1 && t.priority <= 3) {
        byPriority[t.priority - 1]++;
      }
      for (final tag in t.tags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
      if (t.isCompleted) {
        completed++;
        final d = DateTime(t.date.year, t.date.month, t.date.day);
        activeDaySet.add('${d.year}-${d.month}-${d.day}');
        byWeekday[t.date.weekday - 1]++;
        if (d == today) completedToday++;
        if (!d.isBefore(weekStart)) completedThisWeek++;
      }
    }

    final topTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (!mounted) return;
    setState(() {
      _streakCurrent = streak.current;
      _streakBest = streak.best;
      _total = tasks.length;
      _completed = completed;
      _completedToday = completedToday;
      _completedThisWeek = completedThisWeek;
      _activeDays = activeDaySet.length;
      _notesCount = notes.length;
      _goalsCount = goals.length;
      _byPriority
        ..[0] = byPriority[0]
        ..[1] = byPriority[1]
        ..[2] = byPriority[2];
      for (int i = 0; i < 7; i++) {
        _byWeekday[i] = byWeekday[i];
      }
      _topTags = topTags.take(8).toList();
      _loading = false;
    });
  }

  double get _completionFraction => _total == 0 ? 0 : _completed / _total;
  int get _completionRate => (_completionFraction * 100).round();

  // Фон в стиле iOS «systemGroupedBackground».
  Color _groupBg(AppColors c) =>
      c.isDark ? Colors.black : const Color(0xFFF2F2F7);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bg = _groupBg(colors);
    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(tr('Аналитика')),
            backgroundColor: bg.withValues(alpha: 0.7),
            border: null,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              onPressed: () => Navigator.of(context).pop(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.back, size: 26),
                  Text(
                    tr('Назад'),
                    style: const TextStyle(fontSize: 17),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CupertinoActivityIndicator()),
            )
          else
            SliverToBoxAdapter(child: _buildContent(colors)),
        ],
      ),
    );
  }

  Widget _buildContent(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          _buildStreakHero(colors),
          _groupHeader(colors, tr('Обзор')),
          _buildSummaryCard(colors),
          _groupHeader(colors, tr('Активность')),
          _buildActivityRow(colors),
          _groupHeader(colors, tr('Контент')),
          _buildContentList(colors),
          _groupHeader(colors, tr('Продуктивность по дням')),
          _buildWeekdayChart(colors),
          _groupHeader(colors, tr('По приоритету')),
          _buildPrioritySection(colors),
          _groupHeader(colors, tr('Популярные теги')),
          _buildTagsSection(colors),
        ],
      ),
    );
  }

  // ── Общие строительные блоки ──────────────────────────────────────────

  Widget _groupHeader(AppColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: colors.textTertiary,
        ),
      ),
    );
  }

  Widget _card(AppColors colors, {required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: colors.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }

  // ── Стрик-герой ───────────────────────────────────────────────────────

  Widget _buildStreakHero(AppColors colors) {
    final active = _streakCurrent > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A00), Color(0xFFFF5252)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF7A00).withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _heroFlame(active),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Текущая серия'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$_streakCurrent',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        tr('дней подряд'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  '$_streakBest',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr('рекорд'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroFlame(bool active) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
          ),
          Icon(
            Icons.local_fire_department,
            size: 36,
            color: Colors.white.withValues(alpha: active ? 1 : 0.6),
          ),
        ],
      ),
    );
  }

  // ── Обзор: кольцо + легенда ───────────────────────────────────────────

  Widget _buildSummaryCard(AppColors colors) {
    final remaining = (_total - _completed).clamp(0, 1 << 30);
    return _card(
      colors,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 112,
              height: 112,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _completionFraction),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return CustomPaint(
                    painter: _RingPainter(
                      progress: value,
                      color: const Color(0xFF34C759),
                      trackColor: colors.isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFEDEDF0),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_completionRate%',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr('готово'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legendRow(colors, const Color(0xFF0A84FF),
                      tr('Всего задач'), _total),
                  const SizedBox(height: 14),
                  _legendRow(colors, const Color(0xFF34C759),
                      tr('Выполнено'), _completed),
                  const SizedBox(height: 14),
                  _legendRow(colors, colors.textTertiary,
                      tr('Осталось'), remaining),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(AppColors colors, Color dot, String label, int value) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }

  // ── Активность: три плитки ────────────────────────────────────────────

  Widget _buildActivityRow(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _miniStat(colors,
                icon: CupertinoIcons.checkmark_alt_circle_fill,
                color: const Color(0xFFFF375F),
                value: '$_completedToday',
                label: tr('Сегодня')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _miniStat(colors,
                icon: CupertinoIcons.calendar,
                color: const Color(0xFF30B0C7),
                value: '$_completedThisWeek',
                label: tr('За неделю')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _miniStat(colors,
                icon: CupertinoIcons.flame_fill,
                color: const Color(0xFFFF9F0A),
                value: '$_activeDays',
                label: tr('Активных дней')),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(AppColors colors,
      {required IconData icon,
      required Color color,
      required String value,
      required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: colors.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Контент: список в стиле iOS Settings ──────────────────────────────

  Widget _buildContentList(AppColors colors) {
    return _card(
      colors,
      child: Column(
        children: [
          _listRow(colors,
              icon: CupertinoIcons.doc_text_fill,
              iconBg: const Color(0xFFAF52DE),
              title: tr('Заметок'),
              value: _notesCount),
          _listDivider(colors),
          _listRow(colors,
              icon: CupertinoIcons.flag_fill,
              iconBg: const Color(0xFF0A84FF),
              title: tr('Целей'),
              value: _goalsCount),
          _listDivider(colors),
          _listRow(colors,
              icon: CupertinoIcons.square_list_fill,
              iconBg: const Color(0xFF34C759),
              title: tr('Всего задач'),
              value: _total),
        ],
      ),
    );
  }

  Widget _listRow(AppColors colors,
      {required IconData icon,
      required Color iconBg,
      required String title,
      required int value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _listDivider(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Container(
        height: 0.5,
        color: colors.isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
      ),
    );
  }

  // ── График по дням недели ─────────────────────────────────────────────

  Widget _buildWeekdayChart(AppColors colors) {
    const labels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final maxVal =
        _byWeekday.fold<int>(0, (m, v) => v > m ? v : m).clamp(1, 1 << 30);
    final hasData = _byWeekday.any((v) => v > 0);
    return _card(
      colors,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: hasData
            ? SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (i) {
                    final v = _byWeekday[i];
                    final h = (v / maxVal) * 96;
                    final isMax = v == maxVal && v > 0;
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            v > 0 ? '$v' : '',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: h < 5 ? 5 : h),
                            duration: Duration(milliseconds: 500 + i * 60),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) => Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              height: value,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: isMax
                                      ? const [
                                          Color(0xFF2DBE55),
                                          Color(0xFF5BE584)
                                        ]
                                      : [
                                          const Color(0xFF34C759)
                                              .withValues(alpha: 0.55),
                                          const Color(0xFF34C759)
                                              .withValues(alpha: 0.8),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              )
            : _emptyHint(colors),
      ),
    );
  }

  // ── По приоритету ─────────────────────────────────────────────────────

  Widget _buildPrioritySection(AppColors colors) {
    const colorsByPriority = [
      Color(0xFFFF3B30), // высокий
      Color(0xFFFFCC00), // средний
      Color(0xFF0A84FF), // низкий
    ];
    final labels = [tr('Высокий'), tr('Средний'), tr('Низкий')];
    final maxVal =
        _byPriority.fold<int>(0, (m, v) => v > m ? v : m).clamp(1, 1 << 30);
    final hasData = _byPriority.any((v) => v > 0);
    return _card(
      colors,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: hasData
            ? Column(
                children: List.generate(3, (i) {
                  final v = _byPriority[i];
                  final frac = v / maxVal;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              children: [
                                Container(
                                  height: 14,
                                  color: colors.isDark
                                      ? const Color(0xFF2C2C2E)
                                      : const Color(0xFFEDEDF0),
                                ),
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: frac),
                                  duration: const Duration(milliseconds: 700),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, _) =>
                                      FractionallySizedBox(
                                    widthFactor: value == 0 ? 0.0 : value,
                                    child: Container(
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: colorsByPriority[i],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 28,
                          child: Text(
                            '$v',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              )
            : Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _emptyHint(colors),
              ),
      ),
    );
  }

  // ── Теги ──────────────────────────────────────────────────────────────

  Widget _buildTagsSection(AppColors colors) {
    return _card(
      colors,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _topTags.isEmpty
            ? _emptyHint(colors)
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _topTags.map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.key,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0A84FF),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${e.value}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }

  Widget _emptyHint(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          tr('Нет данных'),
          style: TextStyle(fontSize: 14, color: colors.textTertiary),
        ),
      ),
    );
  }
}

/// Кольцо прогресса в стиле Apple Fitness (скруглённый колпачок дуги).
class _RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Color trackColor;
  final double stroke;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    // ignore: unused_element_parameter
    this.stroke = 11,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [color.withValues(alpha: 0.75), color],
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}
