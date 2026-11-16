/// Rapport du banc de mesure du moteur multi-agents (US15), tel que
/// `mboaride_agents.bench.run_scenario(...).to_dict()` le produit.
class BenchReport {
  const BenchReport({
    required this.scenario,
    required this.runs,
    required this.convergenceMinS,
    required this.convergenceMedianS,
    required this.convergenceMaxS,
    required this.messages,
    required this.requests,
    required this.crews,
    required this.noCrew,
    required this.deterministic,
    required this.distinctFingerprints,
    required this.fingerprint,
    required this.targets,
    this.reassignmentMaxS,
    this.roundsPerCrew,
    this.messagesPerCrew,
    this.maxMessagesPerCrew,
    this.byType = const {},
    this.cancelledCrews = 0,
    this.renegotiations = 0,
    this.reassigned = 0,
    this.memoryPeakKibFirst,
    this.memoryPeakKibLast,
    this.memoryGrowthPct,
  });

  final String scenario;
  final int runs;

  // Convergence
  final double convergenceMinS;
  final double convergenceMedianS;
  final double convergenceMaxS;
  final double? reassignmentMaxS;
  final double? roundsPerCrew;

  // Charge de communication
  final int messages;
  final double? messagesPerCrew;
  final int? maxMessagesPerCrew;
  final Map<String, int> byType;

  // Résultat de la négociation
  final int requests;
  final int crews;
  final int noCrew;
  final int cancelledCrews;
  final int renegotiations;
  final int reassigned;

  // Déterminisme
  final bool deterministic;
  final int distinctFingerprints;
  final String fingerprint;

  // Mémoire
  final double? memoryPeakKibFirst;
  final double? memoryPeakKibLast;
  final double? memoryGrowthPct;

  /// Cibles de la grille : `convergence_under_2s`, `under_20_messages_per_crew`,
  /// `deterministic`, `memory_stable`.
  final Map<String, bool> targets;

  bool get allTargetsMet => targets.values.every((ok) => ok);

  String ms(double seconds) =>
      '${(seconds * 1000).toStringAsFixed(1).replaceAll('.', ',')} ms';

  factory BenchReport.fromJson(Map<String, dynamic> json) {
    final convergence =
        (json['convergence_s'] as Map<String, dynamic>?) ?? const {};
    return BenchReport(
      scenario: json['scenario'] as String? ?? '',
      runs: (json['runs'] as num?)?.toInt() ?? 0,
      convergenceMinS: (convergence['min'] as num?)?.toDouble() ?? 0,
      convergenceMedianS: (convergence['median'] as num?)?.toDouble() ?? 0,
      convergenceMaxS: (convergence['max'] as num?)?.toDouble() ?? 0,
      reassignmentMaxS: (json['reassignment_max_s'] as num?)?.toDouble(),
      roundsPerCrew: (json['rounds_per_crew'] as num?)?.toDouble(),
      messages: (json['messages'] as num?)?.toInt() ?? 0,
      messagesPerCrew: (json['messages_per_crew'] as num?)?.toDouble(),
      maxMessagesPerCrew: (json['max_messages_per_crew'] as num?)?.toInt(),
      byType: ((json['by_type'] as Map<String, dynamic>?) ?? const {}).map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      ),
      requests: (json['requests'] as num?)?.toInt() ?? 0,
      crews: (json['crews'] as num?)?.toInt() ?? 0,
      noCrew: (json['no_crew'] as num?)?.toInt() ?? 0,
      cancelledCrews: (json['cancelled_crews'] as num?)?.toInt() ?? 0,
      renegotiations: (json['renegotiations'] as num?)?.toInt() ?? 0,
      reassigned: (json['reassigned'] as num?)?.toInt() ?? 0,
      deterministic: json['deterministic'] as bool? ?? false,
      distinctFingerprints:
          (json['distinct_fingerprints'] as num?)?.toInt() ?? 0,
      fingerprint: json['fingerprint'] as String? ?? '',
      memoryPeakKibFirst: (json['memory_peak_kib_first'] as num?)?.toDouble(),
      memoryPeakKibLast: (json['memory_peak_kib_last'] as num?)?.toDouble(),
      memoryGrowthPct: (json['memory_growth_pct'] as num?)?.toDouble(),
      targets: ((json['targets'] as Map<String, dynamic>?) ?? const {}).map(
        (key, value) => MapEntry(key, value == true),
      ),
    );
  }
}

/// Scénario proposé par le banc de mesure.
class BenchScenario {
  const BenchScenario({required this.code, required this.title});

  final String code;
  final String title;

  factory BenchScenario.fromJson(Map<String, dynamic> json) => BenchScenario(
    code: json['code'] as String? ?? '',
    title: json['titre'] as String? ?? '',
  );
}

/// Libellés français des quatre cibles de la grille.
const Map<String, String> benchTargetLabels = {
  'convergence_under_2s': 'Convergence en moins de 2 secondes',
  'under_20_messages_per_crew': 'Moins de 20 messages par équipage',
  'deterministic': 'Même solution à chaque exécution',
  'memory_stable': 'Mémoire stable d\'une exécution à l\'autre',
};
