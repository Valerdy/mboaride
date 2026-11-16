/// Compte élève rattaché à un parent (US17) et journal de ses trajets (US19).
class Child {
  const Child({
    required this.id,
    required this.firstName,
    required this.age,
    required this.authorized,
    this.school,
    this.schoolId,
    this.notifyDeparture = true,
    this.notifyArrival = true,
  });

  final int id;

  /// Prénom seul : la base ne garde que le prénom et l'âge déclaré de l'élève
  /// (minimisation des données).
  final String firstName;
  final int age;
  final String? school;
  final int? schoolId;
  final bool notifyDeparture;
  final bool notifyArrival;

  /// Autorisation parentale : sans elle, aucune réservation n'est possible
  /// (règle appliquée aussi par la base, déclencheur `autorisation_eleve`).
  final bool authorized;

  factory Child.fromJson(Map<String, dynamic> json) => Child(
    id: (json['id_eleve'] as num?)?.toInt() ?? 0,
    firstName: json['prenom'] as String? ?? '',
    age: (json['age'] as num?)?.toInt() ?? 0,
    school: json['etablissement'] as String?,
    schoolId: (json['id_etablissement'] as num?)?.toInt(),
    authorized: json['autorisation_active'] as bool? ?? false,
    notifyDeparture: json['notifier_depart'] as bool? ?? true,
    notifyArrival: json['notifier_arrivee'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'prenom': firstName,
    'age': age,
    if (schoolId != null) 'id_etablissement': schoolId,
  };

  /// Règle produit et contrainte de la base : un compte élève va de 12 à 17 ans.
  static const int minimumAge = 12;
  static const int maximumAge = 17;

  /// Établissement affiché, ou une mention claire quand il n'est pas renseigné.
  String get schoolLabel =>
      school == null || school!.isEmpty ? 'Établissement non renseigné' : school!;

  static String? validate({
    required String firstName,
    required String ageText,
  }) {
    if (firstName.trim().length < 2) return 'Indiquez le prénom de l\'élève.';
    final age = int.tryParse(ageText.trim());
    if (age == null) return 'Indiquez l\'âge en chiffres.';
    if (age < minimumAge || age > maximumAge) {
      return 'Un compte élève va de $minimumAge à $maximumAge ans.';
    }
    return null;
  }
}

/// Une ligne du journal d'un élève : réservation, départ, arrivée.
class ChildEvent {
  const ChildEvent({
    required this.kind,
    required this.label,
    required this.at,
    this.driver,
  });

  /// `reservation`, `depart` ou `arrivee`.
  final String kind;
  final String label;
  final String at;
  final String? driver;

  factory ChildEvent.fromJson(Map<String, dynamic> json) => ChildEvent(
    kind: json['type'] as String? ?? 'reservation',
    label: json['libelle'] as String? ?? '',
    at: json['horodatage'] as String? ?? '',
    driver: json['conducteur'] as String?,
  );

  bool get isArrival => kind == 'arrivee';
  bool get isDeparture => kind == 'depart';
}
