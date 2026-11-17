/// Espace conducteur : modèles et calculs (wireframes « MboaRide - Wireframes conducteur »).
///
/// Les calculs de prix reprennent la règle du produit du moteur d'agents
/// (`agents/mboaride_agents/pricing.py`, `PRODUCT_POLICY`) : le coût du trajet commun
/// est partagé entre les occupants à bord, conducteur compris ; MboaRide prélève 10 %
/// du prix sur chaque trajet, prix arrondi aux 25 FCFA supérieurs, 100 FCFA au moins.
library;

import '../../payment/domain/payment.dart' show CourseStatus;

export '../../payment/domain/payment.dart' show CourseStatus;

/// Prix officiel du super depuis février 2024 (FCFA par litre).
const int fuelPricePerLitre = 840;

/// Commission MboaRide, prélevée sur tous les trajets.
const double commissionRate = 0.10;

/// Pas d'arrondi du prix (pièces de 25 FCFA) et prix minimal d'un trajet.
const int priceStepFcfa = 25;
const int minFareFcfa = 100;

/// Prix payé par le passager pour une part [share] du conducteur : commission de 10 %
/// comprise, arrondi aux 25 FCFA supérieurs (même calcul que le moteur).
int passengerPrice(int share) {
  final raw = (share * 10 / 9 / priceStepFcfa).ceil() * priceStepFcfa;
  return raw < minFareFcfa ? minFareFcfa : raw;
}

/// Arrondi au FCFA le plus proche, demi vers le haut (comme le moteur).
int roundHalfUp(double value) => (value + 0.5).floor();

// --- Agrément --------------------------------------------------------------------------

enum DocumentStatus { validated, pending, missing }

class DriverDocument {
  const DriverDocument({
    required this.kind,
    required this.label,
    required this.status,
    this.detail,
  });

  /// Identifiant technique : identity, licence, criminal_record, insurance.
  final String kind;
  final String label;
  final DocumentStatus status;

  /// Précision affichée sous le nom (date de validité, date de dépôt...).
  final String? detail;

  DriverDocument copyWith({DocumentStatus? status, String? detail}) =>
      DriverDocument(
        kind: kind,
        label: label,
        status: status ?? this.status,
        detail: detail ?? this.detail,
      );
}

/// Les quatre pièces de l'agrément : aucun trajet ne peut être publié avant.
class Approval {
  const Approval(this.documents);

  final List<DriverDocument> documents;

  int get validatedCount =>
      documents.where((d) => d.status == DocumentStatus.validated).length;

  bool get approved =>
      documents.isNotEmpty && validatedCount == documents.length;

  /// Toutes les pièces sont déposées (validées ou en vérification).
  bool get allSubmitted =>
      documents.every((d) => d.status != DocumentStatus.missing);
}

// --- Véhicule et confort -----------------------------------------------------------------

enum Comfort {
  airConditioning('Climatisation'),
  nonSmoking('Non-fumeur'),
  quiet('Trajet silencieux'),
  luggage('Coffre pour bagages');

  const Comfort(this.label);
  final String label;
}

class Vehicle {
  const Vehicle({
    required this.model,
    required this.plate,
    required this.seats,
    required this.consumptionL100,
    required this.comfort,
  });

  final String model;
  final String plate;

  /// Places offertes aux passagers, hors conducteur.
  final int seats;
  final double consumptionL100;
  final Set<Comfort> comfort;

  static const int minSeats = 1;
  static const int maxSeats = 6;

  Vehicle copyWith({
    String? model,
    String? plate,
    int? seats,
    double? consumptionL100,
    Set<Comfort>? comfort,
  }) => Vehicle(
    model: model ?? this.model,
    plate: plate ?? this.plate,
    seats: seats ?? this.seats,
    consumptionL100: consumptionL100 ?? this.consumptionL100,
    comfort: comfort ?? this.comfort,
  );

  /// Message d'erreur à afficher, ou null si le véhicule est valide.
  String? get error {
    if (model.trim().isEmpty) return 'Indiquez la marque et le modèle.';
    if (plate.trim().isEmpty) return 'Indiquez l\'immatriculation.';
    if (seats < minSeats || seats > maxSeats) {
      return 'Entre $minSeats et $maxSeats places.';
    }
    if (consumptionL100 < 3 || consumptionL100 > 25) {
      return 'Consommation entre 3 et 25 L/100 km.';
    }
    return null;
  }
}

