/// Paiement Mobile Money (US10, simulé) et « Mes trajets ».
library;

enum MobileMoneyOperator {
  mtn('mtn', 'MTN Mobile Money', ['67', '650', '651', '652', '653', '654', '680', '681', '682', '683', '684']),
  orange('orange', 'Orange Money', ['69', '655', '656', '657', '658', '659', '685', '686', '687', '688', '689']);

  const MobileMoneyOperator(this.code, this.label, this.prefixes);

  final String code;
  final String label;

  /// Préfixes des numéros camerounais de l'opérateur (mêmes règles que l'API).
  final List<String> prefixes;

  static MobileMoneyOperator fromCode(String? code) =>
      values.firstWhere((o) => o.code == code, orElse: () => MobileMoneyOperator.mtn);

  /// Numéro à 9 chiffres (« 6XXXXXXXX »), sans indicatif ni espaces ; null s'il est invalide.
  static String? localNumber(String raw) {
    var digits = raw.replaceAll(RegExp(r'[\s.()\-]'), '');
    if (digits.startsWith('+237')) {
      digits = digits.substring(4);
    } else if (digits.startsWith('237') && digits.length == 12) {
      digits = digits.substring(3);
    }
    return RegExp(r'^6\d{8}$').hasMatch(digits) ? digits : null;
  }

  /// Message d'erreur, ou null si le numéro appartient bien à l'opérateur.
  String? checkNumber(String raw) {
    final number = localNumber(raw);
    if (number == null) return 'Numéro camerounais attendu : 6 suivi de 8 chiffres.';
    if (!prefixes.any(number.startsWith)) {
      final other = values.where((o) => o != this && o.prefixes.any(number.startsWith));
      return 'Ce numéro n\'est pas un numéro $label'
          '${other.isEmpty ? '' : ' (il semble être ${other.first.label})'}.';
    }
    return null;
  }
}

/// Compte Mobile Money enregistré : opérateur, numéro, titulaire. Jamais de code secret.
class MobileMoneyAccount {
  const MobileMoneyAccount({
    required this.id,
    required this.operator,
    required this.phone,
    required this.holder,
    required this.isDefault,
  });

  final int id;
  final MobileMoneyOperator operator;
  final String phone;
  final String holder;
  final bool isDefault;

  /// « +237 6 77 00 05 02 ».
  String get displayPhone {
    final n = MobileMoneyOperator.localNumber(phone) ?? phone;
    if (n.length != 9) return phone;
    return '+237 ${n[0]} ${n.substring(1, 3)} ${n.substring(3, 5)} ${n.substring(5, 7)} ${n.substring(7)}';
  }

  factory MobileMoneyAccount.fromJson(Map<String, dynamic> json) => MobileMoneyAccount(
    id: (json['id_compte'] as num).toInt(),
    operator: MobileMoneyOperator.fromCode(json['operateur'] as String?),
    phone: json['telephone'] as String? ?? '',
    holder: json['titulaire'] as String? ?? '',
    isDefault: json['par_defaut'] == true,
  );
}

enum PaymentStatus { pending, succeeded, failed, refunded }

PaymentStatus paymentStatusFromCode(String? code) => switch (code) {
  'reussi' => PaymentStatus.succeeded,
  'echoue' => PaymentStatus.failed,
  'rembourse' => PaymentStatus.refunded,
  _ => PaymentStatus.pending,
};

/// État d'un paiement après initiation ou réponse de l'opérateur.
class PaymentReceipt {
  const PaymentReceipt({
    required this.paymentId,
    required this.status,
    required this.amountFcfa,
    this.reference,
    this.operatorLabel,
    this.phone,
    this.message,
    this.failureReason,
    this.attemptsLeft = 3,
  });

  final int paymentId;
  final PaymentStatus status;
  final int amountFcfa;
  final String? reference;
  final String? operatorLabel;
  final String? phone;

  /// Consigne de l'opérateur : « une demande de paiement a été envoyée au... ».
  final String? message;
  final String? failureReason;
  final int attemptsLeft;

