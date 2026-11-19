import '../../../core/api_client.dart';
import '../../organisations/domain/organisation.dart' show School;
import '../domain/child.dart';

/// Comptes élèves et journal des trajets (US17, US19).
abstract class ChildrenRepository {
  Future<List<Child>> children();

  Future<Child> addChild({
    required String firstName,
    required int age,
    int? schoolId,
  });

  Future<Child> setAuthorization(int childId, bool authorized);

  Future<List<ChildEvent>> journal(int childId);

  /// Écoles et campus connus, pour rattacher l'élève à son établissement.
  Future<List<School>> schools();

  /// Démonstration (US19 est simulée) : produit les notifications de départ et d'arrivée du dernier
  /// voyage de l'élève. Échoue s'il n'a aucune réservation confirmée.
  Future<void> simulateRide(int childId);
}

class ApiChildrenRepository implements ChildrenRepository {
  ApiChildrenRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<Child>> children() async {
    final body = await _client.get('/api/moi/eleves') as List<dynamic>;
    return body
        .map((e) => Child.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Child> addChild({
    required String firstName,
    required int age,
    int? schoolId,
  }) async {
    final body = await _client.post('/api/moi/eleves', {
      'prenom': firstName,
      'age': age,
      if (schoolId != null) 'id_etablissement': schoolId,
    });
    return Child.fromJson(body as Map<String, dynamic>);
  }

  @override
  Future<Child> setAuthorization(int childId, bool authorized) async {
    final body = await _client.put(
      '/api/moi/eleves/$childId/autorisation',
      {'active': authorized},
    );
    return Child.fromJson(body as Map<String, dynamic>);
  }

  @override
  Future<void> simulateRide(int childId) async {
    await _client.post('/api/moi/eleves/$childId/simuler-trajet');
  }

  @override
  Future<List<School>> schools() async {
    final body = await _client.get('/api/etablissements') as List<dynamic>;
    return body.map((s) => School.fromJson(s as Map<String, dynamic>)).toList(growable: false);
  }

  @override
  Future<List<ChildEvent>> journal(int childId) async {
    final body =
        await _client.get('/api/moi/eleves/$childId/journal') as List<dynamic>;
    return body
        .map((e) => ChildEvent.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}

/// Données simulées : les écrans tournent sans serveur (FAKE_API=true).
class FakeChildrenRepository implements ChildrenRepository {
  final List<Child> _children = [
    const Child(
      id: 1,
      firstName: 'Ange',
      age: 12,
      school: 'Collège B (Bonapriso)',
      schoolId: 3,
      authorized: true,
    ),
    const Child(
      id: 2,
      firstName: 'Marc',
      age: 15,
      school: 'Collège B (Bonapriso)',
      schoolId: 3,
      authorized: false,
    ),
  ];

  int _nextId = 3;

  @override
  Future<List<Child>> children() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return List.unmodifiable(_children);
  }

  @override
  Future<Child> addChild({
    required String firstName,
    required int age,
    int? schoolId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final child = Child(
      id: _nextId++,
      firstName: firstName,
      age: age,
      school: schoolId == null ? null : 'Collège B (Bonapriso)',
      schoolId: schoolId,
      authorized: true,
    );
    _children.add(child);
    return child;
  }

  @override
  Future<Child> setAuthorization(int childId, bool authorized) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final index = _children.indexWhere((c) => c.id == childId);
    final previous = _children[index];
    final updated = Child(
      id: previous.id,
      firstName: previous.firstName,
      age: previous.age,
      school: previous.school,
      schoolId: previous.schoolId,
      authorized: authorized,
    );
    _children[index] = updated;
    return updated;
  }

  @override
  Future<void> simulateRide(int childId) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (childId != 1) throw ApiException('Aucune réservation confirmée pour cet élève');
  }

  @override
  Future<List<School>> schools() async => const [
    School(id: 3, name: 'Collège B (Bonapriso)'),
    School(id: 4, name: 'Campus C'),
  ];

  @override
  Future<List<ChildEvent>> journal(int childId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (childId != 1) return const [];
    return const [
      ChildEvent(
        kind: 'reservation',
        label: 'Place confirmée pour le trajet du matin',
        at: 'hier 19:12',
        driver: 'Armand Essomba',
      ),
      ChildEvent(
        kind: 'depart',
        label: 'Ange est montée à bord à Makepe à 06:52.',
        at: 'aujourd\'hui 06:52',
        driver: 'Armand Essomba',
      ),
      ChildEvent(
        kind: 'arrivee',
        label: 'Ange est arrivée à Bonapriso à 07:24.',
        at: 'aujourd\'hui 07:24',
        driver: 'Armand Essomba',
      ),
    ];
  }
}