// --- Cercles et règles -------------------------------------------------------------------

class DriverRules {
  const DriverRules({
    required this.colleagues,
    required this.partners,
    required this.publicNetwork,
    required this.acceptsStudents,
    required this.minPriceFcfa,
    required this.automatic,
  });

  final bool colleagues;
  final bool partners;
  final bool publicNetwork;

  /// Élèves de 12 ans et plus, avec autorisation parentale.
  final bool acceptsStudents;

  /// Prix plancher par passager : en dessous, l'agent ne propose pas de place.
  final int minPriceFcfa;

  /// true : l'agent propose une place à chaque passager compatible.
  final bool automatic;

  DriverRules copyWith({
    bool? colleagues,
    bool? partners,
    bool? publicNetwork,
    bool? acceptsStudents,
    int? minPriceFcfa,
    bool? automatic,
  }) => DriverRules(
    colleagues: colleagues ?? this.colleagues,
    partners: partners ?? this.partners,
    publicNetwork: publicNetwork ?? this.publicNetwork,
    acceptsStudents: acceptsStudents ?? this.acceptsStudents,
    minPriceFcfa: minPriceFcfa ?? this.minPriceFcfa,
    automatic: automatic ?? this.automatic,
  );

  String? get error {
    if (!colleagues && !partners && !publicNetwork) {
      return 'Acceptez au moins un cercle de passagers.';
    }
    if (minPriceFcfa < 0) return 'Le prix minimal ne peut pas être négatif.';
    return null;
  }
}

// --- Publication d'un trajet -------------------------------------------------------------

enum TripKind { urban, interurban }

const List<String> weekdayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const List<String> weekdayNames = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

class TripPlan {
  const TripPlan({
    required this.kind,
    required this.from,
    required this.to,
    required this.weekdays,
    required this.departure,
    required this.seats,
    required this.maxDetourKm,
    this.tollsFcfa = 0,
    this.pickupPoints = const [],
    this.meetingPoint = '',
    this.meetingInstructions = '',
    this.waitMinutes = 5,
  });

  final TripKind kind;
  final String from;
  final String to;

  /// Jours du trajet régulier, 1 (lundi) à 7 (dimanche).
  final Set<int> weekdays;

  /// Heure de départ « HH:MM ».
  final String departure;
  final int seats;
  final double maxDetourKm;
  final int tollsFcfa;

  /// Interurbain : points de départ possibles dans la ville.
  final List<String> pickupPoints;

  /// Point de ramassage précis (« Station Total de Logpom, côté boulangerie »), consignes
  /// (« berline grise, je klaxonne deux fois ») et attente maximale.
  final String meetingPoint;
  final String meetingInstructions;
  final int waitMinutes;

  TripPlan copyWith({
    TripKind? kind,
    String? from,
    String? to,
    Set<int>? weekdays,
    String? departure,
    int? seats,
    double? maxDetourKm,
    int? tollsFcfa,
    List<String>? pickupPoints,
    String? meetingPoint,
    String? meetingInstructions,
    int? waitMinutes,
  }) => TripPlan(
    kind: kind ?? this.kind,
    from: from ?? this.from,
    to: to ?? this.to,
    weekdays: weekdays ?? this.weekdays,
    departure: departure ?? this.departure,
    seats: seats ?? this.seats,
    maxDetourKm: maxDetourKm ?? this.maxDetourKm,
    tollsFcfa: tollsFcfa ?? this.tollsFcfa,
    pickupPoints: pickupPoints ?? this.pickupPoints,
    meetingPoint: meetingPoint ?? this.meetingPoint,
    meetingInstructions: meetingInstructions ?? this.meetingInstructions,
    waitMinutes: waitMinutes ?? this.waitMinutes,
  );

