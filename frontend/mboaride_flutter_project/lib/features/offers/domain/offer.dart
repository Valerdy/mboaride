/// Offres reçues des agents conducteurs et prix détaillé (US05, US09).
library;

/// 15400 -> « 15 400 FCFA »
String formatFcfa(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}$buffer FCFA';
}

/// Une ligne du calcul du prix : carburant, péage, partage, commission, total.
class PriceLine {
  const PriceLine({required this.label, required this.amountFcfa});

  final String label;
  final int amountFcfa;

  factory PriceLine.fromJson(Map<String, dynamic> json) => PriceLine(
    label: json['libelle'] as String? ?? '',
    amountFcfa: (json['montant_fcfa'] as num?)?.toInt() ?? 0,
  );
}

/// Proposition d'un conducteur pour une demande donnée.
class Offer {
  const Offer({
    required this.rideRequestId,
    required this.tripId,
    required this.driver,
    required this.route,
    required this.circle,
    required this.priceFcfa,
    required this.priceLines,
    required this.distanceKm,
    required this.commissionFcfa,
    required this.maxPriceFcfa,
    required this.withinBudget,
    required this.pickupTime,
    required this.arrivalTime,
    required this.detourKm,
    required this.scheduleFits,
    required this.bookable,
    required this.formula,
  });

  final int rideRequestId;
  final int tripId;
  final String driver;
  final String route;
  final String circle;
  final int priceFcfa;
  final List<PriceLine> priceLines;
  final double distanceKm;
  final int commissionFcfa;
  final int maxPriceFcfa;
  final bool withinBudget;
  final String? pickupTime;
  final String? arrivalTime;
  final double? detourKm;
  final bool scheduleFits;
  final bool bookable;
  final String formula;

  factory Offer.fromJson(Map<String, dynamic> json) => Offer(
    rideRequestId: (json['id_demande'] as num?)?.toInt() ?? 0,
    tripId: (json['id_trajet'] as num?)?.toInt() ?? 0,
    driver: json['conducteur'] as String? ?? 'Conducteur',
    route: json['trajet'] as String? ?? '',
    circle: json['cercle'] as String? ?? 'organisation',
    priceFcfa: (json['prix_fcfa'] as num?)?.toInt() ?? 0,
    priceLines: (json['detail'] as List<dynamic>? ?? const [])
        .map((line) => PriceLine.fromJson(line as Map<String, dynamic>))
        .toList(),
    distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
    commissionFcfa: (json['commission_fcfa'] as num?)?.toInt() ?? 0,
    maxPriceFcfa: (json['prix_max_fcfa'] as num?)?.toInt() ?? 0,
    withinBudget: json['dans_le_budget'] == true,
    pickupTime: json['prise_en_charge'] as String?,
    arrivalTime: json['arrivee_estimee'] as String?,
    detourKm: (json['detour_km'] as num?)?.toDouble(),
    scheduleFits: json['horaires_compatibles'] == true,
    bookable: json['confirmable'] == true,
    formula: json['formule'] as String? ?? '',
  );

  /// Libellé du cercle tel qu'il est montré au passager.
  String get circleLabel => const {
    'organisation': 'Collègue',
    'partenaires': 'Partenaire',
    'public': 'Public vérifié',
  }[circle] ?? circle;

  /// Pourquoi cette offre ne peut pas être confirmée, ou null si elle le peut.
  String? get blockedReason {
    if (!scheduleFits) {
      return 'Arrivée hors de votre fenêtre, ou détour trop long';
    }
    if (!withinBudget) {
      return 'Au-dessus de votre maximum de ${formatFcfa(maxPriceFcfa)}';
    }
    return null;
  }
}

/// Un motif de refus, agrégé sur les trajets examinés.
class RejectionReason {
  const RejectionReason({
    required this.code,
    required this.label,
    required this.trips,
  });

  final String code;
  final String label;
  final int trips;

  factory RejectionReason.fromJson(Map<String, dynamic> json) =>
      RejectionReason(
        code: json['code'] as String? ?? '',
        label: json['libelle'] as String? ?? '',
        trips: (json['trajets'] as num?)?.toInt() ?? 0,
      );
}

