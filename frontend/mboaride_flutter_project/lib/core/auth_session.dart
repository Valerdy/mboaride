/// Session de l'utilisateur connecté.
/// À renseigner après la connexion (US01) : AuthSession.accessToken = tokens.accessToken;
class AuthSession {
  static String? accessToken;

  /// Identifiant de démonstration, envoyé dans l'en-tête `X-Utilisateur`.
  /// Sert tant que l'API Python n'exige pas le jeton de session ; à laisser nul en production.
  static int? demoUserId;
}
