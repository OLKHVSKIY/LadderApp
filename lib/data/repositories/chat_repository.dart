import 'package:drift/drift.dart' as dr;
import '../app_database.dart';
import '../user_session.dart';

class ChatRepository {
  final AppDatabase db;

  ChatRepository(this.db);

  /// Сохранить сообщение в БД
  Future<int> saveMessage({
    required String role, // 'user' или 'assistant'
    required String content,
  }) async {
    final userId = UserSession.currentUserId;
    if (userId == null) throw Exception('Нет авторизованного пользователя');

    return await db.into(db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            userId: userId,
            role: role,
            content: content,
            createdAt: dr.Value(DateTime.now()),
          ),
        );
  }

  /// Загрузить все сообщения текущего пользователя
  Future<List<ChatMessage>> loadMessages() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return [];

    final messages = await (db.select(db.chatMessages)
          ..where((m) => m.userId.equals(userId))
          ..orderBy([(m) => dr.OrderingTerm.asc(m.createdAt)]))
        .get();

    return messages;
  }

  /// Удалить все сообщения текущего пользователя
  Future<void> clearMessages() async {
    final userId = UserSession.currentUserId;
    if (userId == null) return;

    await (db.delete(db.chatMessages)
          ..where((m) => m.userId.equals(userId)))
        .go();
  }

  /// Удалить сообщения пользователя (для очистки при выходе)
  Future<void> deleteUserMessages(int userId) async {
    await (db.delete(db.chatMessages)
          ..where((m) => m.userId.equals(userId)))
        .go();
  }
}

