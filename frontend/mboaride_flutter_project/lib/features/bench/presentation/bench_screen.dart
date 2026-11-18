import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/bench_repository.dart';
import '../domain/bench_report.dart';

/// US15 · Lancer un scénario simulé et afficher le temps de convergence, les
/// messages échangés et la mémoire, pour prouver la performance du système.
///
/// Les quatre mesures correspondent aux quatre critères de la grille
/// « Maquette » : cycles sous deux secondes, charge de communication,
/// indéterminisme et utilisation de la mémoire.
class BenchScreen extends StatefulWidget {
  const BenchScreen({super.key, required this.repository});

  final BenchRepository repository;

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> {
  List<BenchScenario> _scenarios = const [];
  String? _selected;
  int _runs = 10;
  BenchReport? _report;
  bool _loading = true;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scenarios = await widget.repository.scenarios();
      if (!mounted) return;
      setState(() {
        _scenarios = scenarios;
        _selected = scenarios.isEmpty ? null : scenarios.first.code;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _run() async {
    final scenario = _selected;
    if (scenario == null) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final report = await widget.repository.run(scenario, runs: _runs);
      if (!mounted) return;
      setState(() {
        _report = report;
        _running = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Banc de mesure du moteur')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chaque exécution rejoue le scénario complet. Le banc '
                      'mesure le temps de convergence, le nombre de messages '
                      'échangés, l\'empreinte du résultat (pour vérifier que '
                      'la solution ne change pas d\'une exécution à l\'autre) '
                      'et le pic de mémoire.',
                      style: TextStyle(
                        fontSize: 14,
                        color: MboaColors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Controls(
                      scenarios: _scenarios,
                      selected: _selected,
                      runs: _runs,
                      running: _running,
                      onScenario: (code) => setState(() => _selected = code),
                      onRuns: (runs) => setState(() => _runs = runs),
                      onRun: _run,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: MboaColors.red),
                        ),
                      ),
                    if (_report != null) ...[
                      const SizedBox(height: 24),
                      _Verdict(report: _report!),
                      const SizedBox(height: 20),
                      _Measures(report: _report!),
                    ],
                  ],
                ),
              ),
            ),
          ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.scenarios,
    required this.selected,
    required this.runs,
    required this.running,
    required this.onScenario,
    required this.onRuns,
    required this.onRun,
  });

  final List<BenchScenario> scenarios;
  final String? selected;
  final int runs;
  final bool running;
  final ValueChanged<String> onScenario;
  final ValueChanged<int> onRuns;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: MboaColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Scénario',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: MboaColors.night,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: scenarios
              .map(
                (scenario) => ChoiceChip(
                  selected: scenario.code == selected,
                  onSelected: (_) => onScenario(scenario.code),
                  label: Text('${scenario.code} · ${scenario.title}'),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text(
              'Exécutions',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: MboaColors.night,
              ),
            ),
            const SizedBox(width: 14),
            ...[5, 10, 20].map(
              (value) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: value == runs,
                  onSelected: (_) => onRuns(value),
                  label: Text(value.toString()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: running || selected == null ? null : onRun,
          icon: const Icon(Icons.play_arrow),
          label: Text(running ? 'Mesure en cours...' : 'Lancer la mesure'),
        ),
      ],
    ),
  );
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.report});

  final BenchReport report;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: MboaColors.night,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scénario ${report.scenario} · ${report.runs} exécutions',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${report.crews} équipage(s) formé(s) sur ${report.requests} demande(s)'
          '${report.noCrew == 0 ? '' : ', ${report.noCrew} sans équipage'}'
          '${report.renegotiations == 0 ? '' : ', ${report.reassigned} réaffecté(s) après annulation'}.',
          style: const TextStyle(fontSize: 13, color: Color(0xFFCBD6CF)),
        ),
        const SizedBox(height: 16),
        ...benchTargetLabels.entries.map((entry) {
          final met = report.targets[entry.key];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  met == true ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: met == true ? MboaColors.sun : MboaColors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ),
                Text(
                  met == null
                      ? 'non mesurée'
                      : met
                      ? 'atteinte'
                      : 'non atteinte',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: met == true ? MboaColors.sun : MboaColors.red,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    ),
  );
}

class _Measures extends StatelessWidget {
  const _Measures({required this.report});

  final BenchReport report;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _MeasureCard(
        title: 'Convergence',
        lines: [
          '${report.ms(report.convergenceMedianS)} en médiane',
          'min ${report.ms(report.convergenceMinS)} · max ${report.ms(report.convergenceMaxS)}',
          if (report.roundsPerCrew != null)
            '${report.roundsPerCrew!.toStringAsFixed(2).replaceAll('.', ',')} tour(s) d\'appel d\'offres par équipage',
          if (report.reassignmentMaxS != null)
            'réaffectation la plus longue : ${report.ms(report.reassignmentMaxS!)}',
          'cible de la grille : moins de 2 secondes',
        ],
      ),
      _MeasureCard(
        title: 'Charge de communication',
        lines: [
          '${report.messages} messages au total',
          if (report.messagesPerCrew != null)
            '${report.messagesPerCrew!.toStringAsFixed(1).replaceAll('.', ',')} par équipage (max ${report.maxMessagesPerCrew})',
          ...report.byType.entries.map((e) => '${e.key} : ${e.value}'),
        ],
      ),
      _MeasureCard(
        title: 'Déterminisme',
        lines: [
          report.deterministic
              ? 'Une seule empreinte sur ${report.runs} exécutions'
              : '${report.distinctFingerprints} empreintes distinctes sur ${report.runs}',
          'empreinte : ${report.fingerprint.length <= 16 ? report.fingerprint : report.fingerprint.substring(0, 16)}',
          'le même scénario rejoué donne la même affectation',
        ],
      ),
      _MeasureCard(
        title: 'Mémoire',
        lines: [
          if (report.memoryPeakKibFirst != null)
            'pic ${report.memoryPeakKibFirst!.round()} Kio à la 1re exécution',
          if (report.memoryPeakKibLast != null)
            'pic ${report.memoryPeakKibLast!.round()} Kio à la dernière',
          if (report.memoryGrowthPct != null)
            'écart ${report.memoryGrowthPct! >= 0 ? '+' : ''}${report.memoryGrowthPct!.toStringAsFixed(1).replaceAll('.', ',')} %',
          'cible de la grille : moins de 5 % d\'écart',
        ],
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 20) / 2;
        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(growable: false),
        );
      },
    );
  }
}

class _MeasureCard extends StatelessWidget {
  const _MeasureCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: MboaColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MboaColors.night,
          ),
        ),
        const SizedBox(height: 10),
        ...lines.map(
          (line) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              line,
              style: const TextStyle(fontSize: 13, color: MboaColors.night),
            ),
          ),
        ),
      ],
    ),
  );
}