/// Ce qui débloquerait la demande : élargir le cercle, relever le budget,
/// élargir la fenêtre d'arrivée.
class Suggestion {
  const Suggestion({
    required this.action,
    required this.message,
    this.circleCode,
    this.extraOffers,
    this.priceFcfa,
  });

  final String action;
  final String message;
  final String? circleCode;
  final int? extraOffers;
  final int? priceFcfa;

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
    action: json['action'] as String? ?? '',
    message: json['message'] as String? ?? '',
    circleCode: json['cercle_max'] as String?,
    extraOffers: (json['offres_en_plus'] as num?)?.toInt(),
    priceFcfa: (json['prix_max_fcfa'] as num?)?.toInt(),
  );
}

/// Explication affichée quand aucune offre ne convient.
class Diagnostic {
  const Diagnostic({
    required this.examinedTrips,
    required this.bookableOffers,
    required this.reasons,
    required this.suggestions,
  });

  final int examinedTrips;
  final int bookableOffers;
  final List<RejectionReason> reasons;
  final List<Suggestion> suggestions;

  factory Diagnostic.fromJson(Map<String, dynamic> json) => Diagnostic(
    examinedTrips: (json['trajets_examines'] as num?)?.toInt() ?? 0,
    bookableOffers: (json['offres_confirmables'] as num?)?.toInt() ?? 0,
    reasons: (json['motifs'] as List<dynamic>? ?? const [])
        .map((r) => RejectionReason.fromJson(r as Map<String, dynamic>))
        .toList(),
    suggestions: (json['suggestions'] as List<dynamic>? ?? const [])
        .map((s) => Suggestion.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

/// Réservation confirmée.
class Booking {
  const Booking({
    required this.bookingId,
    required this.paymentId,
    required this.priceFcfa,
    required this.pickupTime,
    required this.arrivalTime,
    required this.payment,
  });

  final int bookingId;
  final int? paymentId;
  final int priceFcfa;
  final String? pickupTime;
  final String? arrivalTime;
  final String payment;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
    bookingId: (json['id_reservation'] as num?)?.toInt() ?? 0,
    paymentId: (json['id_paiement'] as num?)?.toInt(),
    priceFcfa: (json['prix_fcfa'] as num?)?.toInt() ?? 0,
    pickupTime: json['prise_en_charge'] as String?,
    arrivalTime: json['arrivee_estimee'] as String?,
    payment: json['paiement'] as String? ?? '',
  );
}

/// Demande de trajet ouverte, telle que l'API la résume.
class RideRequestSummary {
  const RideRequestSummary({
    required this.id,
    required this.from,
    required this.to,
    required this.earliest,
    required this.latest,
    required this.maxPriceFcfa,
    required this.circleCode,
    required this.modeCode,
    this.singleDate,
  });

  final int id;
  final String from;
  final String to;
  final String earliest;
  final String latest;
  final int maxPriceFcfa;
  final String circleCode;
  final String modeCode;
  final DateTime? singleDate;

  factory RideRequestSummary.fromJson(Map<String, dynamic> json) =>
      RideRequestSummary(
        id: (json['id_demande'] as num?)?.toInt() ?? 0,
        from: json['depart_libelle'] as String? ?? '',
        to: json['arrivee_libelle'] as String? ?? '',
        earliest: json['arrivee_au_plus_tot'] as String? ?? '',
        latest: json['arrivee_au_plus_tard'] as String? ?? '',
        maxPriceFcfa: (json['prix_max_fcfa'] as num?)?.toInt() ?? 0,
        circleCode: json['cercle_max'] as String? ?? 'organisation',
        modeCode: json['mode_reservation'] as String? ?? 'manuel',
        singleDate: DateTime.tryParse(json['date_unique'] as String? ?? ''),
      );

  String get label => '$from → $to';

  /// Date proposée pour la réservation : celle de la demande, sinon le prochain
  /// jour ouvré.
  DateTime dateFor(DateTime now) {
    if (singleDate != null) return singleDate!;
    var day = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    while (day.weekday > DateTime.friday) {
      day = day.add(const Duration(days: 1));
    }
    return day;
  }
}
