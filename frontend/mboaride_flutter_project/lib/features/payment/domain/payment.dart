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
  );
}

const List<String> _frenchDays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const List<String> _frenchMonths = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// « mercredi 18 novembre ».
String frenchDate(DateTime d) => '${_frenchDays[d.weekday - 1]} ${d.day} ${_frenchMonths[d.month - 1]}';
