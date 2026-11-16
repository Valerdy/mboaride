import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'auth_session.dart';

/// Erreur renvoyée par l'API. [message] vient du champ `detail` de FastAPI.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.detail});

  final String message;
  final int? statusCode;

  /// Corps du champ `detail` quand c'est un objet, par exemple le nouveau prix
  /// renvoyé avec un code 409 lorsque le tarif a changé avant la confirmation.
  final Object? detail;

  @override
  String toString() => message;
}

/// Client HTTP de l'API MboaRide : jeton de session, décodage UTF-8, messages en français.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;
  static const Duration _timeout = Duration(seconds: 10);

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = AuthSession.accessToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final demo = AuthSession.demoUserId;
    if (demo != null) headers['X-Utilisateur'] = demo.toString();
    return headers;
  }

  Future<dynamic> get(String path) =>
      _send(() => _client.get(_uri(path), headers: _headers()));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send(
    () => _client.post(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body ?? <String, dynamic>{}),
    ),
  );

  Future<dynamic> put(String path, Map<String, dynamic> body) => _send(
    () => _client.put(_uri(path), headers: _headers(), body: jsonEncode(body)),
  );

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response response;
    try {
      response = await call().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Le serveur ne répond pas. Réessayez.');
    } on http.ClientException {
      throw ApiException(
        'Impossible de joindre le serveur. Vérifiez votre connexion.',
      );
    }
    final body = _decode(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    if (response.statusCode == 401) {
      throw ApiException(
        'Votre session a expiré, reconnectez-vous.',
        statusCode: 401,
      );
    }
    final detail = body is Map<String, dynamic> ? body['detail'] : null;
    throw ApiException(
      _message(detail, response.statusCode),
      statusCode: response.statusCode,
      detail: detail,
    );
  }

  String _message(Object? detail, int statusCode) {
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is Map && detail['message'] is String) {
      return detail['message'] as String;
    }
    return 'La requête a échoué (code $statusCode).';
  }

  dynamic _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }
}
