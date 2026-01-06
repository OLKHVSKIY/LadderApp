import 'package:drift/drift.dart';
import '../app_database.dart';
import '../user_session.dart';

class AuthRepository {
  final AppDatabase db;

  AuthRepository(this.db);

  /// Логика: если пользователь с таким email/login есть и пароль совпадает — вход.
  /// Если нет — создаём и входим. Простой пароль хранится как есть (без хеша) для прототипа.
  Future<int> loginOrRegister(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final usersQuery =
        await (db.select(db.users)..where((u) => u.email.equals(normalized))).get();

    if (usersQuery.isEmpty) {
      final id = await db.into(db.users).insert(UsersCompanion.insert(
        email: normalized,
        passwordHash: password,
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));
      UserSession.setUser(id: id, email: normalized, name: null);
      return id;
    } else {
      final user = usersQuery.first;
      if (user.passwordHash != password) {
        throw Exception('Неверный пароль');
      }
      // Обновляем updated_at
      await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(updatedAt: Value(DateTime.now())),
      );
      UserSession.setUser(id: user.id, email: normalized, name: user.name);
      return user.id;
    }
  }

  /// Заглушки для соц-входа: создаём/находим пользователя по провайдеру.
  Future<int> socialLogin(String provider, {String? emailHint}) async {
    final email =
        emailHint?.trim().toLowerCase().isNotEmpty == true ? emailHint!.trim().toLowerCase() : '$provider-user@ladder.app';
    final usersQuery =
        await (db.select(db.users)..where((u) => u.email.equals(email))).get();

    if (usersQuery.isEmpty) {
      final id = await db.into(db.users).insert(UsersCompanion.insert(
        email: email,
        passwordHash: 'social-$provider',
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));
      UserSession.setUser(id: id, email: email, name: null);
      return id;
    } else {
      final user = usersQuery.first;
      await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(updatedAt: Value(DateTime.now())),
      );
      UserSession.setUser(id: user.id, email: email, name: user.name);
      return user.id;
    }
  }
}

