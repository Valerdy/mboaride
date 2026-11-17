import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'app_config.dart';
import 'auth_session.dart';

/// Itinéraire sur le réseau routier (OpenStreetMap, calculé par OSRM).
class RoadRoute {
  const RoadRoute({required this.points, required this.distanceKm, required this.durationMin});

  /// Tracé qui suit les routes, à dessiner tel quel.
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;
}

/// Calcule le tracé routier d'un trajet passant par [stops], dans l'ordre.
///
/// 1. API Node (`POST /routes/route`), qui interroge OSRM et garde les tracés en cache ;
/// 2. si elle n'a qu'une estimation (OSRM trop lent) ou ne répond pas, OSRM directement.
///
/// Renvoie null si aucun tracé routier n'est disponible : l'écran n'affiche alors pas de
/// ligne, plutôt qu'une ligne droite qui ferait croire à un itinéraire.
class RoadRouting {
  RoadRouting({http.Client? client, this.publicOsrmUrl = 'https://router.project-osrm.org'})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String publicOsrmUrl;

  static const Duration _nodeTimeout = Duration(seconds: 15);
  static const Duration _osrmTimeout = Duration(seconds: 20);

  Future<RoadRoute?> route(List<LatLng> stops) async {
    if (stops.length < 2) return null;
    return await _fromNode(stops) ?? await _fromPublicOsrm(stops);
  }

  Future<RoadRoute?> _fromNode(List<LatLng> stops) async {
    final token = AuthSession.accessToken;
    if (token == null) return null;
    Map<String, double> p(LatLng l) => {'lat': l.latitude, 'lng': l.longitude};
    try {
      final res = await _client
          .post(
            Uri.parse('${AppConfig.authBaseUrl}/routes/route'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: jsonEncode({
              'from': p(stops.first),
              'to': p(stops.last),
              'via': [for (final s in stops.sublist(1, stops.length - 1)) p(s)],
              'include_geometry': true,
            }),
          )
          .timeout(_nodeTimeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (data['estimated'] == true) return null; // ligne droite : on tente OSRM directement
      return _parse(data['geometry'], data['distance_m'], data['duration_s']);
    } on Object {
      return null;
    }
  }

  Future<RoadRoute?> _fromPublicOsrm(List<LatLng> stops) async {
    final coords = stops.map((s) => '${s.longitude},${s.latitude}').join(';');
    try {
      final res = await _client
          .get(Uri.parse('$publicOsrmUrl/route/v1/driving/$coords?overview=full&geometries=geojson&steps=false'))
          .timeout(_osrmTimeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;
      if (data['code'] != 'Ok' || routes == null || routes.isEmpty) return null;
      final r = routes.first as Map<String, dynamic>;
      return _parse(r['geometry'], r['distance'], r['duration']);
    } on Object {
      return null;
    }
  }

  static RoadRoute? _parse(Object? geometry, Object? distanceM, Object? durationS) {
    final coords = (geometry as Map<String, dynamic>?)?['coordinates'] as List<dynamic>?;
    if (coords == null || coords.length < 2) return null;
    return RoadRoute(
      points: [
        for (final c in coords.cast<List<dynamic>>())
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ],
      distanceKm: ((distanceM as num?) ?? 0) / 1000,
      durationMin: (((durationS as num?) ?? 0) / 60).round(),
    );
  }
}
