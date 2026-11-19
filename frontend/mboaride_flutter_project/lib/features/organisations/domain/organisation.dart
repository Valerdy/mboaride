/// Organisation dont la personne fait partie : entreprise, école, campus ou événement.
class Organisation {
  const Organisation({required this.id, required this.name, required this.type, required this.role});

  final int id;
  final String name;
  final String type;

  /// « membre » ou « administrateur ».
  final String role;

  bool get isAdmin => role == 'administrateur';

  factory Organisation.fromJson(Map<String, dynamic> json) => Organisation(
    id: (json['id_organisation'] as num?)?.toInt() ?? 0,
    name: json['nom'] as String? ?? '',
    type: json['type_organisation'] as String? ?? 'entreprise',
    role: json['role'] as String? ?? 'membre',
  );

  String get typeLabel => switch (type) {
    'etablissement_scolaire' => 'École',
    'campus' => 'Campus',
    'evenement' => 'Événement',
    _ => 'Entreprise',
  };
}

/// École ou campus connu de MboaRide, proposé quand on ajoute un compte élève.
class School {
  const School({required this.id, required this.name});

  final int id;
  final String name;

  factory School.fromJson(Map<String, dynamic> json) =>
      School(id: (json['id'] as num?)?.toInt() ?? 0, name: json['nom'] as String? ?? '');
}
