import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';

/// Jetons de session gardés dans le stockage chiffré du téléphone (Keystore Android) :
/// l'utilisateur reste connecté d'un lancement à l'autre, jusqu'à ce qu'il se déconnecte.
///
/// Toutes les opérations avalent les erreurs : sans stockage (tests, navigateur sans
/// support), l'application fonctionne simplement sans se souvenir de la session.
class SessionStore {
  SessionStore._();

  static FlutterSecureStorage storage = const FlutterSecureStorage();
  static const String _access = 'mboaride.access_token';
  static const String _refresh = 'mboaride.refresh_token';

  static Future<void> save() async {
    try {
      final access = AuthSession.accessToken;
      final refresh = AuthSession.refreshToken;
      if (access != null) await storage.write(key: _access, value: access);
      if (refresh != null) await storage.write(key: _refresh, value: refresh);
    } on Object {
      // stockage indisponible
    }
  }

  /// Recharge les jetons enregistrés dans [AuthSession] ; false s'il n'y en a pas.
  static Future<bool> load() async {
    try {
      final access = await storage.read(key: _access);
      final refresh = await storage.read(key: _refresh);
      if (access == null && refresh == null) return false;
      AuthSession.accessToken = access;
      AuthSession.refreshToken = refresh;
      return true;
    } on Object {
      return false;
    }
  }

  static Future<void> clear() async {
    try {
      await storage.delete(key: _access);
      await storage.delete(key: _refresh);
    } on Object {
      // stockage indisponible
    }
  }
}
