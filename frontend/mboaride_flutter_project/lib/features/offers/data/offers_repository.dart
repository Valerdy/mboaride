import '../../../core/api_client.dart';
import '../domain/offer.dart';

/// Erreur de confirmation : le prix a changé entre l'affichage et la validation.
class PriceChangedException implements Exception {
  PriceChangedException({
    required this.message,
    required this.newPriceFcfa,
    required this.priceLines,
  });

  final String message;
  final int newPriceFcfa;
  final List<PriceLine> priceLines;

  @override
  String toString() => message;
}

/// Offres, diagnostic et confirmation (US05, US09).
abstract class OffersRepository {
  Future<List<RideRequestSummary>> openRequests();

  Future<List<Offer>> offersFor(int rideRequestId);

  Future<Diagnostic> diagnosticFor(int rideRequestId);

  /// Élargit le cercle de la demande et renvoie les offres recalculées.
  Future<List<Offer>> widenCircle(int rideRequestId, String circleCode);

  Future<Booking> book({
    required int rideRequestId,
    required int tripId,
    required DateTime date,
    required int announcedPriceFcfa,
  });
}

class ApiOffersRepository implements OffersRepository {
  ApiOffersRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<RideRequestSummary>> openRequests() async {
    final body = await _client.get('/api/moi/demandes') as List<dynamic>;
    return body
        .map((r) => RideRequestSummary.fromJson(r as Map<String, dynamic>))
        .where((r) => r.id != 0)
        .toList();
  }

  @override
  Future<List<Offer>> offersFor(int rideRequestId) async {
    final body =
        await _client.get('/api/moi/demandes/$rideRequestId/offres')
            as List<dynamic>;
    return body.map((o) => Offer.fromJson(o as Map<String, dynamic>)).toList();
  }

  @override
  Future<Diagnostic> diagnosticFor(int rideRequestId) async {
    final body = await _client.get('/api/moi/demandes/$rideRequestId/diagnostic');
    return Diagnostic.fromJson(body as Map<String, dynamic>);
  }

  @override
  Future<List<Offer>> widenCircle(int rideRequestId, String circleCode) async {
    final body = await _client.post(
      '/api/moi/demandes/$rideRequestId/elargir',
      {'cercle_max': circleCode},
    );
    final offers = (body as Map<String, dynamic>)['offres'] as List<dynamic>;
    return offers
        .map((o) => Offer.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Booking> book({
    required int rideRequestId,
    required int tripId,
    required DateTime date,
    required int announcedPriceFcfa,
  }) async {
    try {
      final body = await _client.post('/api/reservations', {
        'id_demande': rideRequestId,
        'id_trajet': tripId,
        'date_trajet': _isoDate(date),
        'prix_annonce_fcfa': announcedPriceFcfa,
      });
      return Booking.fromJson(body as Map<String, dynamic>);
    } on ApiException catch (error) {
      final detail = error.detail;
      if (error.statusCode == 409 &&
          detail is Map &&
          detail['nouveau_prix_fcfa'] != null) {
        throw PriceChangedException(
          message: error.message,
          newPriceFcfa: (detail['nouveau_prix_fcfa'] as num).toInt(),
          priceLines: (detail['detail'] as List<dynamic>? ?? const [])
              .map((l) => PriceLine.fromJson(l as Map<String, dynamic>))
              .toList(),
        );
      }
      rethrow;
    }
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Jeu d'offres fixe, pour montrer les écrans sans serveur.
class FakeOffersRepository implements OffersRepository {
  FakeOffersRepository({this.empty = false});

  /// true : aucune offre confirmable, pour montrer le diagnostic.
  final bool empty;

  static const List<Map<String, dynamic>> _lines = [
    {
      'libelle': 'Carburant du trajet (10,7 km × 6,5 L/100 km × 840 FCFA/L)',
      'montant_fcfa': 584,
    },
    {
      'libelle': 'Partagé entre 4 occupants (conducteur compris)',
      'montant_fcfa': 146,
    },
    {'libelle': 'Prix du trajet', 'montant_fcfa': 146},
  ];

  Map<String, dynamic> _offer(
    int tripId,
    String driver,
    int price,
    String pickup,
    String arrival,
    String circle,
    bool bookable,
  ) => {
    'id_demande': 1,
    'id_trajet': tripId,
    'conducteur': driver,
    'trajet': 'Makepe → Bonanjo',
    'cercle': circle,
    'prix_fcfa': price,
    'detail': _lines,
    'distance_km': 10.7,
    'commission_fcfa': circle == 'public' ? (price * 0.1).round() : 0,
    'prix_max_fcfa': 400,
    'dans_le_budget': price <= 400,
    'prise_en_charge': pickup,
    'arrivee_estimee': arrival,
    'detour_km': 1.2,
    'horaires_compatibles': bookable,
    'confirmable': bookable && price <= 400,
    'formule': 'distance × consommation ÷ occupants',
  };

  @override
  Future<List<RideRequestSummary>> openRequests() async => [
    RideRequestSummary(
      id: 1,
      from: 'Makepe',
      to: 'Bonanjo',
      earliest: '07:20',
      latest: '08:00',
      maxPriceFcfa: 400,
      circleCode: 'partenaires',
      modeCode: 'manuel',
      singleDate: DateTime.now().add(const Duration(days: 1)),
    ),
  ];

  @override
  Future<List<Offer>> offersFor(int rideRequestId) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (empty) return [];
    return [
      Offer.fromJson(
        _offer(1, 'Aïcha', 146, '07:12', '07:30', 'organisation', true),
      ),
      Offer.fromJson(
        _offer(2, 'Carine', 169, '07:20', '07:38', 'organisation', true),
      ),
      Offer.fromJson(
        _offer(3, 'Brice', 420, '07:05', '07:41', 'public', true),
      ),
    ];
  }

  @override
  Future<Diagnostic> diagnosticFor(int rideRequestId) async =>
      Diagnostic.fromJson({
        'trajets_examines': 13,
        'offres_confirmables': 0,
        'motifs': [
          {
            'code': 'ferme',
            'libelle': "conducteur qui n'ouvre pas son trajet à votre cercle",
            'trajets': 11,
          },
          {
            'code': 'horaires',
            'libelle': 'arrivée hors de votre fenêtre ou détour trop long',
            'trajets': 2,
          },
        ],
        'suggestions': [
          {
            'action': 'elargir',
            'cercle_max': 'public',
            'offres_en_plus': 1,
            'message': 'Élargir au cercle « public » ajoute 1 offre confirmable',
          },
        ],
      });

  @override
  Future<List<Offer>> widenCircle(int rideRequestId, String circleCode) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return [
      Offer.fromJson(
        _offer(3, 'Brice', 225, '07:05', '07:41', 'public', true),
      ),
    ];
  }

  @override
  Future<Booking> book({
    required int rideRequestId,
    required int tripId,
    required DateTime date,
    required int announcedPriceFcfa,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return Booking.fromJson({
      'id_reservation': 42,
      'id_paiement': 7,
      'prix_fcfa': announcedPriceFcfa,
      'prise_en_charge': '07:12',
      'arrivee_estimee': '07:30',
      'paiement': 'en attente : payez par Mobile Money',
    });
  }
}
