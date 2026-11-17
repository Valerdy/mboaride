import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mboaride/core/auth_session.dart';
import 'package:mboaride/core/road_routing.dart';

const _logpom = LatLng(4.088, 9.765);
const _kotto = LatLng(4.072, 9.766);
const _bonanjo = LatLng(4.042, 9.689);

/// Tracé routier : quatre points qui suivent la route, et non deux points en ligne droite.
Map<String, dynamic> _road(String coordsKey) => {
  coordsKey: {
    'type': 'LineString',
    'coordinates': [
      [9.765, 4.088], [9.760, 4.080], [9.740, 4.060], [9.689, 4.042],
    ],
  },
};

void main() {
  setUp(() => AuthSession.accessToken = 'jeton');
  tearDown(AuthSession.clear);

  test('le tracé de l\'API Node passe par les étapes et suit la route', () async {
    late Map<String, dynamic> sent;
    final routing = RoadRouting(client: MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({..._road('geometry'), 'distance_m': 14200, 'duration_s': 1500, 'estimated': false}), 200);
    }));
    final route = await routing.route([_logpom, _kotto, _bonanjo]);
    expect(sent['via'], [{'lat': 4.072, 'lng': 9.766}]);
    expect(route!.points, hasLength(4));
    expect(route.distanceKm, 14.2);
    expect(route.durationMin, 25);
  });

  test('une estimation à vol d\'oiseau est écartée au profit d\'OSRM', () async {
    final urls = <String>[];
    final routing = RoadRouting(client: MockClient((request) async {
      urls.add(request.url.toString());
      if (request.url.path == '/routes/route') {
        return http.Response(jsonEncode({
          'geometry': {'type': 'LineString', 'coordinates': [[9.765, 4.088], [9.689, 4.042]]},
          'distance_m': 12000, 'duration_s': 900, 'estimated': true,
        }), 200);
      }
      return http.Response(jsonEncode({'code': 'Ok', 'routes': [{..._road('geometry'), 'distance': 13300, 'duration': 780}]}), 200);
    }));
    final route = await routing.route([_logpom, _bonanjo]);
    expect(urls.last, contains('/route/v1/driving/9.765,4.088;9.689,4.042'));
    expect(route!.points, hasLength(4));
  });

  test('sans tracé routier disponible, aucune ligne', () async {
    final routing = RoadRouting(client: MockClient((_) async => http.Response('indisponible', 503)));
    expect(await routing.route([_logpom, _bonanjo]), isNull);
  });
}
