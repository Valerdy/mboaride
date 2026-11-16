import '../../../core/api_client.dart';
import '../domain/child.dart';

/// Comptes élèves et journal des trajets (US17, US19).
abstract class ChildrenRepository {
  Future<List<Child>> children();

  Future<Child> addChild({
    required String name,
    required int age,
    required String school,
  });

  Future<Child> setAuthorization(int childId, bool authorized);

  Future<List<ChildEvent>> journal(int childId);
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
    required String name,
    required int age,
    required String school,
  }) async {
    final body = await _client.post('/api/moi/eleves', {
      'nom': name,
      'age': age,
      'ecole': school,
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
      name: 'Ariane Mbarga',
      age: 14,
      school: 'Collège Saint-Michel, Bonabéri',
      authorized: true,
    ),
    const Child(
      id: 2,
      name: 'Yves Mbarga',
      age: 12,
      school: 'Collège Saint-Michel, Bonabéri',
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
    required String name,
    required int age,
    required String school,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final child = Child(
      id: _nextId++,
      name: name,
      age: age,
      school: school,
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
      name: previous.name,
      age: previous.age,
      school: previous.school,
      authorized: authorized,
    );
    _children[index] = updated;
    return updated;
  }

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
        label: 'Montée à bord à Bonabéri',
        at: 'aujourd\'hui 06:52',
        driver: 'Armand Essomba',
      ),
      ChildEvent(
        kind: 'arrivee',
        label: 'Déposée au collège Saint-Michel',
        at: 'aujourd\'hui 07:24',
        driver: 'Armand Essomba',
      ),
    ];
  }
}
