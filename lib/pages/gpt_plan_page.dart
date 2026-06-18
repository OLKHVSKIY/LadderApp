import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/swipeable_page_route.dart';
import '../widgets/main_header.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/sidebar.dart';
import '../widgets/spotlight_search.dart';
import '../widgets/custom_snackbar.dart';
import 'tasks_page.dart';
import 'plan_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import 'list_page.dart';
import '../l10n/app_translations.dart';

class GptPlanPage extends StatefulWidget {
  const GptPlanPage({super.key});

  @override
  State<GptPlanPage> createState() => _GptPlanPageState();
}

class _GptPlanPageState extends State<GptPlanPage> with TickerProviderStateMixin {
  bool _isSidebarOpen = false;
  int _currentStep = 0;

  final TextEditingController _planNameController = TextEditingController();
  final TextEditingController _goalDescriptionController = TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _daysCountController = TextEditingController(text: '30');
  final Set<int> _weekendDays = {5, 6}; // Сб, Вс по умолчанию

  late final AnimationController _aiIconController;
  late final Animation<double> _aiIconScale;

  @override
  void initState() {
    super.initState();
    _aiIconController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat(reverse: true);
    _aiIconScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _aiIconController, curve: Curves.easeInOutQuad),
    );
  }

  @override
  void dispose() {
    _aiIconController.dispose();
    _planNameController.dispose();
    _goalDescriptionController.dispose();
    _startDateController.dispose();
    _daysCountController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    // Скрываем клавиатуру при открытии/закрытии сайдбара
    FocusScope.of(context).unfocus();
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }

  void _navigateTo(Widget page, {bool slideFromRight = false}) {
    if (page is SettingsPage || page is ChatPage) {
      // Для настроек и чата — push с CupertinoPageRoute (нативный iOS swipe back)
      Navigator.of(context).push(
        SwipeablePageRoute(
          builder: (_) => page,
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, animation, _) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: page,
          ),
        ),
      );
    }
  }

  void _setStep(int step) {
    setState(() {
      _currentStep = step.clamp(0, 2);
    });
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
    } else {
      CustomSnackBar.show(context, tr('Генерация плана скоро будет доступна'));
    }
  }

  void _toggleWeekend(int dayIndex) {
    setState(() {
      if (_weekendDays.contains(dayIndex)) {
        _weekendDays.remove(dayIndex);
      } else {
        _weekendDays.add(dayIndex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top - 10),
            child: Column(
              children: [
                MainHeader(
                  title: tr('GPT План'),
                  onMenuTap: null,
                  showBackButton: true,
                  onBack: () {
                    _navigateTo(const PlanPage(), slideFromRight: true);
                  },
                  onSearchTap: () {
                    showDialog(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.9),
                      builder: (context) => const SpotlightSearch(),
                    );
                  },
                  onSettingsTap: () {
                    _navigateTo(const SettingsPage());
                  },
                  hideSearchAndSettings: true,
                  onGreetingToggle: null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 140),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 4),
                            _buildProgress(),
                            const SizedBox(height: 100),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) => FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                              layoutBuilder: (currentChild, previousChildren) {
                                return Stack(
                                  alignment: Alignment.topCenter,
                                  children: [
                                    ...previousChildren,
                                    if (currentChild != null) currentChild,
                                  ],
                                );
                              },
                              child: _buildStepContent(_currentStep),
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
              _toggleSidebar();
              _navigateTo(const TasksPage(), slideFromRight: false);
            },
            onSettingsTap: () {
              _navigateTo(const SettingsPage(), slideFromRight: true);
            },
          ),
          BottomNavigation(
            currentIndex: 2, // Цели
            isSidebarOpen: _isSidebarOpen,
            onAddTask: () {},
            onTasksTap: () {
              _navigateTo(const TasksPage(), slideFromRight: false);
            },
            onPlanTap: () {
              Navigator.of(context).pop(); // Возвращаемся на PlanPage
            },
            onGptTap: () {},
            onAiTap: () {
              _navigateTo(const ChatPage(), slideFromRight: true);
            },
            onIndexChanged: (index) {
              if (index == 0) {
                _navigateTo(const TasksPage(), slideFromRight: false);
              } else if (index == 1) {
                _navigateTo(const ListPage(), slideFromRight: true);
              } else if (index == 2) {
                _navigateTo(const PlanPage(), slideFromRight: true);
              } else if (index == 3) {
                _navigateTo(const ChatPage(), slideFromRight: true);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final isActive = index == _currentStep;
        final isCompleted = index < _currentStep;
        final color = isActive || isCompleted ? colors.inverseSurface : colors.border;
        final textColor = isActive || isCompleted ? colors.onInverseSurface : colors.textTertiary;
        return GestureDetector(
          onTap: () => _setStep(index),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            scale: isActive ? 1.05 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: color),
              ),
              alignment: Alignment.center,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
                child: Text('${index + 1}'),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent(int step) {
    switch (step) {
      case 0:
        return _buildStepOne();
      case 1:
        return _buildStepTwo();
      case 2:
        return _buildStepThree();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepOne() {
    final colors = AppColors.of(context);
    return Column(
      key: const ValueKey('step1'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: _aiIconScale,
          child: Image.asset(
            'assets/icon/ai.png',
            width: 80,
            height: 80,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          tr('Создайте план проекта с помощью нейросети. Опишите вашу цель, и AI разобьет её на шаги и задачи.'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.6,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 37),
        _inputBlock(
          label: tr('Название плана'),
          child: TextField(
            controller: _planNameController,
            decoration: InputDecoration(
              hintText: tr('Например: Подготовка к марафону'),
              hintStyle: TextStyle(color: colors.textTertiary),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.textPrimary, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _primaryButton(tr('Продолжить'), _nextStep),
      ],
    );
  }

  Widget _buildStepTwo() {
    final colors = AppColors.of(context);
    return Column(
      key: const ValueKey('step2'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _inputBlock(
          label: tr('Описание цели'),
          child: TextField(
            controller: _goalDescriptionController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: tr('Опишите вашу цель подробно...'),
              hintStyle: TextStyle(color: colors.textTertiary),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.textPrimary, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _primaryButton(tr('Продолжить'), _nextStep),
      ],
    );
  }

  Widget _buildStepThree() {
    final colors = AppColors.of(context);
    return Column(
      key: const ValueKey('step3'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _inputBlock(
          label: tr('С какого дня начинать план?'),
          child: TextField(
            controller: _startDateController,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              hintText: tr('ДД.ММ.ГГГГ'),
              hintStyle: TextStyle(color: colors.textTertiary),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.textPrimary, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _inputBlock(
          label: tr('На сколько дней разбить план?'),
          child: TextField(
            controller: _daysCountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '30',
              hintStyle: TextStyle(color: colors.textTertiary),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.textPrimary, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _inputBlock(
          label: tr('Выходные дни'),
          child: _buildWeekendSelector(),
        ),
        const SizedBox(height: 24),
        _primaryButton(tr('Сгенерировать'), _nextStep),
      ],
    );
  }

  Widget _buildWeekendSelector() {
    final colors = AppColors.of(context);
    final days = [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')];
    return Row(
      children: List.generate(days.length, (index) {
        final isActive = _weekendDays.contains(index);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == days.length - 1 ? 0 : 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: isActive ? colors.inverseSurface : colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive ? colors.inverseSurface : colors.border,
                  width: 2,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _toggleWeekend(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        days[index],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isActive ? colors.onInverseSurface : colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _inputBlock({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _primaryButton(String text, VoidCallback onTap) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.inverseSurface,
          foregroundColor: colors.onInverseSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 4,
        ),
        onPressed: onTap,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
