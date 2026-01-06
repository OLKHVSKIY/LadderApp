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

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late final AuthRepository _authRepository;
  bool _isLoading = false;
  String? _error;

  late final AnimationController _animController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

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
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginOrRegister() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите почту и пароль');
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 46, 20, bottom + 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'LADDER',
                          style: TextStyle(
                            fontSize: 43,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 10),
                        AnimatedScale(
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeInOutQuad,
                          scale: 1.08,
                          child: const Text('🌿', style: TextStyle(fontSize: 40)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Войдите, чтобы продолжить',
                      style: TextStyle(fontSize: 16, color: Color(0xFF666666)),
                    ),
                    const SizedBox(height: 60),
                    _buildField(
                      label: 'Email',
                      controller: _emailController,
                      hint: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      label: 'Пароль',
                      controller: _passwordController,
                      hint: '••••••••',
                      obscure: true,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
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

