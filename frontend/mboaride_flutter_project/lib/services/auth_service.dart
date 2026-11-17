import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/auth_session.dart';
import '../core/session_store.dart';

typedef JsonMap = Map<String, dynamic>;

/// Inscription et connexion (US01) sur l'API Node, puis profil métier sur l'API Python.
///
/// Après chaque connexion réussie, [AuthService] demande à l'API Python le profil de
/// l'utilisateur (`POST /api/moi/profil`) : il est créé au premier passage à partir du
/// compte Node, et c'est lui que lisent ensuite tous les écrans (demandes, conducteur...).
class AuthService {
  AuthService({http.Client? client, ApiClient? api})
    : _client = client ?? http.Client(),
      _api = api ?? ApiClient();

  final http.Client _client;
  final ApiClient _api;

  static const Duration _timeout = Duration(seconds: 10);

  Future<(int, JsonMap)> _post(String path, JsonMap body) async {
    try {
      final res = await _client
          .post(
            Uri.parse('${AppConfig.authBaseUrl}/auth$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      JsonMap data = {};
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) data = decoded;
      } on FormatException {
        // corps vide ou non JSON
      }
      return (res.statusCode, data);
    } on TimeoutException {
      throw Exception('Le serveur d\'authentification ne répond pas.');
    } on http.ClientException {
      throw Exception(
        'Impossible de joindre le serveur d\'authentification (${AppConfig.authBaseUrl}).',
      );
    }
  }

  static String _error(JsonMap data, String fallback) =>
      (data['detail'] ?? data['error'] ?? fallback).toString();

  /// 1. Création du compte : nom, e-mail, téléphone, mot de passe. Un code part par SMS.
  /// La réponse contient `phone` normalisé et, en démonstration locale, `devOtp`.
  Future<JsonMap> registerWithDetails({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final (status, data) = await _post('/register', {
      'fullName': fullName.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'password': password,
    });
    if (status == 201 || status == 200) return data;
    throw Exception(_error(data, 'Erreur lors de la création du compte'));
  }

  /// 2. Vérification du code reçu : ouvre la session et prépare le profil.
  Future<String> verifySmsOtp({required String phone, required String code}) async {
    final (status, data) = await _post('/verify-otp', {
      'phone': phone.trim(),
      'code': code.trim(),
    });
    if (status == 200 && data['token'] != null) return _openSession(data);
    throw Exception(_error(data, 'Code invalide ou expiré'));
  }

  /// 3. Nouveau code.
  Future<JsonMap> resendSmsOtp(String phone) async {
    final (status, data) = await _post('/resend-otp', {'phone': phone.trim()});
    if (status == 200) return data;
    throw Exception(_error(data, 'Impossible de renvoyer le code'));
  }

  /// 4. Connexion par e-mail ou téléphone. Un compte pas encore vérifié reçoit un
  /// nouveau code : la réponse vaut alors `{requiresOtp: true, phone: ...}`.
  Future<JsonMap> loginWithCredentials({
    required String identifier,
    required String password,
  }) async {
    final (status, data) = await _post('/login', {
      'identifier': identifier.trim(),
      'password': password,
    });
    if (status == 200 && data['token'] != null) {
      await _openSession(data);
      return data;
    }
    if (status == 403) {
      final resent = await resendSmsOtp(identifier);
      return {'requiresOtp': true, 'phone': identifier.trim(), ...resent};
    }
    throw Exception(_error(data, 'Identifiants incorrects'));
  }

  Future<String> _openSession(JsonMap data) async {
    final token = data['token'] as String;
    AuthSession.accessToken = token;
    AuthSession.refreshToken = data['refresh_token'] as String?;
    AuthSession.profile = await ensureProfile();
    await SessionStore.save();
    return token;
  }

  /// Renouvelle la session avec le jeton de rafraîchissement (usage unique côté Node).
  Future<bool> refreshSession() async {
    final refresh = AuthSession.refreshToken;
    if (refresh == null) return false;
    try {
      final (status, data) = await _post('/refresh', {'refresh_token': refresh});
      if (status != 200 || data['token'] == null) return false;
      await _openSession(data);
      return true;
    } on Object {
      return false;
    }
  }

  /// Révoque le jeton de rafraîchissement chez l'API Node ; silencieux hors connexion.
  Future<void> revoke(String refreshToken) async {
    try {
      await _post('/logout', {'refresh_token': refreshToken});
    } on Object {
      // hors ligne : la session locale est fermée de toute façon
    }
  }

  /// Profil métier (API Python), créé au premier appel.
  Future<JsonMap> ensureProfile() async {
    try {
      return await _api.post('/api/moi/profil') as JsonMap;
    } on ApiException catch (error) {
      throw Exception('Connexion réussie, mais profil indisponible : ${error.message}');
    }
  }

  /// 5. Profil affiché par l'écran « Mon profil ».
  Future<JsonMap?> getProfile() async {
    if (AuthSession.accessToken == null) return null;
    try {
      final profile = await _api.get('/api/moi/profil') as JsonMap;
      AuthSession.profile = profile;
      return profile;
    } on ApiException {
      return AuthSession.profile;
    }
  }

  /// 6. Déconnexion : la session locale est fermée tout de suite, le jeton de
  /// rafraîchissement est révoqué côté Node en arrière-plan.
  Future<void> signOut() async {
    final refresh = AuthSession.refreshToken;
    AuthSession.clear();
    unawaited(SessionStore.clear());
    if (refresh != null) unawaited(revoke(refresh));
  }
}