  static final RegExp _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  String? get error {
    if (from.trim().isEmpty || to.trim().isEmpty) {
      return 'Indiquez le départ et l\'arrivée.';
    }
    if (kind == TripKind.urban && weekdays.isEmpty) {
      return 'Choisissez au moins un jour.';
    }
    if (!_time.hasMatch(departure)) return 'Heure au format HH:MM, par exemple 06:45.';
    if (seats < Vehicle.minSeats || seats > Vehicle.maxSeats) {
      return 'Entre ${Vehicle.minSeats} et ${Vehicle.maxSeats} places.';
    }
    if (tollsFcfa < 0) return 'Les péages ne peuvent pas être négatifs.';
    if (meetingPoint.trim().length < 5) {
      return 'Précisez le point de ramassage (lieu exact et repère), pour que vos passagers vous trouvent.';
    }
    if (waitMinutes < 0 || waitMinutes > 30) return 'Attente entre 0 et 30 minutes.';
    return null;
  }
}

/// Prix d'un passager selon le nombre de passagers à bord (règle du produit, hors détour).
class PriceEstimate {
  PriceEstimate._({
    required this.distanceKm,
    required this.fuelFcfa,
    required this.tollsFcfa,
    required this.withCommission,
    required this.perPassengerByOccupancy,
  });

  /// Le carburant du trajet commun (et les péages) est partagé entre le conducteur et
  /// les passagers à bord ; le prix comprend la commission MboaRide de 10 %.
  factory PriceEstimate.compute({
    required double distanceKm,
    required double consumptionL100,
    required int seats,
    int tollsFcfa = 0,
    bool withCommission = false,
  }) {
    final fuel = roundHalfUp(distanceKm * consumptionL100 / 100 * fuelPricePerLitre);
    final prices = <int>[
      for (var passengers = 1; passengers <= seats; passengers++)
        _withCommission(
          roundHalfUp((fuel + tollsFcfa) / (1 + passengers)),
          withCommission,
        ),
    ];
    return PriceEstimate._(
      distanceKm: distanceKm,
      fuelFcfa: fuel,
      tollsFcfa: tollsFcfa,
      withCommission: withCommission,
      perPassengerByOccupancy: prices,
    );
  }

  static int _withCommission(int share, bool apply) => passengerPrice(share);

  final double distanceKm;
  final int fuelFcfa;
  final int tollsFcfa;
  final bool withCommission;

  /// Indice 0 : un passager à bord ; dernier indice : voiture pleine.
  final List<int> perPassengerByOccupancy;

  int get alonePrice => perPassengerByOccupancy.first;
  int get fullPrice => perPassengerByOccupancy.last;
}

// --- Activité de l'agent -------------------------------------------------------------------

enum AgentEventKind { booked, offerSent, declined }

/// Motifs de refus du protocole (DECLINE.reason), en français.
const Map<String, String> declineReasonLabels = {
  'DETOUR_TOO_LONG': 'détour trop long',
  'OUTSIDE_WINDOW': 'hors fenêtre',
  'NO_SEAT': 'plus de place',
  'PRICE_TOO_HIGH': 'prix trop élevé pour le passager',
  'COMFORT_MISMATCH': 'confort obligatoire absent',
  'CIRCLE_NOT_ACCEPTED': 'cercle non accepté',
  'STUDENT_NOT_ALLOWED': 'élève non accepté',
  'DRIVER_NOT_APPROVED': 'agrément manquant',
  'NO_ROUTE': 'aucun itinéraire',
};

class AgentEvent {
  const AgentEvent({
    required this.kind,
    required this.title,
    required this.detail,
    this.reasonCode,
  });

  final AgentEventKind kind;

  /// Passager et trajet, ou motif du refus.
  final String title;
  final String detail;

  /// Code du protocole pour un refus (DETOUR_TOO_LONG...).
  final String? reasonCode;

  String get heading => switch (kind) {
    AgentEventKind.booked => 'Réservation confirmée · $title',
    AgentEventKind.offerSent => 'Offre envoyée · $title',
    AgentEventKind.declined =>
      'Refus automatique · ${declineReasonLabels[reasonCode] ?? title}',
  };
}

// --- Équipage, retard, annulation -----------------------------------------------------------

