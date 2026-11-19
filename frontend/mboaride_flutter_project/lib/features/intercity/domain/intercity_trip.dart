import '../../offers/domain/offer.dart' show formatFcfa;

export '../../offers/domain/offer.dart' show formatFcfa;

/// Point de montée proposé par le conducteur sur un voyage interurbain
/// (Akwa, Ndokoti, péage de Douala...).
class PickupPoint {
  const PickupPoint({
    required this.id,
    required this.label,
    required this.time,
  });

  final int id;
  final String label;
  final String time;

  factory PickupPoint.fromJson(Map<String, dynamic> json) => PickupPoint(
    id: (json['id_point'] as num?)?.toInt() ?? 0,
    label: json['libelle'] as String? ?? '',
    time: json['heure'] as String? ?? '',
  );
}

/// Voyage interurbain publié par un conducteur agréé (US21), vu par le
/// voyageur qui cherche une place (US22).
class IntercityTrip {
  const IntercityTrip({
    required this.id,
    required this.driver,
    required this.from,
    required this.to,
    required this.date,
    required this.departureTime,
    required this.seatsLeft,
    required this.priceFcfa,
    required this.points,
    this.comfort = const [],
  });

  final int id;
  final String driver;
  final String from;
  final String to;
  final DateTime date;
  final String departureTime;
  final int seatsLeft;
  final int priceFcfa;
  final List<PickupPoint> points;
  final List<String> comfort;

  factory IntercityTrip.fromJson(Map<String, dynamic> json) => IntercityTrip(
    id: (json['id_trajet'] as num?)?.toInt() ?? 0,
    driver: json['conducteur'] as String? ?? '',
    from: json['depart_libelle'] as String? ?? '',
    to: json['arrivee_libelle'] as String? ?? '',
    date:
        DateTime.tryParse(json['date_trajet'] as String? ?? '') ??
        DateTime.now(),
    departureTime: json['heure_depart'] as String? ?? '',
    seatsLeft: (json['places_restantes'] as num?)?.toInt() ?? 0,
    priceFcfa: (json['prix_fcfa'] as num?)?.toInt() ?? 0,
    points: ((json['points_depart'] as List<dynamic>?) ?? const [])
        .map((p) => PickupPoint.fromJson(p as Map<String, dynamic>))
        .toList(growable: false),
    comfort: ((json['confort'] as List<dynamic>?) ?? const [])
        .map((c) => c.toString())
        .toList(growable: false),
  );

  String get route => '$from → $to';

  bool get isFull => seatsLeft <= 0;

  String get seatsLabel => isFull
      ? 'Complet'
      : seatsLeft == 1
      ? '1 place restante'
      : '$seatsLeft places restantes';

  String get priceLabel => formatFcfa(priceFcfa);
}

/// Confirmation d'une place interurbaine.
class SeatBooking {
  const SeatBooking({
    required this.bookingId,
    required this.priceFcfa,
    required this.pickupLabel,
    required this.pickupTime,
    this.payment = '',
    this.seats = 1,
  });

  final int seats;
  final int bookingId;
  final int priceFcfa;
  final String pickupLabel;
  final String pickupTime;
  final String payment;

  factory SeatBooking.fromJson(Map<String, dynamic> json) => SeatBooking(
    bookingId: (json['id_reservation'] as num?)?.toInt() ?? 0,
    priceFcfa: (json['prix_fcfa'] as num?)?.toInt() ?? 0,
    pickupLabel: json['point_depart'] as String? ?? '',
    pickupTime: json['heure_depart'] as String? ?? '',
    payment: json['paiement'] as String? ?? '',
    seats: (json['nb_places'] as num?)?.toInt() ?? 1,
  );
}
