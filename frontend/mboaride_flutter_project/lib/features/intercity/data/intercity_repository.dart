import '../../../core/api_client.dart';
import '../domain/intercity_trip.dart';

/// Voyages interurbains et réservation d'une place (US22).
abstract class IntercityRepository {
  /// Voyages publiés pour cette date. La recherche porte sur une date future :
  /// le voyageur réserve plusieurs jours à l'avance.
  Future<List<IntercityTrip>> trips(DateTime date);

  Future<SeatBooking> bookSeat({
    required int tripId,
    required int pickupPointId,
    required DateTime date,
    int? childId,

    /// Prix affiché au voyageur : un écart renvoie un 409 et rien n'est réservé.
    int? announcedPriceFcfa,
  });
}

class ApiIntercityRepository implements IntercityRepository {
  ApiIntercityRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<IntercityTrip>> trips(DateTime date) async {
    final body =
        await _client.get('/api/voyages?date=${isoDate(date)}') as List<dynamic>;
    return body
        .map((t) => IntercityTrip.fromJson(t as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<SeatBooking> bookSeat({
    required int tripId,
    required int pickupPointId,
    required DateTime date,
    int? childId,
    int? announcedPriceFcfa,
  }) async {
    final body = await _client.post('/api/voyages/$tripId/reservations', {
      'id_point_depart': pickupPointId,
      'date_trajet': isoDate(date),
      if (childId != null) 'id_eleve': childId,
      if (announcedPriceFcfa != null) 'prix_annonce_fcfa': announcedPriceFcfa,
    });
    return SeatBooking.fromJson(body as Map<String, dynamic>);
  }

  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String isoDate(DateTime date) => ApiIntercityRepository.isoDate(date);

/// Données simulées pour la démonstration (FAKE_API=true).
class FakeIntercityRepository implements IntercityRepository {
  final Map<int, int> _taken = {};
  int _nextBooking = 9100;

  static const List<PickupPoint> _doualaPoints = [
    PickupPoint(id: 1, label: 'Akwa, carrefour Trois Statues', time: '06:00'),
    PickupPoint(id: 2, label: 'Ndokoti', time: '06:20'),
    PickupPoint(id: 3, label: 'Péage de Douala', time: '06:45'),
  ];

  @override
  Future<List<IntercityTrip>> trips(DateTime date) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final weekend = date.weekday >= 6;
    final trips = <IntercityTrip>[
      IntercityTrip(
        id: 501,
        driver: 'Hervé Tchounga',
        from: 'Douala',
        to: 'Yaoundé',
        date: date,
        departureTime: '06:00',
        seatsLeft: 3 - (_taken[501] ?? 0),
        priceFcfa: 3500,
        points: _doualaPoints,
        comfort: const ['Climatisation', 'Non-fumeur'],
      ),
      IntercityTrip(
        id: 502,
        driver: 'Mireille Ngo Bassong',
        from: 'Douala',
        to: 'Yaoundé',
        date: date,
        departureTime: '14:30',
        seatsLeft: 1 - (_taken[502] ?? 0),
        priceFcfa: 3000,
        points: const [
          PickupPoint(id: 4, label: 'Bonabéri, rond-point', time: '14:10'),
          PickupPoint(id: 3, label: 'Péage de Douala', time: '14:50'),
        ],
        comfort: const ['Non-fumeur'],
      ),
    ];
    if (weekend) {
      trips.add(
        IntercityTrip(
          id: 503,
          driver: 'Patrice Enow',
          from: 'Douala',
          to: 'Buéa',
          date: date,
          departureTime: '08:15',
          seatsLeft: 4 - (_taken[503] ?? 0),
          priceFcfa: 2500,
          points: _doualaPoints,
          comfort: const ['Climatisation'],
        ),
      );
    }
    return trips;
  }

  @override
  Future<SeatBooking> bookSeat({
    required int tripId,
    required int pickupPointId,
    required DateTime date,
    int? childId,
    int? announcedPriceFcfa,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _taken[tripId] = (_taken[tripId] ?? 0) + 1;
    final trips = await this.trips(date);
    final trip = trips.firstWhere((t) => t.id == tripId);
    final point = trip.points.firstWhere(
      (p) => p.id == pickupPointId,
      orElse: () => trip.points.first,
    );
    return SeatBooking(
      bookingId: _nextBooking++,
      priceFcfa: trip.priceFcfa,
      pickupLabel: point.label,
      pickupTime: point.time,
      payment: 'À régler par Mobile Money avant le départ.',
    );
  }
}
