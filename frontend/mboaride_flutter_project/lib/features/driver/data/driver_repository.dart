import '../../../core/api_client.dart';
import '../domain/driver.dart';

/// Espace conducteur : agrément, véhicule, règles, trajets, équipage, imprévus, gains.
abstract class DriverRepository {
  Future<DriverOverview> overview();

  Future<Approval> approval();

  /// Dépôt d'une pièce : elle passe « en vérification ».
  Future<Approval> uploadDocument(String kind);

  Future<Vehicle> vehicle();
  Future<Vehicle> saveVehicle(Vehicle vehicle);

  Future<DriverRules> rules();
  Future<DriverRules> saveRules(DriverRules rules);

  /// Distance estimée du trajet commun, pour l'estimation du prix.
  Future<double> estimateDistanceKm(String from, String to);

  Future<void> publishTrip(TripPlan plan);

  /// Ce que l'agent conducteur a fait pour le prochain trajet : réservations et refus.
  Future<List<AgentEvent>> agentActivity();

  /// Prochain équipage, ou null s'il n'y en a pas.
  Future<Crew?> nextCrew();

  Future<void> reportDelay(Crew crew, int minutes);

  /// Annulation (US07) : les passagers sont prévenus et réaffectés automatiquement.
  Future<CancellationResult> cancelTrip(
    Crew crew,
    CancelReason reason, {
    String? note,
  });

  Future<Earnings> earnings();

  Future<void> ratePassengers(
    Crew crew,
    List<PassengerRating> ratings, {
    Set<String> reports = const {},
    bool serious = false,
  });
}

/// Branché sur l'API FastAPI. Seules deux routes conducteur existent aujourd'hui :
/// `GET /api/moi/trajets` (prochain trajet) et `POST /api/trajets/{id}/annulations`
/// (annulation et réaffectation). Les autres écrans affichent un message clair tant
/// que leur route n'est pas ajoutée côté API.
class ApiDriverRepository implements DriverRepository {
  ApiDriverRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  static Never _missing(String what) => throw ApiException(
    'Pas encore disponible côté API : $what. '
    'Lancez l\'application avec FAKE_API=true pour la démonstration.',
  );

  @override
  Future<DriverOverview> overview() async =>
      DriverOverview(firstName: '', approved: null, automatic: true, nextCrew: await nextCrew());

  @override
  Future<Crew?> nextCrew() async {
    final rows = await _client.get('/api/moi/trajets') as List<dynamic>;
    final booked = rows
        .cast<Map<String, dynamic>>()
        .where((r) => r['date_trajet'] != null && ((r['passagers'] as num?) ?? 0) > 0)
        .toList()
      ..sort((a, b) => (a['date_trajet'] as String).compareTo(b['date_trajet'] as String));
    if (booked.isEmpty) return null;
    final row = booked.first;
    final date = row['date_trajet'] as String;
    final passengers = (row['passagers'] as num).toInt();
    return Crew(
      tripId: (row['id_trajet'] as num).toInt(),
      date: date,
      dayLabel: 'Le ${date.substring(8, 10)}/${date.substring(5, 7)}',
      departure: row['heure'] as String,
      from: row['depart_libelle'] as String,
      to: row['arrivee_libelle'] as String,
      seatsTotal: passengers,
      stops: const [],
      arrival: row['heure'] as String,
    );
  }