  factory PaymentReceipt.fromJson(Map<String, dynamic> json) => PaymentReceipt(
    paymentId: (json['id_paiement'] as num).toInt(),
    status: paymentStatusFromCode(json['statut'] as String?),
    amountFcfa: (json['montant_fcfa'] as num?)?.toInt() ?? 0,
    reference: json['reference'] as String?,
    operatorLabel: json['operateur'] as String?,
    phone: json['telephone'] as String?,
    message: json['message'] as String?,
    failureReason: json['motif_echec'] as String?,
    attemptsLeft: (json['tentatives_restantes'] as num?)?.toInt() ?? 3,
  );
}

/// Un trajet choisi par le passager.
enum TripState {
  toConfirm('À confirmer'),
  confirmed('Confirmé'),
  cancelled('Annulé'),
  done('Terminé');

  const TripState(this.label);
  final String label;

  static TripState fromCode(String? code) => switch (code) {
    'confirme' => TripState.confirmed,
    'annule' => TripState.cancelled,
    'termine' => TripState.done,
    _ => TripState.toConfirm,
  };
}

class MyTrip {
  const MyTrip({
    required this.bookingId,
    required this.state,
    required this.date,
    required this.route,
    required this.pickupTime,
    required this.arrivalTime,
    required this.priceFcfa,
    required this.driver,
    required this.vehicle,
    this.paymentId,
    this.paymentStatus,
    this.reference,
    this.operatorLabel,
    this.failureReason,
    this.driverPhone,
    this.pickupPoint,
    this.pickupInstructions,
    this.courseStatus = CourseStatus.notStarted,
    this.endValidated = false,
    this.myRating,
    this.driverPaid = false,
  });

  final int bookingId;
  final TripState state;
  final DateTime date;
  final String route;
  final String pickupTime;
  final String arrivalTime;
  final int priceFcfa;
  final String driver;
  final String vehicle;
  final int? paymentId;
  final PaymentStatus? paymentStatus;
  final String? reference;
  final String? operatorLabel;
  final String? failureReason;

  /// Numéro du conducteur, donné une fois la place payée.
  final String? driverPhone;
  final String? pickupPoint;
  final String? pickupInstructions;
  final CourseStatus courseStatus;

  /// Le passager a validé la fin de la course (et noté le conducteur).
  final bool endValidated;
  final int? myRating;

  /// Le conducteur a reçu l'argent : tout l'équipage a validé.
  final bool driverPaid;

  factory MyTrip.fromJson(Map<String, dynamic> json) => MyTrip(
    bookingId: (json['id_reservation'] as num).toInt(),
    state: TripState.fromCode(json['etat'] as String?),
    date: DateTime.parse(json['date_trajet'] as String),
    route: json['trajet'] as String? ?? '',
    pickupTime: json['prise_en_charge'] as String? ?? '',
    arrivalTime: json['arrivee'] as String? ?? '',
    priceFcfa: (json['prix_fcfa'] as num?)?.toInt() ?? 0,
    driver: json['conducteur'] as String? ?? '',
    vehicle: json['vehicule'] as String? ?? '',
    paymentId: (json['id_paiement'] as num?)?.toInt(),
    paymentStatus: json['statut_paiement'] == null ? null : paymentStatusFromCode(json['statut_paiement'] as String?),
    reference: json['reference'] as String?,
    operatorLabel: json['operateur'] as String?,
    failureReason: json['motif_echec'] as String?,
    driverPhone: json['conducteur_telephone'] as String?,
    pickupPoint: json['point_ramassage'] as String?,
    pickupInstructions: json['consignes_ramassage'] as String?,
    courseStatus: CourseStatus.fromCode(json['statut_course'] as String?),
    endValidated: json['fin_validee'] == true,
    myRating: (json['ma_note'] as num?)?.toInt(),
    driverPaid: json['conducteur_paye'] == true,
  );
}