class CrewStop {
  const CrewStop({
    required this.passenger,
    required this.place,
    required this.pickupTime,
    required this.arrivalTime,
    required this.latestArrival,
    required this.priceFcfa,
    this.lat,
    this.lng,
    this.lastName,
    this.phone,
    this.destination,
    this.rating,
    this.ratingCount = 0,
    this.student = false,
    this.endValidated = false,
  });

  /// Prénom du passager.
  final String passenger;
  final String place;

  /// Fiche du passager pour le conducteur : nom, téléphone, destination, note moyenne.
  final String? lastName;
  final String? phone;
  final String? destination;
  final double? rating;
  final int ratingCount;
  final bool student;

  /// Le passager a validé la fin de la course.
  final bool endValidated;

  String get fullName => lastName == null || lastName!.isEmpty ? passenger : '$passenger $lastName';

  /// Heures « HH:MM ».
  final String pickupTime;
  final String arrivalTime;

  /// Fin de la fenêtre d'arrivée du passager.
  final String latestArrival;
  final int priceFcfa;
  final double? lat;
  final double? lng;
}

class Crew {
  const Crew({
    required this.tripId,
    required this.date,
    required this.dayLabel,
    required this.departure,
    required this.from,
    required this.to,
    required this.seatsTotal,
    required this.stops,
    required this.arrival,
    this.fromLat,
    this.fromLng,
    this.toLat,
    this.toLng,
    this.meetingPoint,
    this.meetingInstructions,
    this.waitMinutes = 5,
    this.courseStatus = CourseStatus.notStarted,
  });

  final int tripId;

  /// Point de ramassage annoncé aux passagers (null : pas encore précisé).
  final String? meetingPoint;
  final String? meetingInstructions;
  final int waitMinutes;
  final CourseStatus courseStatus;

  /// Date ISO du trajet (AAAA-MM-JJ) et libellé affiché (« Demain »).
  final String date;
  final String dayLabel;
  final String departure;
  final String from;
  final String to;
  final int seatsTotal;
  final List<CrewStop> stops;
  final String arrival;
  final double? fromLat;
  final double? fromLng;
  final double? toLat;
  final double? toLng;

  int get passengers => stops.length;
  int get totalFcfa => stops.fold(0, (sum, s) => sum + s.priceFcfa);
  bool get full => passengers >= seatsTotal;
}

/// Un passager pendant la course : a-t-il validé la fin, quelle note a-t-il donnée ?
class CoursePassenger {
  const CoursePassenger({required this.firstName, this.lastName, this.validated = false, this.rating});

  final String firstName;
  final String? lastName;
  final bool validated;
  final int? rating;
}

/// État de la course (démarrée, arrivée, réglée) et de son règlement au conducteur.
class CourseState {
  const CourseState({
    required this.status,
    required this.passengers,
    required this.totalPaidFcfa,
    required this.commissionFcfa,
    required this.driverAmountFcfa,
    required this.paidOut,
  });

  final CourseStatus status;
  final List<CoursePassenger> passengers;
  final int totalPaidFcfa;

  /// Commission MboaRide (10 %) et part versée au conducteur.
  final int commissionFcfa;
  final int driverAmountFcfa;

  /// Tout l'équipage a validé : l'argent est dans le portefeuille du conducteur.
  final bool paidOut;

  int get validations => passengers.where((p) => p.validated).length;

  List<String> get waitingFor => [for (final p in passengers) if (!p.validated) p.firstName];

