import '../../../core/api_client.dart';
import '../domain/driver.dart';

/// Espace conducteur : agrément, véhicule, règles, trajets, équipage, imprévus, gains.
abstract class DriverRepository {
  Future<DriverOverview> overview();

  Future<Approval> approval();

  /// Dépôt d'une pièce (le fichier est envoyé) : elle passe « en vérification » jusqu'à la décision
  /// d'un administrateur MboaRide.
  Future<Approval> uploadDocument(String kind, PickedDocument file);

  Future<Vehicle> vehicle();
  Future<Vehicle> saveVehicle(Vehicle vehicle);

  Future<DriverRules> rules();
  Future<DriverRules> saveRules(DriverRules rules);

  /// Distance estimée du trajet commun, pour l'estimation du prix.
  Future<double> estimateDistanceKm(String from, String to);

  Future<void> publishTrip(TripPlan plan);

  /// Programme plusieurs trajets d'un coup ; chacun est publié ou refusé indépendamment.
  Future<BatchPublishResult> publishTrips(List<TripPlan> plans);

  /// Trajets programmés : en ligne, retirés ou passés.
  Future<List<PublishedTrip>> publishedTrips();

  /// Retire un trajet entier : ses passagers sont prévenus, remboursés et réaffectés.
  Future<int> withdrawTrip(int tripId, {String? reason});

  /// Remet en ligne un trajet retiré ou passé (à une nouvelle date s'il était ponctuel).
  Future<void> republishTrip(int tripId, {DateTime? date, String? departure});

  /// Rétablit une date annulée d'un trajet régulier.
  Future<void> restoreDate(int tripId, DateTime date);

  /// Ce que l'agent conducteur a fait pour le prochain trajet : réservations et refus.
  Future<List<AgentEvent>> agentActivity();

  /// Prochain équipage, ou null s'il n'y en a pas.
  Future<Crew?> nextCrew();

  Future<void> reportDelay(Crew crew, int minutes);

  /// Démarrer la course : les passagers payés sont prévenus et peuvent la suivre.
  Future<CourseState> startCourse(Crew crew);

  /// Arrivé à destination : les passagers sont invités à valider la fin de la course.
  Future<CourseState> arriveCourse(Crew crew);

  /// Validations des passagers et règlement (versement au portefeuille).
  Future<CourseState> courseState(Crew crew);

  /// Préciser le point de ramassage d'un trajet publié ; les passagers sont prévenus.
  Future<void> setMeetingPoint(int tripId, {required String point, String? instructions, int waitMinutes = 5});

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

/// Branché sur l'API Python (`/api/moi/conducteur/...`), qui lit et écrit la base
/// partagée et calcule prix et horaires avec le moteur d'agents. L'annulation passe par
/// `POST /api/trajets/{id}/annulations`, qui réaffecte les passagers (US07).
class ApiDriverRepository implements DriverRepository {
  ApiDriverRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;
  static const String _base = '/api/moi/conducteur';

  /// Pièces de l'agrément : identifiant de l'application ↔ code de l'API.
  static const Map<String, String> documentCodes = {
    'identity': 'piece_identite',
    'licence': 'permis',
    'criminal_record': 'casier_judiciaire',
    'insurance': 'assurance',
  };

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  @override
  Future<DriverOverview> overview() async {
    final body = await _client.get(_base) as Map<String, dynamic>;
    return DriverOverview(
      firstName: body['prenom'] as String? ?? '',
      approved: body['agree'] as bool?,
      automatic: body['automatique'] as bool? ?? true,
      nextCrew: await nextCrew(),
    );
  }

  @override
  Future<Crew?> nextCrew() async {
    final body = await _client.get('$_base/equipage');
    if (body == null) return null;
    return crewFromJson(body as Map<String, dynamic>);
  }

