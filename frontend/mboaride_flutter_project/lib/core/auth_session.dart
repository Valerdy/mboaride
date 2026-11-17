/// Session de l'utilisateur connecté.
class AuthSession {
  /// Jeton d'accès émis par l'API Node, accepté aussi par l'API Python.
  static String? accessToken;
  static String? refreshToken;

  /// Profil métier renvoyé par l'API Python (`/api/moi/profil`).
  static Map<String, dynamic>? profile;

  /// Identifiant de démonstration, envoyé dans l'en-tête `X-Utilisateur` par les
  /// points d'entrée `main_*_demo.dart`. À laisser nul dans l'application réelle.
  static int? demoUserId;

  static String get firstName => (profile?['prenom'] as String?) ?? '';

  static void clear() {
    accessToken = null;
    refreshToken = null;
    profile = null;
  }
}