  factory CourseState.fromJson(Map<String, dynamic> json) => CourseState(
    status: CourseStatus.fromCode(json['statut'] as String?),
    passengers: [
      for (final p in (json['passagers'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
        CoursePassenger(
          firstName: p['prenom'] as String? ?? '',
          lastName: p['nom'] as String?,
          validated: p['fin_validee'] == true,
          rating: (p['note'] as num?)?.toInt(),
        ),
    ],
    totalPaidFcfa: (json['total_paye_fcfa'] as num?)?.toInt() ?? 0,
    commissionFcfa: (json['commission_fcfa'] as num?)?.toInt() ?? 0,
    driverAmountFcfa: (json['montant_conducteur_fcfa'] as num?)?.toInt() ?? 0,
    paidOut: json['verse'] == true,
  );
}

int toMinutes(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String fromMinutes(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// « 06:45 » -> « 6 h 45 ».
String frenchTime(String hhmm) {
  final minutes = toMinutes(hhmm);
  final m = minutes % 60;
  return '${minutes ~/ 60} h ${m.toString().padLeft(2, '0')}';
}

class DelayImpact {
  const DelayImpact({
    required this.stop,
    required this.newPickup,
    required this.newArrival,
  });

  final CrewStop stop;
  final String newPickup;
  final String newArrival;

  bool get withinWindow =>
      toMinutes(newArrival) <= toMinutes(stop.latestArrival);
}

/// Effet d'un retard sur chaque passager : ceux qui sortent de leur fenêtre pourront
/// se retirer et relancer une recherche (protocole : DELAY_REPORTED, ETA_UPDATED).
List<DelayImpact> delayImpacts(Crew crew, int delayMinutes) => [
  for (final stop in crew.stops)
    DelayImpact(
      stop: stop,
      newPickup: fromMinutes(toMinutes(stop.pickupTime) + delayMinutes),
      newArrival: fromMinutes(toMinutes(stop.arrivalTime) + delayMinutes),
    ),
];

enum CancelReason {
  personal('Imprévu personnel', 'DRIVER_CANCELLED'),
  breakdown('Panne du véhicule', 'VEHICLE_BREAKDOWN'),
  other('Autre motif', 'OTHER');

  const CancelReason(this.label, this.protocolCode);
  final String label;

  /// Motif du message TRIP_CANCELLED.
  final String protocolCode;
}

class ReassignmentOutcome {
  const ReassignmentOutcome({
    required this.passenger,
    required this.reassigned,
    this.newDriver,
    this.offersAvailable = 0,
  });

  final String passenger;
  final bool reassigned;
  final String? newDriver;
  final int offersAvailable;
}

class CancellationResult {
  const CancellationResult({
    required this.cancelledBookings,
    required this.outcomes,
  });

  final int cancelledBookings;
  final List<ReassignmentOutcome> outcomes;

  int get reassignedCount => outcomes.where((o) => o.reassigned).length;
}

// --- Gains --------------------------------------------------------------------------------------

class Payment {
  const Payment({
    required this.dateLabel,
    required this.route,
    required this.passengers,
    required this.amountFcfa,
    required this.received,
    this.commissionFcfa = 0,
  });

  final String dateLabel;
  final String route;
  final int passengers;
  final int amountFcfa;

  /// « Reçu » : tout l'équipage a validé la fin de la course et l'argent est versé.
  final bool received;

  /// Commission MboaRide (10 %) déjà déduite de [amountFcfa].
  final int commissionFcfa;
}

/// Objectif du document de vision : au moins la moitié des frais couverts.
const double coverageTarget = 0.5;

class Earnings {
  const Earnings({
    required this.monthLabel,
    required this.lastTripReceivedFcfa,
    required this.lastTripFuelFcfa,
    required this.payments,
  });

  final String monthLabel;
  final int lastTripReceivedFcfa;
  final int lastTripFuelFcfa;
  final List<Payment> payments;

  double get lastTripCoverage =>
      lastTripFuelFcfa == 0 ? 0 : lastTripReceivedFcfa / lastTripFuelFcfa;

  int get receivedThisMonthFcfa => payments
      .where((p) => p.received)
      .fold(0, (sum, p) => sum + p.amountFcfa);

  int get pendingFcfa => payments
      .where((p) => !p.received)
      .fold(0, (sum, p) => sum + p.amountFcfa);
}

// --- Évaluation ---------------------------------------------------------------------------------

const List<String> reportKinds = [
  'Passager absent',
  'Retard au point de prise',
  'Comportement inapproprié',
];

class PassengerRating {
  const PassengerRating({required this.passenger, required this.stars});

  final String passenger;

  /// 0 : pas encore noté ; 1 à 5 étoiles.
  final int stars;
}

class DriverOverview {
  const DriverOverview({
    required this.firstName,
    required this.approved,
    required this.automatic,
    this.nextCrew,
  });

  final String firstName;

  /// null : l'état de l'agrément n'est pas connu (l'API ne le publie pas encore).
  final bool? approved;
  final bool automatic;
  final Crew? nextCrew;
}
