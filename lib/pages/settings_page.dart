import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:drift/drift.dart' as dr;

import '../widgets/main_header.dart';
import '../widgets/sidebar.dart';
import 'tasks_page.dart';
import 'login_page.dart';
import '../data/database_instance.dart';
import '../data/user_session.dart';
import '../data/app_database.dart';

class SettingsPage extends StatefulWidget {
  final Widget Function() buildReturnPage;

  const SettingsPage({
    super.key,
    Widget Function()? buildReturnPage,
  }) : buildReturnPage = buildReturnPage ?? _defaultReturn;

  static Widget _defaultReturn() => const TasksPage();

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  bool _isSidebarOpen = false;
  late AnimationController _starsController;
  String _selectedTheme = 'Светлая';
  String _selectedLanguage = 'Русский';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _saving = false;

  void _toggleSidebar() {
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
    });
  }

  void _goBack() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: widget.buildReturnPage(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _starsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _starsController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final users =
        await (appDatabase.select(appDatabase.users)..where((u) => u.id.equals(userId))).get();
    if (users.isNotEmpty) {
      final user = users.first;
      _nameController.text = user.name ?? '';
      _emailController.text = user.email;
    } else {
      _emailController.text = UserSession.currentEmail ?? '';
    }
  }

  Future<void> _saveProfile() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите email')),
      );
      return;
    }
    setState(() {
      _saving = true;
    });
    await (appDatabase.update(appDatabase.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        name: dr.Value(name.isEmpty ? null : name),
        email: dr.Value(email),
        updatedAt: dr.Value(DateTime.now()),
      ),
    );
    UserSession.setUser(id: userId, email: email, name: name.isEmpty ? null : name);
    setState(() {
      _saving = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено')),
      );
    }
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
                  title: 'Настройки',
                  onMenuTap: _toggleSidebar,
                  onSearchTap: null,
                  onSettingsTap: null,
                  hideSearchAndSettings: true,
                  showBackButton: true,
                  onBack: _goBack,
                  onGreetingToggle: null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(15, 20, 15, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProfile(),
                        const SizedBox(height: 32),
                        _buildSubscription(),
                        const SizedBox(height: 32),
                        _buildAppearance(),
                        const SizedBox(height: 32),
                        _buildNotifications(),
                        const SizedBox(height: 32),
                        _buildAbout(),
                        const SizedBox(height: 32),
                        _buildLogout(),
                        const SizedBox(height: 20),
                        _buildSaveButton(),
                      ],
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
              _goBack();
            },
            onChatTap: () {
              // Вернуться к задачам, откуда можно в чат
              _goBack();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(''),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF5F5F5)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFF5F5F5)),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 170,
                      width: double.infinity,
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFF5F5F5),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '👤',
                                style: TextStyle(fontSize: 36),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5F5F5),
                        foregroundColor: const Color(0xFF666666),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: () {},
                      child: const Text(
                        'Изменить фото',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              _buildInputItem(
                title: 'Имя',
                subtitle: 'Как к вам обращаться',
                hint: 'Введите имя',
                controller: _nameController,
              ),
              _buildInputItem(
                title: 'Email',
                subtitle: 'Для уведомлений',
                hint: 'email@example.com',
                keyboardType: TextInputType.emailAddress,
                controller: _emailController,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubscription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('ПОДПИСКА'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Текущий тариф',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFF5F5F5),
                      foregroundColor: const Color(0xFF333333),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: () {},
                    child: const Text(
                      'Бесплатный',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSubscriptionBanner(),
          ],
        ),
      ],
    );
  }

  Widget _buildSubscriptionBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF58ABF5), Color(0xFF2037E7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // звезды как в сайдбаре (мерцают)
          ..._buildTwinklingStars(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Ladder',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: Text(
                              'Basic',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Оформи Pro, чтобы получить больше',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  elevation: 0,
                ),
                onPressed: () {},
                child: const Text(
                  'Обновить',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTwinklingStars() {
    final positions = [
      const Offset(20, 10),
      const Offset(80, 25),
      const Offset(140, 15),
      const Offset(200, 30),
      const Offset(260, 18),
      const Offset(320, 28),
      const Offset(50, 55),
      const Offset(110, 65),
      const Offset(170, 50),
      const Offset(230, 70),
      const Offset(290, 60),
      const Offset(30, 90),
      const Offset(90, 100),
      const Offset(150, 85),
      const Offset(210, 105),
      const Offset(270, 95),
      const Offset(320, 110),
    ];
    return positions
        .asMap()
        .entries
        .map((entry) => Positioned(
              left: entry.value.dx,
              top: entry.value.dy,
              child: AnimatedBuilder(
                animation: _starsController,
                builder: (context, child) {
                  final base = _starsController.value;
                  final phase = (base + entry.key * 0.07) % 1.0;
                  final sine = math.sin(phase * 2 * math.pi);
                  final opacity = (0.3 + 0.7 * (0.5 + 0.5 * sine)).clamp(0.0, 1.0);
                  final scale = 0.8 + 0.4 * (0.5 + 0.5 * sine);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(opacity),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ))
        .toList();
  }

  Widget _buildAppearance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Внешний вид'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF5F5F5)),
          ),
          child: Column(
            children: [
              _buildSelectItem(
                title: 'Тема',
                subtitle: 'Светлая или темная',
                options: const ['Светлая', 'Темная'],
                currentValue: _selectedTheme,
                onChanged: (v) => setState(() => _selectedTheme = v),
              ),
              const Divider(height: 1, color: Color(0xFFF5F5F5)),
              _buildSelectItem(
                title: 'Язык',
                subtitle: 'Язык интерфейса',
                options: const ['Русский', 'English', 'Español'],
                currentValue: _selectedLanguage,
                onChanged: (v) => setState(() => _selectedLanguage = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotifications() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Уведомления'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF5F5F5)),
          ),
          child: Column(
            children: [
              _buildToggleItem(
                title: 'Уведомления',
                subtitle: 'Получать уведомления о задачах',
              ),
              const Divider(height: 1, color: Color(0xFFF5F5F5)),
              _buildToggleItem(
                title: 'Email уведомления',
                subtitle: 'Получать уведомления на email',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAbout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('О приложении'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF5F5F5)),
          ),
          child: _buildSimpleItem(
            title: 'Версия',
            subtitle: '1.0.1',
          ),
        ),
      ],
    );
  }

  Widget _buildLogout() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF5F5F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFEEEE),
              border: Border.all(color: const Color(0xFFD60000)),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.logout,
              size: 20,
              color: Color(0xFFD60000),
            ),
          ),
          const SizedBox(height: 0, width: 14),
          const Expanded(
            child: Text(
              'Выйти из аккаунта',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFD60000),
              elevation: 0,
              side: const BorderSide(color: Color(0xFFD60000), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 220),
                  pageBuilder: (_, animation, __) => FadeTransition(
                    opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                    child: const LoginPage(),
                  ),
                ),
              );
            },
            child: const Text(
              'Выйти',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        onPressed: _saving ? null : _saveProfile,
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Сохранить изменения',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF999999),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildInputItem({
    required String title,
    required String subtitle,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    TextEditingController? controller,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF5F5F5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(color: Colors.black, fontSize: 16),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF999999)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem({
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF5F5F5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Toggle(),
        ],
      ),
    );
  }

  Widget _buildSelectItem({
    required String title,
    required String subtitle,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) {
    final key = GlobalKey();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            key: key,
            onTap: () async {
              final RenderBox box = key.currentContext!.findRenderObject() as RenderBox;
              final Offset pos = box.localToGlobal(Offset.zero);
              final Size size = box.size;
              final selected = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  pos.dx,
                  pos.dy + size.height,
                  pos.dx + size.width,
                  pos.dy,
                ),
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 6,
                items: options
                    .map((o) => PopupMenuItem<String>(
                          value: o,
                          height: 40,
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                            child: SizedBox(
                              width: 100,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(left: 15),
                                    child: Text(
                                      o,
                                      style: const TextStyle(fontSize: 15, color: Colors.black),
                                    ),
                                  ),
                                  if (o != options.last)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child: Center(
                                        child: Transform.translate(
                                          offset: const Offset(4, 0), // slight nudge to center visually
                                          child: const SizedBox(
                                            width: 90,
                                            child: Divider(
                                              height: 1,
                                              thickness: 1,
                                              color: Color(0xFFE5E5E5),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ))
                    .toList(),
              );
              if (selected != null) {
                onChanged(selected);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              constraints: const BoxConstraints(minHeight: 40),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E5E5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentValue,
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.black),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleItem({
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatefulWidget {
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _active = !_active;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 50,
        height: 30,
        decoration: BoxDecoration(
          color: _active ? Colors.black : const Color(0xFFE5E5E5),
          borderRadius: BorderRadius.circular(15),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: _active ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

