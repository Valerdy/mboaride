import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mboaride/core/api_client.dart';
import 'package:mboaride/core/app_config.dart';
import 'package:mboaride/core/auth_session.dart';
import 'package:mboaride/features/driver/data/driver_repository.dart';
import 'package:mboaride/features/driver/domain/driver.dart';
import 'package:mboaride/features/ride_request/data/api_ride_request_repository.dart';
import 'package:mboaride/features/ride_request/domain/ride_request.dart' as rr;
import 'package:mboaride/services/auth_service.dart';

/// Contrats entre l'application et les deux API : chemins, corps et lecture des réponses.
/// Ils doivent rester alignés sur backend/mboaride-api-node(1)/tests/mobile.test.ts
/// et backend/tests/test_parcours_complet.py.
http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  setUp(AuthSession.clear);

  group('connexion (API Node) puis profil (API Python)', () {
    test('le code vérifié ouvre la session et crée le profil métier', () async {
      final calls = <http.Request>[];
      final client = MockClient((request) async {
        calls.add(request);
        if (request.url.path == '/auth/verify-otp') {
          return _json({'token': 'jeton', 'access_token': 'jeton', 'refresh_token': 'r1'});
        }
        if (request.url.path == '/api/moi/profil') {
          return _json({'id_utilisateur': 12, 'prenom': 'Lina', 'nom': 'Ebolo', 'organisations': []});
        }
        return _json({'detail': 'inattendu'}, 404);
      });
      final auth = AuthService(client: client, api: ApiClient(client: client));

      final token = await auth.verifySmsOtp(phone: '+237690000502', code: '123456');

      expect(token, 'jeton');
      expect(calls.first.url.toString(), '${AppConfig.authBaseUrl}/auth/verify-otp');
      expect(jsonDecode(calls.first.body), {'phone': '+237690000502', 'code': '123456'});
      expect(calls.last.url.toString(), '${AppConfig.apiBaseUrl}/api/moi/profil');
      expect(calls.last.method, 'POST');
      expect(calls.last.headers['Authorization'], 'Bearer jeton');
      expect(AuthSession.firstName, 'Lina');
      expect(AuthSession.refreshToken, 'r1');
    });

    test('l\'inscription envoie nom, e-mail et téléphone, et lit l\'erreur de l\'API', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'detail': 'Un compte existe déjà avec cet identifiant'}, 409);
      });
      final auth = AuthService(client: client, api: ApiClient(client: client));
      await expectLater(
        auth.registerWithDetails(fullName: ' Lina Ebolo ', email: 'lina@entreprise-a.cm', phone: '690000502', password: 'Motdepasse1'),
        throwsA(predicate((e) => e.toString().contains('existe déjà'))),
      );
      expect(sent, {'fullName': 'Lina Ebolo', 'email': 'lina@entreprise-a.cm', 'phone': '690000502', 'password': 'Motdepasse1'});
    });

    test('un compte non vérifié reçoit un nouveau code à la connexion', () async {
      final client = MockClient((request) async => switch (request.url.path) {
        '/auth/login' => _json({'detail': 'Compte non vérifié : saisissez le code reçu'}, 403),
        '/auth/resend-otp' => _json({'message': 'ok', 'devOtp': '654321'}),
        _ => _json({}, 404),
      });
      final auth = AuthService(client: client, api: ApiClient(client: client));
      final res = await auth.loginWithCredentials(identifier: '690000502', password: 'x');
      expect(res['requiresOtp'], isTrue);
      expect(res['devOtp'], '654321');
    });
  });

  test('la demande de trajet suit le format de POST /api/demandes', () {
    final body = ApiRideRequestRepository.body(
      rr.RideRequest(
        pickup: const rr.Place(name: 'Kotto', lat: 4.072, lng: 9.766),
        dropoff: const rr.Place(name: 'Bonanjo', lat: 4.042, lng: 9.689),
        windowStart: DateTime(2026, 11, 18, 7, 20),
        windowEnd: DateTime(2026, 11, 18, 7, 55),
        maxPriceFcfa: 800,
        comforts: const {rr.Comfort.airConditioning},
      ),
    );
    expect(body, {
      'depart': {'libelle': 'Kotto', 'lat': 4.072, 'lon': 9.766},
      'arrivee': {'libelle': 'Bonanjo', 'lat': 4.042, 'lon': 9.689},
      'arrivee_au_plus_tot': '07:20',
      'arrivee_au_plus_tard': '07:55',
      'date_trajet': '2026-11-18',
      'prix_max_fcfa': 800,
      'clim_obligatoire': true,
    });
  });

  group('espace conducteur (API Python)', () {
    test('l\'équipage se lit depuis /api/moi/conducteur/equipage', () {
      final crew = ApiDriverRepository.crewFromJson({
        'id_trajet': 7, 'date_trajet': '2026-11-18', 'jour': 'Demain', 'depart': 'Logpom', 'arrivee': 'Bonanjo',
        'heure_depart': '06:50', 'arrivee_estimee': '07:41', 'places': 3,
        'depart_lat': 4.088, 'depart_lon': 9.765, 'arrivee_lat': 4.042, 'arrivee_lon': 9.689,
        'arrets': [
          {'id_reservation': 1, 'passager': 'Lina', 'lieu': 'Kotto', 'prise_en_charge': '07:02', 'arrivee': '07:41',
           'au_plus_tard': '07:55', 'prix_fcfa': 336, 'lat': 4.072, 'lon': 9.766},
        ],
      });
      expect(crew.tripId, 7);
      expect(crew.passengers, 1);
      expect(crew.stops.single.passenger, 'Lina');
      expect(crew.stops.single.latestArrival, '07:55');
      expect(crew.totalFcfa, 336);
      expect(crew.toLat, 4.042);
    });

    test('dépôt d\'une pièce, publication et absence d\'équipage', () async {
      final calls = <http.Request>[];
      final client = MockClient((request) async {
        calls.add(request);
        return switch (request.url.path) {
          '/api/moi/conducteur/agrement/documents/permis' => _json({
            'statut_agrement': 'en_verification',
            'documents': [
              {'type': 'permis', 'libelle': 'Permis de conduire', 'statut': 'valide', 'detail': null},
              {'type': 'assurance', 'libelle': 'Assurance du véhicule', 'statut': 'manquant', 'detail': null},
            ],
          }),
          '/api/moi/conducteur/equipage' => http.Response('null', 200),
          '/api/moi/conducteur/trajets/lot' => _json({
            'publies': 1, 'refuses': 0,
            'resultats': [{'rang': 0, 'publie': true, 'id_trajet': 9}],
          }, 201),
          _ => _json({'id_trajet': 9}, 201),
        };
      });
      final repository = ApiDriverRepository(client: ApiClient(client: client));

      final approval = await repository.uploadDocument('licence');
      expect(approval.documents.map((d) => (d.kind, d.status)), [
        ('licence', DocumentStatus.validated),
        ('insurance', DocumentStatus.missing),
      ]);

      await repository.publishTrip(
        const TripPlan(kind: TripKind.urban, from: 'Logpom', to: 'Bonanjo', weekdays: {5, 1, 3},
            departure: '06:50', seats: 3, maxDetourKm: 2, meetingPoint: 'Station Total de Logpom'),
      );
      final publish = calls.last;
      // Un trajet ou plusieurs : la publication passe par le lot.
      expect(publish.url.path, '/api/moi/conducteur/trajets/lot');
      final trajet = (jsonDecode(publish.body)['trajets'] as List).single as Map<String, dynamic>;
      expect(trajet, containsPair('jours_semaine', [1, 3, 5]));
      expect(trajet, containsPair('type_trajet', 'urbain'));
      expect(trajet, containsPair('point_ramassage', 'Station Total de Logpom'));
      expect(trajet.containsKey('date_trajet'), isFalse);

      expect(await repository.nextCrew(), isNull);
    });
  });
}
