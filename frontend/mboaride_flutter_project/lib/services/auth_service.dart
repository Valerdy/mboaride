import 'dart:convert';
import 'package:flutter/foundation.dart'; // <-- Ajoutez cette ligne ici
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  // Pour l'émulateur Android, 10.0.2.2 pointe sur localhost de votre PC
  static String get baseUrl {
    if (kIsWeb) {
      // Pour Chrome / Web
      return 'http://localhost:8000/auth';
    } else {
      // Pour l'Émulateur Android
      return 'http://10.0.2.2:3000/auth';
    }
  }  final _storage = const FlutterSecureStorage();

  // Inscription (Email ou Téléphone)
  Future<Map<String, dynamic>> register({
    required String identifier,
    required String password,
    required String fullName,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': identifier,
        'password': password,
        'full_name': fullName,
      }),
    );

    return {
      'statusCode': response.statusCode,
      'body': jsonDecode(response.body),
    };
  }

  // Vérification OTP (Code à 6 chiffres)
  Future<Map<String, dynamic>> verifyOtp({
    required String identifier,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': identifier,
        'code': code,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['access_token'] != null) {
        await _storage.write(key: 'access_token', value: data['access_token']);
      }
      if (data['refresh_token'] != null) {
        await _storage.write(key: 'refresh_token', value: data['refresh_token']);
      }
    }

    return {
      'statusCode': response.statusCode,
      'body': jsonDecode(response.body),
    };
  }

  // Connexion
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': identifier,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.write(key: 'access_token', value: data['access_token']);
      await _storage.write(key: 'refresh_token', value: data['refresh_token']);
    }

    return {
      'statusCode': response.statusCode,
      'body': jsonDecode(response.body),
    };
  }

  // Obtenir le profil (/me)
  Future<Map<String, dynamic>?> getProfile() async {
    final token = await _storage.read(key: 'access_token');
    if (token == null) return null;

    final response = await http.get(
      Uri.parse('$baseUrl/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  // Mise à jour du profil (Création de profil conducteur/passager)
  Future<bool> updateProfile(Map<String, dynamic> profileData) async {
    final token = await _storage.read(key: 'access_token');
    if (token == null) return false;

    final response = await http.put(
      Uri.parse('$baseUrl/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(profileData),
    );

    return response.statusCode == 200;
  }
}
