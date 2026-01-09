import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:async';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _starsAnimationController;
  late AnimationController _paddingAnimationController;
  String? _selectedPlan;
  final ScrollController _scrollController = ScrollController();
  int _visibleBenefits = 1; // Первый элемент виден сразу
  bool _showPrices = false;
  bool _showTerms = false;
  bool _headerVisible = false;
  double _maxScrollOffset = 0.0; // Максимальная позиция скролла для отслеживания прокрутки вниз
  double _currentTopPadding = 0.0; // Текущий верхний отступ для плавной анимации
  Set<int> _vibratedBenefits = {}; // Отслеживание вибрированных блоков
  bool _isUpdating = false; // Флаг для предотвращения множественных обновлений

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _animationController.forward();

    // Контроллер для анимации звезд (постоянное мерцание)
    _starsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Контроллер для анимации topPadding
    _paddingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );


    // Инициализируем начальный topPadding
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final screenHeight = MediaQuery.of(context).size.height;
        final headerHeight = 120.0;
        _currentTopPadding = ((screenHeight - headerHeight) / 2).clamp(60.0, 200.0);
        setState(() {});
      }
    });

    // Плавно показываем заголовок
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _headerVisible = true;
        });
      }
    });

    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animationController.dispose();
    _starsAnimationController.dispose();
    _paddingAnimationController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    
    // Заголовок появляется сразу при открытии
    if (!_headerVisible) {
      setState(() {
        _headerVisible = true;
      });
    }
    
    final scrollOffset = _scrollController.offset;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Отслеживаем максимальную позицию скролла
    if (scrollOffset > _maxScrollOffset) {
      _maxScrollOffset = scrollOffset;
    }
    
    // Определяем, был ли скролл вниз (прокрутили больше чем на половину экрана)
    final hasScrolledDown = _maxScrollOffset > screenHeight * 0.3;
    
    // Вычисляем реальную позицию элементов с учетом верхнего отступа
    final headerHeight = 120.0; // Заголовок (текст + отступы)
    
    // Вычисляем целевой topPadding в зависимости от того, скроллили ли вниз
    final targetTopPadding = hasScrolledDown 
        ? 20.0 // Маленький отступ рядом с хедером
        : ((screenHeight - headerHeight) / 2).clamp(60.0, 200.0); // Центрирование при первом открытии
    
    // Плавно анимируем переход topPadding
    if (_currentTopPadding == 0.0) {
      // Первая инициализация
      _currentTopPadding = targetTopPadding;
      if (mounted) setState(() {});
    } else if ((_currentTopPadding - targetTopPadding).abs() > 1.0 && !_paddingAnimationController.isAnimating) {
      // Анимируем только если значение изменилось и анимация не идет
      _paddingAnimationController.reset();
      final animation = Tween<double>(
        begin: _currentTopPadding,
        end: targetTopPadding,
      ).animate(CurvedAnimation(
        parent: _paddingAnimationController,
        curve: Curves.easeInOut,
      ));
      
      animation.addListener(() {
        if (mounted && !_isUpdating) {
          _isUpdating = true;
          _currentTopPadding = animation.value;
          // Обновляем только один раз за кадр
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _isUpdating = false;
              setState(() {});
            }
          });
        } else if (mounted) {
          // Просто обновляем значение без setState
          _currentTopPadding = animation.value;
        }
      });
      _paddingAnimationController.forward();
    }
    
    final dynamicTopPadding = _currentTopPadding > 0 ? _currentTopPadding : targetTopPadding;
    
    // Высота элементов
    const benefitItemHeight = 100.0; // Одно преимущество (примерно)
    const spacing = 24.0; // Отступ между элементами
    
    // Позиция начала преимуществ (после заголовка)
    final benefitsStartY = dynamicTopPadding + headerHeight + 40;
    
    // Центр видимой области экрана
    final visibleCenter = scrollOffset + screenHeight / 2;
    
    // Вычисляем какие преимущества должны быть видимы
    // Элемент появляется когда он попадает в центр экрана
    int newVisibleCount = 0;
    
    for (int i = 0; i < _benefits.length; i++) {
      final itemTop = benefitsStartY + (i * (benefitItemHeight + spacing));
      final itemCenter = itemTop + benefitItemHeight / 2;
      
      // Элемент появляется когда его центр попадает в видимую область экрана
      if (itemCenter <= visibleCenter + 150) {
        newVisibleCount = i + 1;
      } else {
        break;
      }
    }
    
    newVisibleCount = newVisibleCount.clamp(0, _benefits.length);
    
    bool needSet = false;
    if (newVisibleCount != _visibleBenefits) {
      // Добавляем вибрацию для новых блоков при первом появлении
      for (int i = _visibleBenefits; i < newVisibleCount; i++) {
        if (!_vibratedBenefits.contains(i)) {
          _vibratedBenefits.add(i);
          HapticFeedback.mediumImpact();
        }
      }
      _visibleBenefits = newVisibleCount;
      needSet = true;
    }
    
    // Цены появляются когда последнее преимущество прошло центр экрана
    final lastBenefitTop = benefitsStartY + (_benefits.length * (benefitItemHeight + spacing));
    final showPricesNow = visibleCenter >= lastBenefitTop + 200;
    
    if (showPricesNow != _showPrices) {
      _showPrices = showPricesNow;
      needSet = true;
    }
    
    // Условия появляются только при дополнительном скролле после цен
    // Вычисляем позицию конца блока цен
    final pricesSectionTop = lastBenefitTop + 60; // Отступ перед ценами
    const pricesSectionHeight = 550.0; // Высота блока цен (3 карточки + кнопка + отступы)
    final pricesSectionBottom = pricesSectionTop + pricesSectionHeight;
    
    // Условия и политики появляются после дополнительного скролла (в самом низу страницы)
    final showTermsNow = scrollOffset >= pricesSectionBottom + 150;
    
    if (showTermsNow != _showTerms) {
      _showTerms = showTermsNow;
      needSet = true;
    }
    
    // Отложенный setState для предотвращения ускорения скролла
    if (needSet && mounted && !_isUpdating) {
      _isUpdating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _isUpdating = false;
          setState(() {});
        }
      });
    }
  }

  void _handleSubscribe(String plan) {
    setState(() {
      _selectedPlan = plan;
    });
    HapticFeedback.mediumImpact();
    // TODO: Реализовать логику подписки
    // Не закрываем страницу автоматически - пользователь может нажать "Продолжить"
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Stack(
              children: [
                // Звезды на всем экране
                Positioned.fill(
                  child: Stack(
                    children: _buildStars(screenWidth, screenHeight),
                  ),
                ),
                // Скроллируемый контент
                Column(
                  children: [
                    // Кнопка назад
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _buildScrollContent(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollContent() {
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Используем текущий анимированный topPadding
    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: (o) {
        o.disallowIndicator();
        return true;
      },
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(20, _currentTopPadding, 20, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Заголовок "Преимущества Pro"
          AnimatedOpacity(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            opacity: _headerVisible ? 1 : 0,
            child: Column(
              children: [
                const Text(
                  'Преимущества Pro',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Листай ниже',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
          // Преимущества - все элементы в списке, появляются плавно
          _buildBenefitsSection(),
          const SizedBox(height: 60),
          // Цены - появляются в конце
          _buildPlansSection(),
          const SizedBox(height: 40),
          // Кнопка продолжить
          if (_showPrices) _buildContinueButton(),
          const SizedBox(height: 60),
          // Условия использования
          if (_showTerms) _buildTerms(),
        ],
      ),
    );
  }

  Widget _buildBenefitsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Все преимущества в списке, появляются плавно при скролле
        ..._benefits.asMap().entries.map((entry) {
          final index = entry.key;
          final benefit = entry.value;
          final visible = index < _visibleBenefits;
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            opacity: visible ? 1.0 : 0.0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              offset: visible ? Offset.zero : const Offset(0, 0.1),
              child: _buildBenefitItem(
                icon: benefit['icon'] as IconData,
                title: benefit['title'] as String,
                description: benefit['description'] as String,
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlansSection() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      opacity: _showPrices ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        offset: _showPrices ? Offset.zero : const Offset(0, 0.1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Выберите план',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            _buildPlanCard(
              plan: 'yearly',
              title: 'Годовая',
              price: '2199.00Р',
              subtitle: '',
              savings: 'Экономия 40%',
              isPopular: true,
            ),
            const SizedBox(height: 12),
            _buildPlanCard(
              plan: 'monthly',
              title: 'Месячная',
              price: '490.00Р',
              subtitle: 'Подписка на Ladder Pro',
            ),
            const SizedBox(height: 12),
            _buildPlanCard(
              plan: 'weekly',
              title: 'Недельная',
              price: '149.00Р',
              subtitle: 'Подписка на Ladder Pro',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String plan,
    required String title,
    required String price,
    required String subtitle,
    String? savings,
    bool isPopular = false,
  }) {
    final isSelected = _selectedPlan == plan;
    
    return GestureDetector(
      onTap: () => _handleSubscribe(plan),
      child: isPopular && !isSelected
          ? AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
              child: _buildPlanCardContent(
                plan: plan,
                title: title,
                price: price,
                subtitle: subtitle,
                savings: savings,
                isPopular: isPopular,
                isSelected: isSelected,
              ),
            )
          : AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white24,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: _buildPlanCardContent(
                plan: plan,
                title: title,
                price: price,
                subtitle: subtitle,
                savings: savings,
                isPopular: isPopular,
                isSelected: isSelected,
              ),
            ),
    );
  }

  Widget _buildPlanCardContent({
    required String plan,
    required String title,
    required String price,
    required String subtitle,
    String? savings,
    bool isPopular = false,
    bool isSelected = false,
  }) {
    // Градиент для обводки "ПОПУЛЯРНО"
    const badgeGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.topRight,
      colors: [
        Color(0xFF2037E7),
        Color(0xFF58ABF5),
      ],
      stops: [0.0, 0.42],
    );
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.black : Colors.white,
                    ),
                  ),
                  if (isPopular) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: badgeGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ПОПУЛЯРНО',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (savings != null) ...[
                const SizedBox(height: 4),
                Text(
                  savings,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected
                        ? Colors.black54
                        : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: isSelected
                        ? Colors.black54
                        : Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          price,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.black : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        onPressed: _selectedPlan != null
            ? () {
                HapticFeedback.mediumImpact();
                // TODO: Реализовать покупку подписки
                Navigator.of(context).pop();
              }
            : null,
        child: Text(
          'Продолжить',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _selectedPlan != null ? Colors.black : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildTerms() {
    return Center(
      child: Column(
        children: [
          TextButton(
            onPressed: () {
              // TODO: Открыть условия использования
            },
            child: const Text(
              'Условия использования',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // TODO: Открыть политику конфиденциальности
            },
            child: const Text(
              'Политика конфиденциальности',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // TODO: Открыть политику возврата
            },
            child: const Text(
              'Политика возврата',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Подписка автоматически продлевается. Отменить можно в настройках App Store.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Цена и условия могут отличаться в зависимости от региона. Оплата будет списана с вашей учетной записи Apple ID при подтверждении покупки.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Подписка продлевается автоматически, если не отменить её по крайней мере за 24 часа до окончания текущего периода.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Пользователь может управлять подписками и отменять их в настройках своей учетной записи App Store после покупки.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Любая неиспользованная часть бесплатного пробного периода, если он предлагается, будет аннулирована, когда пользователь приобретет подписку.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  List<Widget> _buildStars(double screenWidth, double screenHeight) {
    final stars = <Widget>[];
    final rnd = math.Random(1);
    // Увеличиваем количество звезд и распределяем по всему экрану
    for (int i = 0; i < 50; i++) {
      final top = rnd.nextDouble() * screenHeight;
      final left = rnd.nextDouble() * screenWidth;
      final size = 1.5 + rnd.nextDouble() * 2.5;
      final delay = rnd.nextInt(2000);
      final delayValue = delay.toDouble();
      stars.add(Positioned(
        left: left,
        top: top,
        child: AnimatedBuilder(
          animation: _starsAnimationController,
          builder: (context, child) {
            // Постоянное мерцание с использованием sin волны
            final value = (_starsAnimationController.value * 2 * math.pi + delayValue / 100);
            final opacity = ((math.sin(value) + 1) / 2).clamp(0.3, 1.0);
            return Opacity(
              opacity: opacity,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ));
    }
    return stars;
  }

  List<Map<String, dynamic>> get _benefits => [
        {
          'icon': Icons.calendar_today,
          'title': 'Импорт календаря',
          'description': 'Импортируйте события из вашего календаря',
        },
        {
          'icon': Icons.auto_awesome,
          'title': 'ИИ в Spotlight',
          'description': 'Используйте искусственный интеллект прямо в поиске',
        },
        {
          'icon': Icons.chat_bubble_outline,
          'title': 'Доступ к Чату AI',
          'description': 'Неограниченное общение с AI-ассистентом',
        },
        {
          'icon': Icons.flag_outlined,
          'title': 'Бесконечное создание целей',
          'description': 'Создавайте неограниченное количество целей через AI',
        },
        {
          'icon': Icons.cloud_sync,
          'title': 'Синхронизация в облаке',
          'description': 'Доступ к данным на всех ваших устройствах',
        },
        {
          'icon': Icons.backup,
          'title': 'Автоматическое резервное копирование',
          'description': 'Ваши данные всегда в безопасности',
        },
        {
          'icon': Icons.analytics_outlined,
          'title': 'Расширенная аналитика',
          'description': 'Подробная статистика по задачам и целям',
        },
        {
          'icon': Icons.palette_outlined,
          'title': 'Кастомные темы',
          'description': 'Персонализируйте внешний вид приложения',
        },
        {
          'icon': Icons.file_download_outlined,
          'title': 'Экспорт данных',
          'description': 'Экспортируйте задачи и заметки в PDF и CSV',
        },
      ];
}
