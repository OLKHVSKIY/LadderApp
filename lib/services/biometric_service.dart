import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Единая точка для блокировки приложения по Face ID / Touch ID / отпечатку.
///
/// Хранит флаг включённости в SharedPreferences (ключ `app_lock_enabled` —
/// тот же, что использует переключатель в настройках), оборачивает
/// `local_auth` и задаёт порог фонового времени, после которого нужна
/// повторная аутентификация.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  /// Ключ хранения флага блокировки (общий с settings_page).
  static const String enabledKey = 'app_lock_enabled';

  /// Сколько приложение может пробыть в фоне без повторной аутентификации.
  static const Duration lockAfter = Duration(minutes: 3);

  final LocalAuthentication _auth = LocalAuthentication();

  /// Включена ли блокировка приложения пользователем.
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  /// Сохранить флаг включённости блокировки.
  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
  }

  /// Поддерживает ли устройство биометрию или код-пароль.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Запросить аутентификацию. Возвращает true при успехе.
  ///
  /// `biometricOnly` НЕ задаём → если биометрия недоступна/не распозналась,
  /// ОС сама предложит код-пароль устройства как запасной способ.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Не сбрасывать авторизацию при сворачивании во время запроса.
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
