import '../../../core/api_client.dart';
import '../domain/console.dart';

/// Console entreprise : invitations, adoption et impact (US13, US14).
abstract class ConsoleRepository {
  Future<List<Organisation>> organisations();

  Future<Adoption> adoption(int organisationId);

  Future<Impact> impact(int organisationId);

  Future<List<Invitation>> invitations(int organisationId);

  Future<InvitationResult> invite({
    required int organisationId,
    required List<String> emails,
    String? service,
  });

  Future<Invitation> remind(int organisationId, int invitationId);

  /// Adresse de l'export CSV du bilan, à ouvrir dans un onglet (US14).
  String impactCsvUrl(int organisationId);
}

class ApiConsoleRepository implements ConsoleRepository {
  ApiConsoleRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<Organisation>> organisations() async {
    final body = await _client.get('/api/moi/organisations') as List<dynamic>;
    return body
        .map((o) => Organisation.fromJson(o as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Adoption> adoption(int organisationId) async {
    final body = await _client.get('/api/organisations/$organisationId/adoption');
    return Adoption.fromJson(body as Map<String, dynamic>);
  }

  @override
  Future<Impact> impact(int organisationId) async {
    final body = await _client.get('/api/organisations/$organisationId/impact');
    return Impact.fromJson(body as Map<String, dynamic>);
  }

  @override
  Future<List<Invitation>> invitations(int organisationId) async {
    final body =
        await _client.get('/api/organisations/$organisationId/invitations')
            as List<dynamic>;
    return body
        .map((i) => Invitation.fromJson(i as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<InvitationResult> invite({
    required int organisationId,
    required List<String> emails,
    String? service,
  }) async {
    final body = await _client
        .post('/api/organisations/$organisationId/invitations', {
          'emails': emails,
          if (service != null && service.isNotEmpty) 'service': service,
        });
    return InvitationResult.fromJson(body as Map<String, dynamic>);
  }

  @override
  Future<Invitation> remind(int organisationId, int invitationId) async {
    final body = await _client.post(
      '/api/organisations/$organisationId/invitations/$invitationId/relance',
      const {},
    );
    final map = body as Map<String, dynamic>;
    return Invitation(
      id: invitationId,
      email: map['email'] as String? ?? '',
      status: 'envoyee',
      reminders: (map['relances'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String impactCsvUrl(int organisationId) =>
      '${_client.baseUrl}/api/organisations/$organisationId/impact.csv';
}

/// Données simulées, calquées sur « Entreprise A » du jeu de démonstration.
class FakeConsoleRepository implements ConsoleRepository {
  final List<Invitation> _invitations = [
    const Invitation(
      id: 1,
      email: 'grace.ndongo@entreprise-a.cm',
      status: 'acceptee',
      reminders: 0,
      service: 'Finance',
      member: 'Grâce Ndongo',
      trips: 18,
    ),
    const Invitation(
      id: 2,
      email: 'armand.essomba@entreprise-a.cm',
      status: 'acceptee',
      reminders: 1,
      service: 'Production',
      member: 'Armand Essomba',
      trips: 23,
    ),
    const Invitation(
      id: 3,
      email: 'nadege.fokou@entreprise-a.cm',
      status: 'envoyee',
      reminders: 2,
      service: 'Finance',
    ),
    const Invitation(
      id: 4,
      email: 'serge.biya@entreprise-a.cm',
      status: 'envoyee',
      reminders: 3,
      service: 'Logistique',
    ),
    const Invitation(
      id: 5,
      email: 'claire.manga@entreprise-a.cm',
      status: 'expiree',
      reminders: 3,
      service: 'Logistique',
    ),
  ];

  int _nextId = 6;

  @override
  Future<List<Organisation>> organisations() async => const [
    Organisation(
      id: 1,
      name: 'Entreprise A',
      kind: 'entreprise',
      role: 'administrateur',
    ),
  ];

  @override
  Future<Adoption> adoption(int organisationId) async => Adoption(
    organisation: 'Entreprise A',
    headcount: 120,
    members: _invitations.where((i) => i.status == 'acceptee').length + 60,
    approvedDrivers: 14,
    activeMembers30d: 48,
    rate: 0.517,
    target: 0.6,
    targetReached: false,
    missingForTarget: 10,
    byService: const [
      (service: 'Production', members: 26, active: 21),
      (service: 'Finance', members: 18, active: 12),
      (service: 'Logistique', members: 12, active: 9),
      (service: 'Direction', members: 6, active: 6),
    ],
  );

  @override
  Future<Impact> impact(int organisationId) async => const Impact(
    organisation: 'Entreprise A',
    from: '2026-09-01',
    to: '2026-11-30',
    sharedTrips: 742,
    kmAvoided: 6834.5,
    litresAvoided: 546.8,
    co2CarefulKg: 421.0,
    co2HighKg: 1263.1,
    employeeSavingsFcfa: 3421000,
    employeeSpendFcfa: 1289000,
    subscriptionCostFcfa: 279000,
    subscribers: 62,
    savingsPerFcfa: 12.3,
  );

  @override
  Future<List<Invitation>> invitations(int organisationId) async =>
      List.unmodifiable(_invitations);

  @override
  Future<InvitationResult> invite({
    required int organisationId,
    required List<String> emails,
    String? service,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final sent = <String>[];
    final rejected = <({String email, String reason})>[];
    for (final raw in emails) {
      final email = raw.trim().toLowerCase();
      if (email.isEmpty) continue;
      if (!email.contains('@') || !email.contains('.')) {
        rejected.add((email: email, reason: 'adresse invalide'));
      } else if (!email.endsWith('@entreprise-a.cm')) {
        rejected.add((email: email, reason: 'hors du domaine entreprise-a.cm'));
      } else if (_invitations.any((i) => i.email == email)) {
        rejected.add((email: email, reason: 'déjà invitée, utilisez la relance'));
      } else {
        _invitations.add(
          Invitation(
            id: _nextId++,
            email: email,
            status: 'envoyee',
            reminders: 0,
            service: service,
          ),
        );
        sent.add(email);
      }
    }
    return InvitationResult(
      sent: sent,
      rejected: rejected,
      note: sent.isEmpty
          ? 'Aucune invitation envoyée.'
          : '${sent.length} invitation(s) envoyée(s).',
    );
  }

  @override
  Future<Invitation> remind(int organisationId, int invitationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final index = _invitations.indexWhere((i) => i.id == invitationId);
    final previous = _invitations[index];
    final updated = Invitation(
      id: previous.id,
      email: previous.email,
      status: previous.status,
      reminders: previous.reminders + 1,
      service: previous.service,
      member: previous.member,
      trips: previous.trips,
    );
    _invitations[index] = updated;
    return updated;
  }

  @override
  String impactCsvUrl(int organisationId) =>
      '/api/organisations/$organisationId/impact.csv';
}