  @override
  Future<CancellationResult> cancelTrip(
    Crew crew,
    CancelReason reason, {
    String? note,
  }) async {
    final motif = [reason.label, if (note != null && note.trim().isNotEmpty) note.trim()].join(' : ');
    final body = await _client.post('/api/trajets/${crew.tripId}/annulations', {
      'date_trajet': crew.date,
      'motif': motif,
    }) as Map<String, dynamic>;
    final outcomes = (body['passagers'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (p) => ReassignmentOutcome(
            passenger: (p['passager'] as String?) ?? 'Passager',
            reassigned: p['reaffecte'] == true,
            newDriver: p['nouveau_conducteur'] as String?,
            offersAvailable: (p['offres_disponibles'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
    return CancellationResult(
      cancelledBookings: (body['reservations_annulees'] as num?)?.toInt() ?? outcomes.length,
      outcomes: outcomes,
    );
  }

  @override
  Future<Approval> approval() async => _missing('l\'agrément du conducteur');

  @override
  Future<Approval> uploadDocument(String kind) async => _missing('le dépôt des pièces');

  @override
  Future<Vehicle> vehicle() async => _missing('le véhicule');

  @override
  Future<Vehicle> saveVehicle(Vehicle vehicle) async => _missing('le véhicule');

  @override
  Future<DriverRules> rules() async => _missing('les règles du conducteur');

  @override
  Future<DriverRules> saveRules(DriverRules rules) async => _missing('les règles du conducteur');

  @override
  Future<double> estimateDistanceKm(String from, String to) async =>
      _missing('l\'estimation de distance');

  @override
  Future<void> publishTrip(TripPlan plan) async => _missing('la publication de trajet');

  @override
  Future<List<AgentEvent>> agentActivity() async => _missing('l\'activité de l\'agent');

  @override
  Future<void> reportDelay(Crew crew, int minutes) async => _missing('le signalement de retard');

  @override
  Future<Earnings> earnings() async => _missing('les gains du conducteur');

  @override
  Future<void> ratePassengers(
    Crew crew,
    List<PassengerRating> ratings, {
    Set<String> reports = const {},
    bool serious = false,
  }) async => _missing('l\'évaluation des passagers');
}

/// Données simulées (FAKE_API=true) : Armand, conducteur Logpom → Bonabéri (persona du
/// document de vision), départ 6 h 45, trois places, détour maximal de 2 km.
class FakeDriverRepository implements DriverRepository {
  FakeDriverRepository({bool approvedAtStart = true, this.delay = const Duration(milliseconds: 150)})
    : _approval = Approval(_documents(approvedAtStart));

  final Duration delay;
  Approval _approval;
  final Crew _crew = demoCrew();
  bool _cancelled = false;
  final List<TripPlan> published = [];
  final List<int> reportedDelays = [];
  List<PassengerRating> lastRatings = const [];

  Vehicle _vehicle = const Vehicle(
    model: 'Berline, 2012',
    plate: 'LT 482 AB',
    seats: 3,
    consumptionL100: 8,
    comfort: {Comfort.airConditioning, Comfort.nonSmoking},
  );

  DriverRules _rules = const DriverRules(
    colleagues: true,
    partners: true,
    publicNetwork: false,
    acceptsStudents: false,
    minPriceFcfa: 0,
    automatic: true,
  );

  static List<DriverDocument> _documents(bool approved) => [
    const DriverDocument(
      kind: 'identity',
      label: 'Pièce d\'identité',
      status: DocumentStatus.validated,
      detail: 'Valable jusqu\'en 03/2029',
    ),
    const DriverDocument(
      kind: 'licence',
      label: 'Permis de conduire',
      status: DocumentStatus.validated,
      detail: 'Valable jusqu\'en 11/2030',
    ),
    DriverDocument(
      kind: 'criminal_record',
      label: 'Extrait de casier judiciaire',
      status: approved ? DocumentStatus.validated : DocumentStatus.pending,
      detail: approved ? 'Délivré le 02/11/2026' : 'Déposé le 14/11/2026',
    ),
    DriverDocument(
      kind: 'insurance',
      label: 'Attestation d\'assurance',
      status: approved ? DocumentStatus.validated : DocumentStatus.missing,
      detail: approved ? 'Valable jusqu\'en 06/2027' : 'Photo ou PDF, en cours de validité',
    ),
  ];

  static String _tomorrowIso() {
    final d = DateTime.now().add(const Duration(days: 1));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Équipage de démonstration d'Armand (aussi utilisé par les tests, sans attente).
  static Crew demoCrew() => Crew(
    tripId: 101,
    date: _tomorrowIso(),
    dayLabel: 'Demain',
    departure: '06:45',
    from: 'Logpom',
    to: 'Bonabéri',
    seatsTotal: 3,
    arrival: '07:30',
    fromLat: 4.0790,
    fromLng: 9.7740,
    toLat: 4.0700,
    toLng: 9.6600,
    stops: const [
      CrewStop(passenger: 'Grâce', place: 'Kotto', pickupTime: '06:58', arrivalTime: '07:30',
          latestArrival: '07:45', priceFcfa: 252, lat: 4.0711, lng: 9.7590),
      CrewStop(passenger: 'Paul', place: 'Ndokoti', pickupTime: '07:05', arrivalTime: '07:30',
          latestArrival: '07:35', priceFcfa: 252, lat: 4.0470, lng: 9.7340),
      CrewStop(passenger: 'Nadège', place: 'Deido', pickupTime: '07:12', arrivalTime: '07:30',
          latestArrival: '07:50', priceFcfa: 252, lat: 4.0580, lng: 9.7050),
    ],
  );

  Future<void> _wait() => Future<void>.delayed(delay);

  @override
  Future<DriverOverview> overview() async {
    await _wait();
    return DriverOverview(
      firstName: 'Armand',
      approved: _approval.approved,
      automatic: _rules.automatic,
      nextCrew: _cancelled ? null : _crew,
    );
  }

  @override
  Future<Approval> approval() async {
    await _wait();
    return _approval;
  }

  @override
  Future<Approval> uploadDocument(String kind) async {
    await _wait();
    _approval = Approval([
      for (final d in _approval.documents)
        d.kind == kind
            ? d.copyWith(status: DocumentStatus.pending, detail: 'Déposé aujourd\'hui, en vérification')
            : d,
    ]);
    return _approval;
  }

  @override
  Future<Vehicle> vehicle() async {
    await _wait();
    return _vehicle;
  }

  @override
  Future<Vehicle> saveVehicle(Vehicle vehicle) async {
    await _wait();
    final error = vehicle.error;
    if (error != null) throw ApiException(error, statusCode: 422);
    return _vehicle = vehicle;
  }

  @override
  Future<DriverRules> rules() async {
    await _wait();
    return _rules;
  }

  @override
  Future<DriverRules> saveRules(DriverRules rules) async {
    await _wait();
    final error = rules.error;
    if (error != null) throw ApiException(error, statusCode: 422);
    return _rules = rules;
  }

  @override
  Future<double> estimateDistanceKm(String from, String to) async {
    await _wait();
    final route = '${from.toLowerCase()} ${to.toLowerCase()}';
    if (route.contains('yaound')) return 240;
    if (route.contains('logpom') && route.contains('bonab')) return 15;
    return 10;
  }

  @override
  Future<void> publishTrip(TripPlan plan) async {
    await _wait();
    if (!_approval.approved) {
      throw ApiException('Votre agrément doit être validé avant de publier un trajet.', statusCode: 403);
    }
    final error = plan.error;
    if (error != null) throw ApiException(error, statusCode: 422);
    published.add(plan);
  }

  @override
  Future<List<AgentEvent>> agentActivity() async {
    await _wait();
    return const [
      AgentEvent(kind: AgentEventKind.booked, title: 'Grâce',
          detail: 'Kotto → Bonabéri · prise à 6 h 58 · 252 FCFA · détour de 0,8 km'),
      AgentEvent(kind: AgentEventKind.booked, title: 'Paul',
          detail: 'Ndokoti → Bonabéri · prise à 7 h 05 · 252 FCFA · détour de 1,1 km'),
      AgentEvent(kind: AgentEventKind.booked, title: 'Nadège',
          detail: 'Deido → Bonabéri · prise à 7 h 12 · 252 FCFA · détour de 0,4 km'),
      AgentEvent(kind: AgentEventKind.declined, title: 'Demande refusée', reasonCode: 'DETOUR_TOO_LONG',
          detail: '3,4 km de détour pour un maximum de 2 km'),
      AgentEvent(kind: AgentEventKind.declined, title: 'Demande refusée', reasonCode: 'OUTSIDE_WINDOW',
          detail: 'Arrivée prévue à 7 h 50, le passager doit arriver avant 7 h 30'),
      AgentEvent(kind: AgentEventKind.declined, title: 'Demande refusée', reasonCode: 'NO_SEAT',
          detail: 'Vos 3 places étaient déjà réservées'),
    ];
  }

  @override
  Future<Crew?> nextCrew() async {
    await _wait();
    return _cancelled ? null : _crew;
  }

  @override
  Future<void> reportDelay(Crew crew, int minutes) async {
    await _wait();
    if (minutes <= 0) throw ApiException('Indiquez un retard positif.', statusCode: 422);
    reportedDelays.add(minutes);
  }

  @override
  Future<CancellationResult> cancelTrip(
    Crew crew,
    CancelReason reason, {
    String? note,
  }) async {
    await _wait();
    if (_cancelled) throw ApiException('Ce trajet est déjà annulé.', statusCode: 409);
    _cancelled = true;
    return const CancellationResult(
      cancelledBookings: 3,
      outcomes: [
        ReassignmentOutcome(passenger: 'Grâce', reassigned: true, newDriver: 'Mireille'),
        ReassignmentOutcome(passenger: 'Paul', reassigned: true, newDriver: 'Hervé'),
        ReassignmentOutcome(passenger: 'Nadège', reassigned: false, offersAvailable: 0),
      ],
    );
  }

  @override
  Future<Earnings> earnings() async {
    await _wait();
    return const Earnings(
      monthLabel: 'Novembre 2026',
      lastTripReceivedFcfa: 756,
      lastTripFuelFcfa: 1008,
      payments: [
        Payment(dateLabel: 'Lun. 9 nov.', route: 'Logpom → Bonabéri', passengers: 3, amountFcfa: 756, received: true),
        Payment(dateLabel: 'Mar. 10 nov.', route: 'Logpom → Bonabéri', passengers: 2, amountFcfa: 504, received: true),
        Payment(dateLabel: 'Mer. 11 nov.', route: 'Logpom → Bonabéri', passengers: 3, amountFcfa: 756, received: false),
      ],
    );
  }

  @override
  Future<void> ratePassengers(
    Crew crew,
    List<PassengerRating> ratings, {
    Set<String> reports = const {},
    bool serious = false,
  }) async {
    await _wait();
    if (ratings.every((r) => r.stars == 0)) {
      throw ApiException('Notez au moins un passager.', statusCode: 422);
    }
    lastRatings = ratings;
  }
}