  static Crew crewFromJson(Map<String, dynamic> json) {
    double? d(Object? v) => (v as num?)?.toDouble();
    return Crew(
      tripId: (json['id_trajet'] as num).toInt(),
      date: json['date_trajet'] as String,
      dayLabel: json['jour'] as String? ?? '',
      departure: json['heure_depart'] as String,
      from: json['depart'] as String,
      to: json['arrivee'] as String,
      seatsTotal: (json['places'] as num).toInt(),
      arrival: json['arrivee_estimee'] as String? ?? json['heure_depart'] as String,
      fromLat: d(json['depart_lat']),
      fromLng: d(json['depart_lon']),
      toLat: d(json['arrivee_lat']),
      toLng: d(json['arrivee_lon']),
      meetingPoint: json['point_ramassage'] as String?,
      meetingInstructions: json['consignes_ramassage'] as String?,
      waitMinutes: (json['attente_max_min'] as num?)?.toInt() ?? 5,
      courseStatus: CourseStatus.fromCode(json['statut_course'] as String?),
      stops: [
        for (final s in (json['arrets'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
          CrewStop(
            passenger: s['passager'] as String,
            place: s['lieu'] as String,
            pickupTime: s['prise_en_charge'] as String,
            arrivalTime: s['arrivee'] as String,
            latestArrival: s['au_plus_tard'] as String,
            priceFcfa: (s['prix_fcfa'] as num).toInt(),
            lat: d(s['lat']),
            lng: d(s['lon']),
            lastName: s['nom'] as String?,
            phone: s['telephone'] as String?,
            destination: s['destination'] as String?,
            rating: d(s['note_moyenne']),
            ratingCount: (s['nb_evaluations'] as num?)?.toInt() ?? 0,
            student: s['eleve'] == true,
            endValidated: s['fin_validee'] == true,
            seats: (s['nb_places'] as num?)?.toInt() ?? 1,
          ),
      ],
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

  Approval _approval(Map<String, dynamic> body) {
    final codes = {for (final e in documentCodes.entries) e.value: e.key};
    return Approval([
      for (final doc in (body['documents'] as List<dynamic>).cast<Map<String, dynamic>>())
        DriverDocument(
          kind: codes[doc['type']] ?? doc['type'] as String,
          label: doc['libelle'] as String,
          status: switch (doc['statut']) {
            'valide' => DocumentStatus.validated,
            'depose' => DocumentStatus.pending,
            'refuse' => DocumentStatus.rejected,
            _ => DocumentStatus.missing,
          },
          detail: doc['detail'] as String?,
        ),
    ]);
  }

  @override
  Future<Approval> approval() async =>
      _approval(await _client.get('$_base/agrement') as Map<String, dynamic>);

  @override
  Future<Approval> uploadDocument(String kind, PickedDocument file) async => _approval(
    await _client.postBytes(
          '$_base/agrement/documents/${documentCodes[kind] ?? kind}',
          file.bytes,
          contentType: file.contentType,
        )
        as Map<String, dynamic>,
  );

  @override
  Future<Vehicle> vehicle() async {
    try {
      final v = await _client.get('$_base/vehicule') as Map<String, dynamic>;
      return Vehicle(
        model: v['marque_modele'] as String,
        plate: v['immatriculation'] as String,
        seats: (v['places_passagers'] as num).toInt(),
        consumptionL100: (v['conso_l_100km'] as num).toDouble(),
        comfort: {
          if (v['climatise'] == true) Comfort.airConditioning,
          if (v['non_fumeur'] == true) Comfort.nonSmoking,
          if (v['accepte_bagages'] == true) Comfort.luggage,
        },
      );
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      // Pas encore de véhicule : formulaire vide à remplir.
      return const Vehicle(model: '', plate: '', seats: 3, consumptionL100: 8, comfort: {Comfort.nonSmoking});
    }
  }

  @override
  Future<Vehicle> saveVehicle(Vehicle vehicle) async {
    await _client.put('$_base/vehicule', {
      'marque_modele': vehicle.model.trim(),
      'immatriculation': vehicle.plate.trim(),
      'places_passagers': vehicle.seats,
      'conso_l_100km': vehicle.consumptionL100,
      'climatise': vehicle.comfort.contains(Comfort.airConditioning),
      'non_fumeur': vehicle.comfort.contains(Comfort.nonSmoking),
      'accepte_bagages': vehicle.comfort.contains(Comfort.luggage),
    });
    return vehicle;
  }

  DriverRules _rules(Map<String, dynamic> r) => DriverRules(
    colleagues: r['collegues'] as bool,
    partners: r['partenaires'] as bool,
    publicNetwork: r['public'] as bool,
    acceptsStudents: r['eleves'] as bool,
    minPriceFcfa: (r['prix_min_fcfa'] as num).toInt(),
    automatic: r['automatique'] as bool,
  );

  @override
  Future<DriverRules> rules() async => _rules(await _client.get('$_base/regles') as Map<String, dynamic>);

  @override
  Future<DriverRules> saveRules(DriverRules rules) async => _rules(
    await _client.put('$_base/regles', {
      'collegues': rules.colleagues,
      'partenaires': rules.partners,
      'public': rules.publicNetwork,
      'eleves': rules.acceptsStudents,
      'prix_min_fcfa': rules.minPriceFcfa,
      'automatique': rules.automatic,
    }) as Map<String, dynamic>,
  );

  @override
  Future<double> estimateDistanceKm(String from, String to) async {
    final body = await _client.get(
      '/api/lieux/distance?de=${Uri.encodeQueryComponent(from)}&a=${Uri.encodeQueryComponent(to)}',
    ) as Map<String, dynamic>;
    return (body['distance_km'] as num).toDouble();
  }

  @override
  Future<void> publishTrip(TripPlan plan) async {
    final result = await publishTrips([plan]);
    if (result.refusals.isNotEmpty) throw ApiException(result.refusals.values.first, statusCode: 409);
  }

  @override
  Future<BatchPublishResult> publishTrips(List<TripPlan> plans) async {
    final body = await _client.post('$_base/trajets/lot', {'trajets': [for (final p in plans) _planJson(p)]})
        as Map<String, dynamic>;
    final refusals = <TripPlan, String>{};
    for (final r in (body['resultats'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      if (r['publie'] != true) refusals[plans[(r['rang'] as num).toInt()]] = '${r['erreur']}';
    }
    return BatchPublishResult(published: (body['publies'] as num).toInt(), refusals: refusals);
  }

  @override
  Future<List<PublishedTrip>> publishedTrips() async => [
    for (final t in (await _client.get('$_base/trajets') as List<dynamic>).cast<Map<String, dynamic>>())
      PublishedTrip.fromJson(t),
  ];

  @override
  Future<int> withdrawTrip(int tripId, {String? reason}) async {
    final body = await _client.post('$_base/trajets/$tripId/retrait', {
      if (reason != null && reason.trim().isNotEmpty) 'motif': reason.trim(),
    }) as Map<String, dynamic>;
    return (body['reservations_annulees'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> republishTrip(int tripId, {DateTime? date, String? departure}) async {
    await _client.post('$_base/trajets/$tripId/republication', {
      if (date != null) 'date_trajet': _isoDate(date),
      if (departure != null) 'heure_depart': departure,
    });
  }

  @override
  Future<void> restoreDate(int tripId, DateTime date) async {
    await _client.delete('$_base/trajets/$tripId/annulations/${_isoDate(date)}');
  }

  Map<String, dynamic> _planJson(TripPlan plan) {
    final interurban = plan.kind == TripKind.interurban;
    final oneOff = plan.date ?? (plan.weekdays.isEmpty ? DateTime.now().add(const Duration(days: 1)) : null);
    return {
      'type_trajet': interurban ? 'interurbain' : 'urbain',
      'depart': plan.from.trim(),
      'arrivee': plan.to.trim(),
      'heure_depart': plan.departure,
      'jours_semaine': oneOff == null ? (plan.weekdays.toList()..sort()) : <int>[],
      // Trajet ponctuel : sa date (sans date ni jour, il part demain).
      if (oneOff != null) 'date_trajet': _isoDate(oneOff),
      'places': plan.seats,
      'detour_max_km': plan.maxDetourKm,
      'peage_fcfa': plan.tollsFcfa,
      'points_depart': plan.pickupPoints,
      'point_ramassage': plan.meetingPoint.trim(),
      if (plan.meetingInstructions.trim().isNotEmpty) 'consignes_ramassage': plan.meetingInstructions.trim(),
      'attente_max_min': plan.waitMinutes,
    };
  }

  @override
  Future<List<AgentEvent>> agentActivity() async {
    final rows = await _client.get('$_base/activite') as List<dynamic>;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        if (r['type'] == 'reservation')
          AgentEvent(kind: AgentEventKind.booked, title: r['passager'] as String, detail: r['detail'] as String),
    ];
  }

  @override
  Future<void> reportDelay(Crew crew, int minutes) async {
    await _client.post('$_base/retard', {'id_trajet': crew.tripId, 'date_trajet': crew.date, 'minutes': minutes});
  }

  Map<String, dynamic> _day(Crew crew) => {'id_trajet': crew.tripId, 'date_trajet': crew.date};

  @override
  Future<CourseState> startCourse(Crew crew) async =>
      CourseState.fromJson(await _client.post('$_base/course/demarrer', _day(crew)) as Map<String, dynamic>);

  @override
  Future<CourseState> arriveCourse(Crew crew) async =>
      CourseState.fromJson(await _client.post('$_base/course/arrivee', _day(crew)) as Map<String, dynamic>);

  @override
  Future<CourseState> courseState(Crew crew) async => CourseState.fromJson(
    await _client.get('$_base/course?id_trajet=${crew.tripId}&date_trajet=${crew.date}') as Map<String, dynamic>,
  );

  @override
  Future<void> setMeetingPoint(int tripId, {required String point, String? instructions, int waitMinutes = 5}) async {
    await _client.put('$_base/trajets/$tripId/ramassage', {
      'point_ramassage': point.trim(),
      if (instructions != null && instructions.trim().isNotEmpty) 'consignes_ramassage': instructions.trim(),
      'attente_max_min': waitMinutes,
    });
  }

  @override
  Future<Earnings> earnings() async {
    final body = await _client.get('$_base/gains') as Map<String, dynamic>;
    return Earnings(
      monthLabel: body['mois'] as String,
      lastTripReceivedFcfa: (body['dernier_trajet_recu_fcfa'] as num).toInt(),
      lastTripFuelFcfa: (body['dernier_trajet_carburant_fcfa'] as num).toInt(),
      payments: [
        for (final p in (body['paiements'] as List<dynamic>).cast<Map<String, dynamic>>())
          Payment(
            dateLabel: p['date'] as String,
            route: p['trajet'] as String,
            passengers: (p['passagers'] as num).toInt(),
            amountFcfa: (p['montant_fcfa'] as num).toInt(),
            received: p['recu'] == true,
            commissionFcfa: (p['commission_fcfa'] as num?)?.toInt() ?? 0,
          ),
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
    await _client.post('$_base/evaluations', {
      'id_trajet': crew.tripId,
      'date_trajet': crew.date,
      'notes': [
        for (final r in ratings)
          if (r.stars > 0) {'passager': r.passenger, 'note': r.stars},
      ],
      'signalements': reports.toList(),
      'grave': serious,
    });
  }
}

/// Données simulées (FAKE_API=true) : Armand, conducteur Logpom → Bonabéri (persona du
/// document de vision), départ 6 h 45, trois places, détour maximal de 2 km.
class FakeDriverRepository implements DriverRepository {
  FakeDriverRepository({bool approvedAtStart = true, this.delay = const Duration(milliseconds: 150)})
    : _approval = Approval(_documents(approvedAtStart));

  final Duration delay;
  Approval _approval;
  Crew _crew = demoCrew();
  bool _cancelled = false;
  CourseStatus _course = CourseStatus.notStarted;

  /// Passagers qui ont validé la fin de la course (simulé).
  final Set<String> validated = {};
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
    meetingPoint: 'Station Total de Logpom, côté boulangerie',
    meetingInstructions: 'Berline grise LT 482 AB, je klaxonne deux fois',
    stops: const [
      CrewStop(passenger: 'Grâce', place: 'Kotto', pickupTime: '06:58', arrivalTime: '07:30',
          latestArrival: '07:45', priceFcfa: 275, lat: 4.0711, lng: 9.7590, lastName: 'Ebolo',
          phone: '+237690000201', destination: 'Bonabéri', rating: 4.8, ratingCount: 12),
      CrewStop(passenger: 'Paul', place: 'Ndokoti', pickupTime: '07:05', arrivalTime: '07:30',
          latestArrival: '07:35', priceFcfa: 275, lat: 4.0470, lng: 9.7340, lastName: 'Mbarga',
          phone: '+237690000202', destination: 'Bonabéri', rating: 4.5, ratingCount: 4),
      CrewStop(passenger: 'Nadège', place: 'Deido', pickupTime: '07:12', arrivalTime: '07:30',
          latestArrival: '07:50', priceFcfa: 275, lat: 4.0580, lng: 9.7050, lastName: 'Kamga',
          phone: '+237690000203', destination: 'Bonabéri'),
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
  Future<Approval> uploadDocument(String kind, PickedDocument file) async {
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
  Future<BatchPublishResult> publishTrips(List<TripPlan> plans) async {
    await _wait();
    if (!_approval.approved) {
      throw ApiException('Votre agrément doit être validé avant de publier un trajet.', statusCode: 403);
    }
    final refusals = <TripPlan, String>{};
    for (final plan in plans) {
      final duplicate = published.any((p) =>
          p.from == plan.from && p.to == plan.to && p.departure == plan.departure &&
          p.date == plan.date && p.weekdays.length == plan.weekdays.length &&
          p.weekdays.containsAll(plan.weekdays));
      final error = plan.error ?? (duplicate ? 'Ce trajet est déjà publié' : null);
      if (error != null) {
        refusals[plan] = error;
      } else {
        published.add(plan);
        _trips.insert(0, PublishedTrip(
          id: 200 + _trips.length, kind: plan.kind, state: PublishedState.active, from: plan.from, to: plan.to,
          departure: plan.departure, weekdays: plan.weekdays, seats: plan.seats, date: plan.date,
          meetingPoint: plan.meetingPoint, nextDeparture: plan.date ?? DateTime.now().add(const Duration(days: 1)),
        ));
      }
    }
    return BatchPublishResult(published: plans.length - refusals.length, refusals: refusals);
  }

  /// Trajets programmés de démonstration : l'aller d'Armand, son retour retiré, un voyage passé.
  final List<PublishedTrip> _trips = [
    PublishedTrip(
      id: 101, kind: TripKind.urban, state: PublishedState.active, from: 'Logpom', to: 'Bonabéri',
      departure: '06:45', weekdays: const {1, 2, 3, 4, 5}, seats: 3,
      meetingPoint: 'Station Total de Logpom, côté boulangerie', upcomingBookings: 3,
      nextDeparture: DateTime.now().add(const Duration(days: 1)),
      cancelledDates: [DateTime.now().add(const Duration(days: 3))],
    ),
    const PublishedTrip(
      id: 102, kind: TripKind.urban, state: PublishedState.withdrawn, from: 'Bonabéri', to: 'Logpom',
      departure: '17:30', weekdays: {1, 2, 3, 4, 5}, seats: 3, meetingPoint: 'Carrefour Bonabéri, devant la pharmacie',
    ),
    PublishedTrip(
      id: 103, kind: TripKind.interurban, state: PublishedState.past, from: 'Douala', to: 'Yaoundé',
      departure: '14:00', weekdays: const {}, seats: 4, date: DateTime(2026, 11, 2), meetingPoint: 'Agence de Bonanjo',
    ),
  ];

  @override
  Future<List<PublishedTrip>> publishedTrips() async {
    await _wait();
    return List.unmodifiable(_trips);
  }

  PublishedTrip _with(PublishedTrip t, {PublishedState? state, DateTime? date, List<DateTime>? cancelledDates}) =>
      PublishedTrip(
        id: t.id, kind: t.kind, state: state ?? t.state, from: t.from, to: t.to, departure: t.departure,
        weekdays: t.weekdays, seats: t.seats, date: date ?? t.date, meetingPoint: t.meetingPoint,
        cancelledDates: cancelledDates ?? t.cancelledDates, upcomingBookings: state == PublishedState.withdrawn ? 0 : t.upcomingBookings,
        nextDeparture: state == PublishedState.withdrawn ? null : (date ?? t.nextDeparture),
      );

  void _replace(int id, PublishedTrip Function(PublishedTrip) change) {
    final i = _trips.indexWhere((t) => t.id == id);
    if (i < 0) throw ApiException('Trajet introuvable', statusCode: 404);
    _trips[i] = change(_trips[i]);
  }

  @override
  Future<int> withdrawTrip(int tripId, {String? reason}) async {
    await _wait();
    var passengers = 0;
    _replace(tripId, (t) {
      if (t.state == PublishedState.withdrawn) throw ApiException('Ce trajet est déjà retiré', statusCode: 409);
      passengers = t.upcomingBookings;
      return _with(t, state: PublishedState.withdrawn);
    });
    return passengers;
  }

  @override
  Future<void> republishTrip(int tripId, {DateTime? date, String? departure}) async {
    await _wait();
    _replace(tripId, (t) {
      if (t.state == PublishedState.active) throw ApiException('Ce trajet est déjà en ligne', statusCode: 409);
      if (t.oneOff && date == null) {
        throw ApiException("Choisissez une nouvelle date, aujourd'hui ou plus tard", statusCode: 422);
      }
      return _with(t, state: PublishedState.active, date: date);
    });
  }

  @override
  Future<void> restoreDate(int tripId, DateTime date) async {
    await _wait();
    _replace(tripId, (t) => _with(t, cancelledDates: [
      for (final d in t.cancelledDates)
        if (!(d.year == date.year && d.month == date.month && d.day == date.day)) d,
    ]));
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

  CourseState _state() {
    final all = _crew.stops.every((s) => validated.contains(s.passenger));
    final total = _crew.stops.fold(0, (sum, s) => sum + s.priceFcfa);
    final commission = _crew.stops.fold(0, (sum, s) => sum + s.priceFcfa ~/ 10);
    return CourseState(
      status: all ? CourseStatus.settled : _course,
      passengers: [
        for (final s in _crew.stops)
          CoursePassenger(
            firstName: s.passenger,
            lastName: s.lastName,
            validated: validated.contains(s.passenger),
            rating: validated.contains(s.passenger) ? 5 : null,
          ),
      ],
      totalPaidFcfa: total,
      commissionFcfa: commission,
      driverAmountFcfa: total - commission,
      paidOut: all,
    );
  }

  @override
  Future<CourseState> startCourse(Crew crew) async {
    await _wait();
    if (_course == CourseStatus.notStarted) _course = CourseStatus.running;
    return _state();
  }

  @override
  Future<CourseState> arriveCourse(Crew crew) async {
    await _wait();
    if (_course == CourseStatus.notStarted) throw ApiException("Démarrez d'abord la course", statusCode: 409);
    _course = CourseStatus.arrived;
    return _state();
  }

  @override
  Future<CourseState> courseState(Crew crew) async {
    await _wait();
    return _state();
  }

  @override
  Future<void> setMeetingPoint(int tripId, {required String point, String? instructions, int waitMinutes = 5}) async {
    await _wait();
    if (point.trim().length < 5) throw ApiException('Précisez le point de ramassage.', statusCode: 422);
    _crew = Crew(
      tripId: _crew.tripId, date: _crew.date, dayLabel: _crew.dayLabel, departure: _crew.departure,
      from: _crew.from, to: _crew.to, seatsTotal: _crew.seatsTotal, stops: _crew.stops, arrival: _crew.arrival,
      fromLat: _crew.fromLat, fromLng: _crew.fromLng, toLat: _crew.toLat, toLng: _crew.toLng,
      meetingPoint: point.trim(), meetingInstructions: instructions, waitMinutes: waitMinutes,
      courseStatus: _course,
    );
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
      lastTripReceivedFcfa: 744,
      lastTripFuelFcfa: 1008,
      payments: [
        Payment(dateLabel: 'Lun. 9 nov.', route: 'Logpom → Bonabéri', passengers: 3, amountFcfa: 744,
            received: true, commissionFcfa: 81),
        Payment(dateLabel: 'Mar. 10 nov.', route: 'Logpom → Bonabéri', passengers: 2, amountFcfa: 540,
            received: true, commissionFcfa: 60),
        Payment(dateLabel: 'Mer. 11 nov.', route: 'Logpom → Bonabéri', passengers: 3, amountFcfa: 744,
            received: false, commissionFcfa: 81),
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
