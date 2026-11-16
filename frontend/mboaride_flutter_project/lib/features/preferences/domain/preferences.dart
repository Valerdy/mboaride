/// Exigences de confort, cercle de confiance et mode de réservation (US02).
///
/// Ces réglages ne décident rien à eux seuls : ils sont traduits en paramètres
/// que les agents respectent pendant la négociation.
library;

/// Cercle de confiance, du plus proche au plus large. Les cercles sont emboîtés :
/// accepter le public suppose d'accepter les partenaires.
enum Circle {
  organisation('organisation', 'Collègues', 'Uniquement mon organisation'),
  partenaires('partenaires', 'Partenaires', 'Mon organisation et ses partenaires'),
  public('public', 'Public vérifié', 'Tout conducteur agréé par MboaRide');

  const Circle(this.code, this.label, this.description);

  final String code;
  final String label;
  final String description;

  static Circle fromCode(String? code) =>
      Circle.values.firstWhere((c) => c.code == code, orElse: () => Circle.organisation);
}

/// Mode manuel : l'utilisateur choisit parmi les offres.
/// Mode autonome : la meilleure offre est réservée sans intervention.
enum BookingMode {
  manuel('manuel', 'Manuel', 'Je choisis parmi les offres proposées'),
  autonome('autonome', 'Autonome', 'Les agents réservent et me réaffectent seuls');

  const BookingMode(this.code, this.label, this.description);

  final String code;
  final String label;
  final String description;

  static BookingMode fromCode(String? code) => BookingMode.values
      .firstWhere((m) => m.code == code, orElse: () => BookingMode.manuel);
}

/// Critère départageant deux offres acceptables.
enum RidePriority {
  heure('heure', "L'heure d'arrivée"),
  prix('prix', 'Le prix');

  const RidePriority(this.code, this.label);

  final String code;
  final String label;

  static RidePriority fromCode(String? code) => RidePriority.values
      .firstWhere((p) => p.code == code, orElse: () => RidePriority.heure);
}

class Preferences {
  const Preferences({
    required this.airConditioning,
    required this.nonSmoking,
    required this.quiet,
    required this.maxPriceFcfa,
    required this.circle,
    required this.mode,
    required this.priority,
  });

  final bool airConditioning;
  final bool nonSmoking;
  final bool quiet;
  final int maxPriceFcfa;
  final Circle circle;
  final BookingMode mode;
  final RidePriority priority;

  static const int minPriceFcfa = 50;
  static const int maxAllowedPriceFcfa = 20000;

  factory Preferences.fromJson(Map<String, dynamic> json) {
    final comfort = json['confort'] as Map<String, dynamic>? ?? const {};
    return Preferences(
      airConditioning: comfort['climatisation'] == true,
      nonSmoking: comfort['non_fumeur'] == true,
      quiet: comfort['silence'] == true,
      maxPriceFcfa: (json['prix_max_fcfa'] as num?)?.toInt() ?? 500,
      circle: Circle.fromCode(json['cercle'] as String?),
      mode: BookingMode.fromCode(json['mode'] as String?),
      priority: RidePriority.fromCode(json['priorite'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'confort': {
      'climatisation': airConditioning,
      'non_fumeur': nonSmoking,
      'silence': quiet,
    },
    'prix_max_fcfa': maxPriceFcfa,
    'cercle': circle.code,
    'mode': mode.code,
    'priorite': priority.code,
  };

  Preferences copyWith({
    bool? airConditioning,
    bool? nonSmoking,
    bool? quiet,
    int? maxPriceFcfa,
    Circle? circle,
    BookingMode? mode,
    RidePriority? priority,
  }) => Preferences(
    airConditioning: airConditioning ?? this.airConditioning,
    nonSmoking: nonSmoking ?? this.nonSmoking,
    quiet: quiet ?? this.quiet,
    maxPriceFcfa: maxPriceFcfa ?? this.maxPriceFcfa,
    circle: circle ?? this.circle,
    mode: mode ?? this.mode,
    priority: priority ?? this.priority,
  );

  /// Message d'erreur sur le prix maximal, ou null s'il est acceptable.
  String? get priceError {
    if (maxPriceFcfa < minPriceFcfa) {
      return 'Le prix maximal doit être d\'au moins $minPriceFcfa FCFA.';
    }
    if (maxPriceFcfa > maxAllowedPriceFcfa) {
      return 'Le prix maximal ne peut pas dépasser $maxAllowedPriceFcfa FCFA.';
    }
    return null;
  }
}
