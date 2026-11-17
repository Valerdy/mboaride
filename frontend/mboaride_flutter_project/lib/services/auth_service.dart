import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../core/auth_session.dart';

typedef JsonMap = Map<String, dynamic>;

class AuthService {
  // 1. Création de compte (Nom, Email, Téléphone, Mot de passe) -> déclenche le SMS OTP
  Future<JsonMap> registerWithDetails({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fullName': fullName.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'password': password,
      }),
    );

    final data = jsonDecode(res.body) as JsonMap;
    if (res.statusCode == 201 || res.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? "Erreur lors de la création du compte");
  }

  // 2. Vérification du code OTP reçu par SMS
  Future<String> verifySmsOtp({
    required String phone,
    required String code,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone.trim(),
        'code': code.trim(),
      }),
    );

    final data = jsonDecode(res.body) as JsonMap;
    if (res.statusCode == 200 && data['token'] != null) {
      final token = data['token'] as String;
      AuthSession.accessToken = token;
      return token;
    }
    throw Exception(data['error'] ?? 'Code OTP invalide ou expiré');
  }

  // 3. Renvoyer le code OTP par SMS
  Future<JsonMap> resendSmsOtp(String phone) async {
    final res = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/auth/resend-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone.trim()}),
    );
    final data = jsonDecode(res.body) as JsonMap;
    if (res.statusCode == 200) return data;
    throw Exception(data['error'] ?? "Impossible de renvoyer le SMS");
  }

  // 4. Connexion classique (Email ou Téléphone + Mot de passe)
  Future<JsonMap> loginWithCredentials({
    required String identifier,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': identifier.trim(),
        'password': password,
      }),
    );

    final data = jsonDecode(res.body) as JsonMap;
    if (res.statusCode == 200 && data['token'] != null) {
      AuthSession.accessToken = data['token'] as String;
      return data;
    }
    if (res.statusCode == 403 && data['requiresOtp'] == true) {
      return data;
    }
    throw Exception(data['error'] ?? 'Identifiants incorrects');
  }

  // 5. Récupération du profil utilisateur
  Future<JsonMap?> getProfile() async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as JsonMap;
      }
    } catch (_) {}
    return null;
  }

  // 6. Mise à jour du profil utilisateur
  Future<bool> updateProfile(JsonMap payload) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) return false;
    try {
      final res = await http.put(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}