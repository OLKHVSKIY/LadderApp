class UserSession {
  static int? currentUserId;
  static String? currentEmail;
  static String? currentName;

  static void setUser({required int id, required String email, String? name}) {
    currentUserId = id;
    currentEmail = email;
    currentName = name;
  }

  static void clear() {
    currentUserId = null;
    currentEmail = null;
    currentName = null;
  }
}

