import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../user_session.dart';

class AuthRepository {
  final AppDatabase db;

  AuthRepository(this.db);

  /// Ключ для сохранённого id вошедшего пользователя (автологин).
  static const String _prefsKeyUserId = 'auth_current_user_id';

  Future<void> _persistUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyUserId, userId);
  }

  /// Восстанавливает сессию из сохранённого id (чтобы не вводить данные при
  /// каждом запуске). Возвращает true, если пользователь найден и активен.
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_prefsKeyUserId);
    if (userId == null) return false;
    final user = await (db.select(db.users)
          ..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
    if (user == null || user.isDeleted) {
      await prefs.remove(_prefsKeyUserId);
      return false;
    }
    UserSession.setUser(id: user.id, email: user.email, name: user.name);
    return true;
  }

  /// Полный выход: чистим сохранённую сессию и состояние в памяти.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyUserId);
    UserSession.clear();
  }

  /// Признак, что строка — это bcrypt-хеш (а не legacy plaintext-пароль).
  bool _isBcryptHash(String value) =>
      value.startsWith(r'$2a$') ||
      value.startsWith(r'$2b$') ||
      value.startsWith(r'$2y$');

  /// Логика: если пользователь с таким email/login есть и пароль совпадает — вход.
  /// Если нет — создаём и входим. Пароль хранится в виде bcrypt-хеша.
  Future<int> loginOrRegister(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final usersQuery =
        await (db.select(db.users)..where((u) => u.email.equals(normalized))).get();

    if (usersQuery.isEmpty) {
      // При регистрации проверяем длину пароля
      if (password.length < 9) {
        throw Exception('Пароль должен содержать минимум 9 символов');
      }
      final hash = BCrypt.hashpw(password, BCrypt.gensalt());
      final id = await db.into(db.users).insert(UsersCompanion.insert(
        uuid: Value(const Uuid().v4()),
        email: normalized,
        passwordHash: hash,
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));
      UserSession.setUser(id: id, email: normalized, name: null);
      await _persistUserId(id);
      return id;
    } else {
      final user = usersQuery.first;
      final stored = user.passwordHash;
      bool ok;
      if (_isBcryptHash(stored)) {
        ok = BCrypt.checkpw(password, stored);
      } else {
        // Legacy: старый аккаунт с паролем в открытом виде. Сверяем напрямую
        // и при успехе прозрачно перешифровываем в bcrypt.
        ok = stored == password;
        if (ok) {
          await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
            UsersCompanion(
              passwordHash: Value(BCrypt.hashpw(password, BCrypt.gensalt())),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }
      if (!ok) {
        throw Exception('Неверный пароль');
      }
      // Обновляем updated_at (+ проставляем uuid, если его ещё нет).
      await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(
          uuid: user.uuid == null ? Value(const Uuid().v4()) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
      UserSession.setUser(id: user.id, email: normalized, name: user.name);
      await _persistUserId(user.id);
      return user.id;
    }
  }

  /// Сохраняет имя пользователя в БД и в текущей сессии.
  Future<void> updateName(int userId, String name) async {
    final trimmed = name.trim();
    await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        name: Value(trimmed),
        updatedAt: Value(DateTime.now()),
      ),
    );
    UserSession.currentName = trimmed;
  }

  /// Заглушки для соц-входа: создаём/находим пользователя по провайдеру.
  Future<int> socialLogin(String provider, {String? emailHint}) async {
    final email =
        emailHint?.trim().toLowerCase().isNotEmpty == true ? emailHint!.trim().toLowerCase() : '$provider-user@ladder.app';
    final usersQuery =
        await (db.select(db.users)..where((u) => u.email.equals(email))).get();

    if (usersQuery.isEmpty) {
      // Соц-вход не использует пароль — кладём bcrypt-хеш от случайного значения,
      // чтобы поле никогда не совпало при попытке входа по паролю.
      final placeholder =
          BCrypt.hashpw('social-$provider-${const Uuid().v4()}', BCrypt.gensalt());
      final id = await db.into(db.users).insert(UsersCompanion.insert(
        uuid: Value(const Uuid().v4()),
        email: email,
        passwordHash: placeholder,
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));
      UserSession.setUser(id: id, email: email, name: null);
      await _persistUserId(id);
      return id;
    } else {
      final user = usersQuery.first;
      await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(
          uuid: user.uuid == null ? Value(const Uuid().v4()) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
      UserSession.setUser(id: user.id, email: email, name: user.name);
      await _persistUserId(user.id);
      return user.id;
    }
  }
}
