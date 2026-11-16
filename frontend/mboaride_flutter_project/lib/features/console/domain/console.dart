
export '../../offers/domain/offer.dart' show formatFcfa;

/// Organisation dont l'utilisateur est membre ou administrateur (US13).
class Organisation {
  const Organisation({
    required this.id,
    required this.name,
    required this.kind,
    required this.role,
  });

  final int id;
  final String name;
  final String kind;
  final String role;

  bool get isAdmin => role == 'administrateur';

  factory Organisation.fromJson(Map<String, dynamic> json) => Organisation(
    id: (json['id_organisation'] as num?)?.toInt() ?? 0,
    name: json['nom'] as String? ?? '',
    kind: json['type_organisation'] as String? ?? '',
    role: json['role'] as String? ?? 'membre',
  );
}

/// Invitation envoyée à un employé, avec son statut et le nombre de relances.
class Invitation {
  const Invitation({
    required this.id,
    required this.email,
    required this.status,
    required this.reminders,
    this.service,
    this.member,
    this.trips = 0,
    this.sentOn,
    this.expiresOn,
  });

  final int id;
  final String email;
  final String status;
  final int reminders;
  final String? service;
  final String? member;
  final int trips;
  final String? sentOn;
  final String? expiresOn;

  /// Trois relances au maximum, règle appliquée aussi par l'API.
  static const int maxReminders = 3;

  bool get canRemind => status == 'envoyee' && reminders < maxReminders;

  String get statusLabel => const {
    'envoyee': 'Invitation envoyée',
    'acceptee': 'A rejoint le cercle',
    'expiree': 'Invitation expirée',
    'refusee': 'Invitation refusée',
  }[status] ??
      status;

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
    id: (json['id_invitation'] as num?)?.toInt() ?? 0,
    email: json['email'] as String? ?? '',
    status: json['statut'] as String? ?? 'envoyee',
    reminders: (json['relances'] as num?)?.toInt() ?? 0,
    service: json['service'] as String?,
    member: json['membre'] as String?,
    trips: (json['trajets'] as num?)?.toInt() ?? 0,
    sentOn: json['envoyee_le']?.toString(),
    expiresOn: json['expire_le']?.toString(),
  );
}

/// Résultat d'un envoi d'invitations : adresses retenues et adresses écartées
/// avec leur motif.
class InvitationResult {
  const InvitationResult({
    required this.sent,
    required this.rejected,
    this.note = '',
  });

  final List<String> sent;
  final List<({String email, String reason})> rejected;
  final String note;

  factory InvitationResult.fromJson(Map<String, dynamic> json) =>
      InvitationResult(
        sent: ((json['envoyees'] as List<dynamic>?) ?? const [])
            .map((e) => (e as Map<String, dynamic>)['email'] as String? ?? '')
            .toList(growable: false),
        rejected: ((json['ecartees'] as List<dynamic>?) ?? const [])
            .map(
              (e) => (
                email: (e as Map<String, dynamic>)['email'] as String? ?? '',
                reason: e['motif'] as String? ?? '',
              ),
            )
            .toList(growable: false),
        note: json['note'] as String? ?? '',
      );
}

/// Suivi de l'adoption dans l'organisation (US13).
class Adoption {
  const Adoption({
    required this.organisation,
    required this.headcount,
    required this.members,
    required this.approvedDrivers,
    required this.activeMembers30d,
    required this.rate,
    required this.target,
    required this.targetReached,
    required this.missingForTarget,
    required this.byService,
  });

  final String organisation;
  final int headcount;
  final int members;
  final int approvedDrivers;
  final int activeMembers30d;
  final double? rate;
  final double target;
  final bool targetReached;
  final int? missingForTarget;
  final List<({String service, int members, int active})> byService;

  String get rateLabel =>
      rate == null ? '-' : '${(rate! * 100).toStringAsFixed(1)} %';

  String get targetLabel => '${(target * 100).round()} %';

  factory Adoption.fromJson(Map<String, dynamic> json) => Adoption(
    organisation: json['organisation'] as String? ?? '',
    headcount: (json['effectif'] as num?)?.toInt() ?? 0,
    members: (json['membres'] as num?)?.toInt() ?? 0,
    approvedDrivers: (json['conducteurs_agrees'] as num?)?.toInt() ?? 0,
    activeMembers30d: (json['membres_actifs_30j'] as num?)?.toInt() ?? 0,
    rate: (json['taux_adoption'] as num?)?.toDouble(),
    target: (json['objectif_adoption'] as num?)?.toDouble() ?? 0.6,
    targetReached: json['objectif_atteint'] as bool? ?? false,
    missingForTarget: (json['manque_pour_objectif'] as num?)?.toInt(),
    byService: ((json['par_service'] as List<dynamic>?) ?? const [])
        .map(
          (s) => (
            service: (s as Map<String, dynamic>)['service'] as String? ?? '',
            members: (s['membres'] as num?)?.toInt() ?? 0,
            active: (s['actifs_30j'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false),
  );
}

/// Économies et CO2 évité sur une période (US14).
class Impact {
  const Impact({
    required this.organisation,
    required this.from,
    required this.to,
    required this.sharedTrips,
    required this.kmAvoided,
    required this.litresAvoided,
    required this.co2CarefulKg,
    required this.co2HighKg,
    required this.employeeSavingsFcfa,
    required this.employeeSpendFcfa,
    required this.subscriptionCostFcfa,
    required this.subscribers,
    required this.savingsPerFcfa,
  });

  final String organisation;
  final String from;
  final String to;
  final int sharedTrips;
  final double kmAvoided;
  final double litresAvoided;
  final double co2CarefulKg;
  final double co2HighKg;
  final int employeeSavingsFcfa;
  final int employeeSpendFcfa;
  final int subscriptionCostFcfa;
  final int subscribers;
  final double? savingsPerFcfa;

  factory Impact.fromJson(Map<String, dynamic> json) {
    final co2 = (json['co2_evite_kg'] as Map<String, dynamic>?) ?? const {};
    final sub = (json['abonnement'] as Map<String, dynamic>?) ?? const {};
    return Impact(
      organisation: json['organisation'] as String? ?? '',
      from: json['du']?.toString() ?? '',
      to: json['au']?.toString() ?? '',
      sharedTrips: (json['trajets_partages'] as num?)?.toInt() ?? 0,
      kmAvoided: (json['km_voiture_evites'] as num?)?.toDouble() ?? 0,
      litresAvoided: (json['litres_evites'] as num?)?.toDouble() ?? 0,
      co2CarefulKg: (co2['prudent'] as num?)?.toDouble() ?? 0,
      co2HighKg: (co2['haut'] as num?)?.toDouble() ?? 0,
      employeeSavingsFcfa: (json['economies_employes_fcfa'] as num?)?.toInt() ?? 0,
      employeeSpendFcfa: (json['depense_employes_fcfa'] as num?)?.toInt() ?? 0,
      subscriptionCostFcfa: (sub['cout_fcfa'] as num?)?.toInt() ?? 0,
      subscribers: (sub['abonnes'] as num?)?.toInt() ?? 0,
      savingsPerFcfa: (sub['economies_par_fcfa_d_abonnement'] as num?)
          ?.toDouble(),
    );
  }
}
