/// Compte élève rattaché à un parent (US17) et journal de ses trajets (US19).
class Child {
  const Child({
    required this.id,
    required this.name,
    required this.age,
    required this.school,
    required this.authorized,
  });

  final int id;
  final String name;
  final int age;
  final String school;

  /// Autorisation parentale : sans elle, aucune réservation n'est possible
  /// (règle appliquée aussi par la base, déclencheur `autorisation_eleve`).
  final bool authorized;

  factory Child.fromJson(Map<String, dynamic> json) => Child(
    id: (json['id_eleve'] as num?)?.toInt() ?? 0,
    name: json['nom'] as String? ?? '',
    age: (json['age'] as num?)?.toInt() ?? 0,
    school: json['ecole'] as String? ?? '',
    authorized: json['autorisation_active'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'nom': name,
    'age': age,
    'ecole': school,
  };

  /// Règle produit : les comptes élèves sont réservés aux 12 ans et plus.
  static const int minimumAge = 12;

  static String? validate({
    required String name,
    required String ageText,
    required String school,
  }) {
    if (name.trim().length < 2) return 'Indiquez le nom de l\'élève.';
    final age = int.tryParse(ageText.trim());
    if (age == null) return 'Indiquez l\'âge en chiffres.';
    if (age < minimumAge) {
      return 'MboaRide n\'accepte les élèves qu\'à partir de $minimumAge ans.';
    }
    if (age > 25) return 'Vérifiez l\'âge saisi.';
    if (school.trim().length < 2) return 'Indiquez l\'établissement.';
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