/// État de la course côté conducteur : démarrée, arrivée, puis réglée (conducteur payé).
enum CourseStatus {
  notStarted('a_demarrer', 'Pas encore démarrée'),
  running('en_cours', 'En route'),
  arrived('arrivee', 'Arrivée à destination'),
  settled('reglee', 'Terminée et réglée');

  const CourseStatus(this.code, this.label);
  final String code;
  final String label;

  static CourseStatus fromCode(String? code) =>
      values.firstWhere((c) => c.code == code, orElse: () => CourseStatus.notStarted);
}

/// Un lieu avec ses coordonnées.
class GeoPlace {
  const GeoPlace({required this.label, required this.lat, required this.lng});

  final String label;
  final double lat;
  final double lng;

  factory GeoPlace.fromJson(Map<String, dynamic> json) => GeoPlace(
    label: json['libelle'] as String? ?? '',
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lon'] as num).toDouble(),
  );
}

/// Suivi d'une course par le passager (`GET /api/moi/reservations/{id}/suivi`).
class RideTracking {
  const RideTracking({
    required this.bookingId,
    required this.date,
    required this.paid,
    required this.courseStatus,
    required this.endValidated,
    required this.canValidate,
    required this.driver,
    required this.vehicle,
    required this.pickupTime,
    required this.arrivalTime,
    required this.priceFcfa,
    required this.pickupPoint,
    required this.from,
    required this.to,
    this.driverLastName,
    this.driverPhone,
    this.pickupInstructions,
    this.waitMinutes = 5,
  });

  final int bookingId;
  final DateTime date;
  final bool paid;
  final CourseStatus courseStatus;
  final bool endValidated;
  final bool canValidate;
  final String driver;
  final String? driverLastName;
  final String? driverPhone;
  final String vehicle;
  final String pickupTime;
  final String arrivalTime;
  final int priceFcfa;
  final String pickupPoint;
  final String? pickupInstructions;
  final int waitMinutes;

  /// Départ et destination du passager.
  final GeoPlace from;
  final GeoPlace to;

  factory RideTracking.fromJson(Map<String, dynamic> json) => RideTracking(
    bookingId: (json['id_reservation'] as num).toInt(),
    date: DateTime.parse(json['date_trajet'] as String),
    paid: json['paye'] == true,
    courseStatus: CourseStatus.fromCode(json['statut_course'] as String?),
    endValidated: json['fin_validee'] == true,
    canValidate: json['peut_valider'] == true,
    driver: json['conducteur'] as String? ?? '',
    driverLastName: json['conducteur_nom'] as String?,
    driverPhone: json['conducteur_telephone'] as String?,
    vehicle: json['vehicule'] as String? ?? '',
    pickupTime: json['prise_en_charge'] as String? ?? '',
    arrivalTime: json['arrivee'] as String? ?? '',
    priceFcfa: (json['prix_fcfa'] as num?)?.toInt() ?? 0,
    pickupPoint: json['point_ramassage'] as String? ?? '',
    pickupInstructions: json['consignes_ramassage'] as String?,
    waitMinutes: (json['attente_max_min'] as num?)?.toInt() ?? 5,
    from: GeoPlace.fromJson(json['depart'] as Map<String, dynamic>),
    to: GeoPlace.fromJson(json['destination'] as Map<String, dynamic>),
  );
}

/// Réponse à la validation de fin de course.
class EndOfRideResult {
  const EndOfRideResult({
    required this.message,
    required this.driver,
    required this.rating,
    required this.driverPaid,
    this.waitingFor = const [],
  });

  final String message;
  final String driver;
  final int rating;

  /// Tout l'équipage a validé : le conducteur a reçu son argent.
  final bool driverPaid;

  /// Passagers qui n'ont pas encore validé.
  final List<String> waitingFor;

  factory EndOfRideResult.fromJson(Map<String, dynamic> json) => EndOfRideResult(
    message: json['message'] as String? ?? "Merci d'avoir voyagé avec MboaRide !",
    driver: json['conducteur'] as String? ?? '',
    rating: (json['note'] as num?)?.toInt() ?? 0,
    driverPaid: json['conducteur_paye'] == true,
    waitingFor: [for (final p in (json['en_attente_de'] as List<dynamic>? ?? const [])) p as String],
  );
}

