import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/app_config.dart';
import '../domain/ride_request.dart';
import 'place_search_service.dart';

/// Recherche de lieux avec Nominatim (OpenStreetMap), limitée à Douala.
/// Service public gratuit : usage léger uniquement (1 requête par seconde au maximum).
/// Pour la soutenance, prévoyez une liste de lieux locale en secours.
class NominatimPlaceSearch implements PlaceSearchService {
  NominatimPlaceSearch({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<Place>> search(String query) async {
    final text = query.trim();
    if (text.length < 3) return const [];

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': text,
      'format': 'jsonv2',
      'limit': '6',
      'countrycodes': 'cm',
      // gauche, haut, droite, bas
      'viewbox':
          '${AppConfig.minLng},${AppConfig.maxLat},${AppConfig.maxLng},${AppConfig.minLat}',
      'bounded': '1',
    });

    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': 'MboaRide-student-project/0.1',
              'Accept-Language': 'fr',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw PlaceSearchException(
          'La recherche est indisponible pour le moment.',
        );
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! List) return const [];
      final places = <Place>[];
      for (final item in data) {
        if (item is! Map) continue;
        final lat = double.tryParse('${item['lat']}');
        final lng = double.tryParse('${item['lon']}');
        if (lat == null || lng == null) continue;
        final label = '${item['display_name']}'.split(', ').take(2).join(', ');
        places.add(Place(name: label, lat: lat, lng: lng));
      }
      return places;
    } on TimeoutException {
      throw PlaceSearchException('La recherche est trop lente. Réessayez.');
    } on http.ClientException {
      throw PlaceSearchException(
        'Recherche impossible. Vérifiez votre connexion.',
      );
    }
  }
}
