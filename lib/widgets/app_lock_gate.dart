import 'package:flutter/material.dart';

import '../services/biometric_service.dart';
import '../l10n/app_translations.dart';
import 'lock_screen.dart';

/// Обёртка над всем приложением, которая следит за жизненным циклом и
/// показывает [LockScreen] поверх контента, когда требуется аутентификация.
///
/// Логика:
/// - холодный старт + блокировка включена → сразу запираем;
/// - уход в фон → запоминаем время;
/// - возврат из фона спустя [BiometricService.lockAfter]+ → запираем.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _authInProgress = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // При запуске приложения сразу запираем, если блокировка включена.
    WidgetsBinding.instance.addPostFrameCallback((_) => _lockIfEnabled());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Время ухода в фон фиксируем только если ещё не заперты.
      if (!_locked) _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _maybeLockOnResume();
    }
  }

  Future<void> _lockIfEnabled() async {
    if (await BiometricService.instance.isEnabled()) {
      if (mounted) setState(() => _locked = true);
      _authenticate();
    }
  }

  Future<void> _maybeLockOnResume() async {
    if (_locked) return; // уже заперто — повторно не запускаем
    final pausedAt = _pausedAt;
    if (pausedAt == null) return;
    if (DateTime.now().difference(pausedAt) < BiometricService.lockAfter) {
      return; // были в фоне меньше порога
    }
    if (!await BiometricService.instance.isEnabled()) return;
    if (mounted) setState(() => _locked = true);
    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authInProgress) return;
    setState(() => _authInProgress = true);
    final ok = await BiometricService.instance
        .authenticate(tr('Подтвердите, что это вы, чтобы продолжить'));
    if (!mounted) return;
    setState(() {
      _authInProgress = false;
      if (ok) {
        _locked = false;
        _pausedAt = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: LockScreen(
              authInProgress: _authInProgress,
              onUnlock: _authenticate,
            ),
          ),
      ],
    );
  }
}