// --- Portefeuille ---------------------------------------------------------------------------

enum WalletMovementType {
  topUp('recharge'),
  payment('paiement'),
  refund('remboursement'),
  earning('gain'),
  withdrawal('retrait');

  const WalletMovementType(this.code);
  final String code;

  static WalletMovementType fromCode(String? code) =>
      values.firstWhere((t) => t.code == code, orElse: () => WalletMovementType.payment);
}

class WalletMovement {
  const WalletMovement({
    required this.type,
    required this.typeLabel,
    required this.amountFcfa,
    required this.balanceAfterFcfa,
    required this.label,
    this.reference,
    this.createdAt,
  });

  final WalletMovementType type;
  final String typeLabel;

  /// Positif pour un crédit, négatif pour un débit.
  final int amountFcfa;
  final int balanceAfterFcfa;
  final String label;
  final String? reference;
  final DateTime? createdAt;

  factory WalletMovement.fromJson(Map<String, dynamic> json) => WalletMovement(
    type: WalletMovementType.fromCode(json['type'] as String?),
    typeLabel: json['type_libelle'] as String? ?? '',
    amountFcfa: (json['montant_fcfa'] as num).toInt(),
    balanceAfterFcfa: (json['solde_apres_fcfa'] as num).toInt(),
    label: json['libelle'] as String? ?? '',
    reference: json['reference'] as String?,
    createdAt: DateTime.tryParse(json['cree_le'] as String? ?? '')?.toLocal(),
  );
}

/// Portefeuille MboaRide : solde, gains en attente (conducteur), paiements gardés par
/// MboaRide jusqu'à la fin de la course (passager), relevé.
class Wallet {
  const Wallet({
    required this.balanceFcfa,
    required this.autoTransfer,
    required this.movements,
    this.defaultAccount,
    this.pendingEarningsFcfa = 0,
    this.pendingPassengers = 0,
    this.escrowFcfa = 0,
    this.commissionFcfa = 0,
  });

  final int balanceFcfa;
  final bool autoTransfer;
  final MobileMoneyAccount? defaultAccount;
  final int pendingEarningsFcfa;
  final int pendingPassengers;
  final int escrowFcfa;
  final int commissionFcfa;
  final List<WalletMovement> movements;

  factory Wallet.fromJson(Map<String, dynamic> json) {
    final account = json['compte_par_defaut'] as Map<String, dynamic>?;
    return Wallet(
      balanceFcfa: (json['solde_fcfa'] as num).toInt(),
      autoTransfer: json['virement_auto'] == true,
      defaultAccount: account == null
          ? null
          : MobileMoneyAccount(
              id: (account['id_compte'] as num).toInt(),
              operator: MobileMoneyOperator.fromCode(account['operateur'] as String?),
              phone: account['telephone'] as String? ?? '',
              holder: account['titulaire'] as String? ?? '',
              isDefault: true,
            ),
      pendingEarningsFcfa: (json['gains_en_attente_fcfa'] as num?)?.toInt() ?? 0,
      pendingPassengers: (json['passagers_en_attente'] as num?)?.toInt() ?? 0,
      escrowFcfa: (json['paiements_en_sequestre_fcfa'] as num?)?.toInt() ?? 0,
      commissionFcfa: (json['commission_mboaride_fcfa'] as num?)?.toInt() ?? 0,
      movements: [
        for (final m in (json['mouvements'] as List<dynamic>? ?? const []))
          WalletMovement.fromJson(m as Map<String, dynamic>),
      ],
    );
  }
}


const List<String> _frenchDays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const List<String> _frenchMonths = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// « mercredi 18 novembre ».
String frenchDate(DateTime d) => '${_frenchDays[d.weekday - 1]} ${d.day} ${_frenchMonths[d.month - 1]}';
