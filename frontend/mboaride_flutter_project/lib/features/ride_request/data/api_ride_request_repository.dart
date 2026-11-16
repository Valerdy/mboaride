import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/app_config.dart';
import '../../../core/auth_session.dart';
import '../domain/ride_request.dart';
import 'ride_request_repository.dart';

/// Appelle POST {API}/ride-requests avec la session de l'utilisateur.
class ApiRideRequestRepository implements RideRequestRepository {
  ApiRideRequestRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<RideRequestResult> create(RideRequest request) async {
    final token = AuthSession.accessToken;
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/ride-requests'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 10));
      final body = _decode(response);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return RideRequestResult.fromJson(body);
      }
      if (response.statusCode == 401) {
        throw RideRequestException('Votre session a expiré, reconnectez-vous.');
      }
      throw RideRequestException(
        body['detail']?.toString() ??
            'La demande a été refusée (code ${response.statusCode}).',
      );
    } on TimeoutException {
      throw RideRequestException('Le serveur ne répond pas. Réessayez.');
    } on http.ClientException {
      throw RideRequestException(
        'Impossible de joindre le serveur. Vérifiez votre connexion.',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }
}
