import 'package:flutter/material.dart';
import '../data/database_instance.dart';
import '../data/repositories/auth_repository.dart';
import '../data/user_session.dart';
import 'tasks_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  late final AuthRepository _authRepository;
  bool _isLoading = false;
  String? _error;
  bool _obscurePassword = true;

  late final AnimationController _animController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  AnimationController? _whiteBlockController;
  Animation<double>? _whiteBlockAnimation;

  @override
  void initState() {
    super.initState();
    _authRepository = AuthRepository(appDatabase);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
    
    // Анимация для белого блока
    _initializeWhiteBlockAnimation();
  }

  void _initializeWhiteBlockAnimation() {
    if (_whiteBlockController == null) {
      _whiteBlockController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      );
      _whiteBlockAnimation = CurvedAnimation(
        parent: _whiteBlockController!,
        curve: Curves.easeInOutCubic,
      );
      
      // Слушатели фокуса
      _emailFocusNode.addListener(() {
        if (_emailFocusNode.hasFocus || _passwordFocusNode.hasFocus) {
          _whiteBlockController?.forward();
        } else {
          _whiteBlockController?.reverse();
        }
      });
      
      _passwordFocusNode.addListener(() {
        if (_emailFocusNode.hasFocus || _passwordFocusNode.hasFocus) {
          _whiteBlockController?.forward();
        } else {
          _whiteBlockController?.reverse();
        }
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _whiteBlockController?.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loginOrRegister() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите почту и пароль');
      return;
    }
    // Проверяем длину пароля при регистрации (минимум 9 символов)
    if (password.length < 9) {
      setState(() => _error = 'Пароль должен содержать минимум 9 символов');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _authRepository.loginOrRegister(email, password);
      if (!mounted) return;
      _goToApp();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _socialLogin(String provider) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _authRepository.socialLogin(provider);
      if (!mounted) return;
      _goToApp();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToApp() {
    UserSession.currentEmail = _emailController.text.trim();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: const TasksPage(),
        ),
      ),
    );
  }

  Widget _circleButton({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: 1.0,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE5E5E5), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final top = MediaQuery.of(context).padding.top;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Определяем, является ли устройство телефоном (не планшетом и не ПК)
    // Обычно телефоны имеют ширину меньше 600px
    final isPhone = screenWidth < 600;
    
    // Инициализируем анимацию белого блока, если еще не инициализирована
    if (isPhone) {
      _initializeWhiteBlockAnimation();
    }
    
    // Вычисляем высоту черного блока
    final blackBlockHeight = top + 40 + 43 + 10 + 16 + 40; // top padding + title + spacing + subtitle + bottom padding
    
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Stack(
            children: [
              // Черный фон с мерцающими звездами (только в верхней части)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: screenHeight * 0.31, // Высота черного фона
                child: Container(
                  color: Colors.black,
                  child: _TwinklingStars(),
                ),
              ),
              // Верхняя часть с черным фоном и белым текстом
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(20, top + 40, 20, 40),
                  color: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'LADDER',
                            style: TextStyle(
                              fontSize: 49,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          AnimatedScale(
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeInOutQuad,
                            scale: 1.08,
                            child: const Text('🌿', style: TextStyle(fontSize: 45)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Войдите, чтобы продолжить',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Светлая карточка с формой входа - занимает 65% экрана
              isPhone && _whiteBlockAnimation != null
                  ? AnimatedBuilder(
                      animation: _whiteBlockAnimation!,
                      builder: (context, child) {
                        // Вычисляем позицию блока
                        // Когда поднят: почти до текста "Войдите, чтобы продолжить"
                        // Текст находится на top + 40 + 43 + 10 + 20 = top + 113
                        // Блок должен начинаться примерно на top + 150 (на 20 пикселей ниже)
                        final raisedTop = top + 150;
                        final blockHeight = screenHeight * 0.69;
                        
                        // Когда анимация = 0: блок внизу (top = screenHeight - blockHeight)
                        // Когда анимация = 1: блок поднят (top = raisedTop)
                        final normalTop = screenHeight - blockHeight;
                        final currentTop = normalTop + (raisedTop - normalTop) * _whiteBlockAnimation!.value;
                        
                        // Вычисляем высоту блока так, чтобы он всегда доходил до низа экрана
                        final currentHeight = screenHeight - currentTop;
                        
                        return Positioned(
                          top: currentTop,
                          left: 0,
                          right: 0,
                          height: currentHeight,
                          child: child!,
                        );
                      },
                      child: _buildWhiteBlockContent(context, bottom),
                    )
                  : Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: screenHeight * 0.69,
                      child: _buildWhiteBlockContent(context, bottom),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWhiteBlockContent(BuildContext context, double bottom) {
    return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(35),
                      topRight: Radius.circular(35),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 30, 20, bottom + 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildField(
                              label: 'Email',
                              controller: _emailController,
                              focusNode: _emailFocusNode,
                              hint: 'you@example.com',
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 16),
                    _buildField(
                      label: 'Пароль',
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      hint: '••••••••',
                      obscure: _obscurePassword,
                    ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                                  elevation: 6,
                                ),
                                onPressed: _isLoading ? null : _loginOrRegister,
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Войти',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                      ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                style: const TextStyle(color: Colors.red, fontSize: 13),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: const [
                                Expanded(child: Divider(color: Color(0xFFE5E5E5), thickness: 1)),
                                SizedBox(width: 12),
                                Text('или', style: TextStyle(color: Color(0xFF999999))),
                                SizedBox(width: 12),
                                Expanded(child: Divider(color: Color(0xFFE5E5E5), thickness: 1)),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _circleButton(
                                  child: Image.asset(
                                    'assets/icon/google.png',
                                    width: 22,
                                    height: 22,
                                    fit: BoxFit.contain,
                                  ),
                                  onTap: _isLoading ? () {} : () => _socialLogin('google'),
                                ),
                                _circleButton(
                                  child: Transform.translate(
                                    offset: const Offset(0, -1),
                                    child: Image.asset(
                                      'assets/icon/apple-logo.png',
                                      width: 22,
                                      height: 22,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  onTap: _isLoading ? () {} : () => _socialLogin('apple'),
                                ),
                                _circleButton(
                                  child: Image.asset(
                                    'assets/icon/email.png',
                                    width: 22,
                                    height: 22,
                                    fit: BoxFit.contain,
                                  ),
                                  onTap: _isLoading ? () {} : () => _socialLogin('email'),
                                ),
                                _circleButton(
                                  child: Image.asset(
                                    'assets/icon/microsoft.png',
                                    width: 20,
                                    height: 20,
                                    fit: BoxFit.contain,
                                  ),
                                  onTap: _isLoading ? () {} : () => _socialLogin('microsoft'),
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

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    const borderColor = Colors.black;
    return Padding(
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                obscureText: obscure,
                keyboardType: keyboardType,
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: hint,
                  hintStyle: const TextStyle(color: Color(0xFF999999), fontSize: 16),
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
                label,
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

// Виджет с мерцающими звездами
class _TwinklingStars extends StatefulWidget {
  @override
  State<_TwinklingStars> createState() => _TwinklingStarsState();
}

class _TwinklingStarsState extends State<_TwinklingStars> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  final List<Offset> _starPositions = [];

  @override
  void initState() {
    super.initState();
    // Создаем около 20 звезд
    final starCount = 30;
    _controllers = List.generate(starCount, (index) => AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1000 + (index % 5) * 300), // Разная скорость мерцания
    )..repeat(reverse: true));
    
    _animations = _controllers.map((controller) => 
      Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      )
    ).toList();
    
    // Генерируем случайные позиции для звезд
    _generateStarPositions();
  }

  void _generateStarPositions() {
    // Генерируем хаотично распределенные позиции звезд
    // Используем псевдослучайные значения для каждой координаты
    final seed = DateTime.now().millisecondsSinceEpoch;
    
    for (int i = 0; i < _controllers.length; i++) {
      // X: хаотичное распределение по всей ширине экрана (0.0 - 1.0)
      // Используем разные простые числа и операции для каждой звезды
      final xSeed = (seed + i * 137 + i * i * 17) % 10000;
      final x = ((xSeed * 7 + i * 23) % 100) / 100.0;
      
      // Y: хаотичное распределение по всей высоте черного фона (0.0 - 1.0 относительно черного блока)
      // Черный фон занимает примерно 31% экрана (100% - 69% белого блока)
      // Распределяем по всей высоте черного блока (0.0 - 1.0, потом умножим на высоту блока)
      final ySeed = (seed + i * 271 + i * i * 23) % 10000;
      final y = ((ySeed * 11 + i * 31) % 100) / 100.0; // 0.0 - 1.0 для всей высоты черного блока
      
      _starPositions.add(Offset(x, y));
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return CustomPaint(
      painter: _StarsPainter(
        starPositions: _starPositions,
        animations: _animations,
        size: size,
      ),
      child: Container(),
    );
  }
}

class _StarsPainter extends CustomPainter {
  final List<Offset> starPositions;
  final List<Animation<double>> animations;
  final Size size;

  _StarsPainter({
    required this.starPositions,
    required this.animations,
    required this.size,
  }) : super(repaint: Listenable.merge(animations));

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Черный фон занимает примерно 31% экрана (100% - 69% белого блока)
    final blackAreaHeight = size.height * 0.31;
    
    for (int i = 0; i < starPositions.length && i < animations.length; i++) {
      final position = starPositions[i];
      final opacity = animations[i].value;
      // X: по всей ширине экрана
      final x = position.dx * size.width;
      // Y: распределяем по высоте черного фона (от 0 до blackAreaHeight)
      final y = position.dy * blackAreaHeight;
      
      // Рисуем свечение (ауру) - только когда звезда яркая
      if (opacity > 0.6) {
        final glowOpacity = (opacity - 0.6) * 0.4; // Свечение появляется при яркости > 60%
        paint.color = Colors.white.withOpacity(glowOpacity);
        // Внешнее свечение (больший радиус, более прозрачное)
        canvas.drawCircle(
          Offset(x, y),
          4.0,
          paint,
        );
        // Среднее свечение
        paint.color = Colors.white.withOpacity(glowOpacity * 0.6);
        canvas.drawCircle(
          Offset(x, y),
          3.0,
          paint,
        );
      }
      
      // Рисуем саму звезду (чуть меньше размера)
      paint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(
        Offset(x, y),
        1.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

