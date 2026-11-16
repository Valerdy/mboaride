import '../../../core/api_client.dart';
import '../domain/bench_report.dart';

/// Banc de mesure du moteur multi-agents (US15).
abstract class BenchRepository {
  Future<List<BenchScenario>> scenarios();

  Future<BenchReport> run(String scenario, {int runs = 10});
}

class ApiBenchRepository implements BenchRepository {
  ApiBenchRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<BenchScenario>> scenarios() async {
    final body = await _client.get('/api/demo/banc') as List<dynamic>;
    return body
        .map((s) => BenchScenario.fromJson(s as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<BenchReport> run(String scenario, {int runs = 10}) async {
    final body =
        await _client.post('/api/demo/banc/$scenario?runs=$runs', const {});
    return BenchReport.fromJson(body as Map<String, dynamic>);
  }
}

/// Mesures simulées, du même ordre que celles du banc en local, pour pouvoir
/// montrer l'écran sans serveur.
class FakeBenchRepository implements BenchRepository {
  @override
  Future<List<BenchScenario>> scenarios() async => const [
    BenchScenario(code: 'S1', title: 'Matin ordinaire, 12 demandes'),
    BenchScenario(code: 'S3', title: 'Annulation du conducteur'),
    BenchScenario(code: 'S5', title: 'Charge : 40 demandes'),
  ];

  @override
  Future<BenchReport> run(String scenario, {int runs = 10}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final heavy = scenario == 'S5';
    final cancellation = scenario == 'S3';
    return BenchReport(
      scenario: scenario,
      runs: runs,
      convergenceMinS: heavy ? 0.214 : 0.058,
      convergenceMedianS: heavy ? 0.243 : 0.064,
      convergenceMaxS: heavy ? 0.287 : 0.071,
      reassignmentMaxS: cancellation ? 0.049 : null,
      roundsPerCrew: 1.18,
      messages: heavy ? 612 : 184,
      messagesPerCrew: heavy ? 16.1 : 15.3,
      maxMessagesPerCrew: heavy ? 19 : 18,
      byType: heavy
          ? const {
              'cfp': 40,
              'propose': 236,
              'accept': 38,
              'reject': 198,
              'inform': 100,
            }
          : const {
              'cfp': 12,
              'propose': 68,
              'accept': 12,
              'reject': 56,
              'inform': 36,
            },
      requests: heavy ? 40 : 12,
      crews: heavy ? 38 : 12,
      noCrew: heavy ? 2 : 0,
      cancelledCrews: cancellation ? 1 : 0,
      renegotiations: cancellation ? 1 : 0,
      reassigned: cancellation ? 1 : 0,
      deterministic: true,
      distinctFingerprints: 1,
      fingerprint: 'c41f9ab2d7e8054b',
      memoryPeakKibFirst: heavy ? 1842.0 : 736.0,
      memoryPeakKibLast: heavy ? 1859.0 : 741.0,
      memoryGrowthPct: heavy ? 0.9 : 0.7,
      targets: const {
        'convergence_under_2s': true,
        'under_20_messages_per_crew': true,
        'deterministic': true,
        'memory_stable': true,
      },
    );
  }
}
