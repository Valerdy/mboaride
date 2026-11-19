import '../../../core/api_client.dart';
import '../domain/organisation.dart';

/// Mes organisations : lister, rejoindre avec un code, quitter.
abstract class OrganisationsRepository {
  Future<List<Organisation>> mine();

  /// Rejoint l'organisation qui porte ce code. Erreur claire si le code est inconnu, si la personne
  /// en fait déjà partie, ou si l'entreprise est réservée à un nom de domaine d'e-mail.
  Future<Organisation> join(String code);

  Future<void> leave(int organisationId);
}

class ApiOrganisationsRepository implements OrganisationsRepository {
  ApiOrganisationsRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<Organisation>> mine() async {
    final body = await _client.get('/api/moi/organisations') as List<dynamic>;
    return body.map((o) => Organisation.fromJson(o as Map<String, dynamic>)).toList(growable: false);
  }

  @override
  Future<Organisation> join(String code) async => Organisation.fromJson(
    await _client.post('/api/moi/organisations/rejoindre', {'code': code.trim()}) as Map<String, dynamic>,
  );

  @override
  Future<void> leave(int organisationId) async {
    await _client.delete('/api/moi/organisations/$organisationId');
  }
}

/// Données simulées (FAKE_API=true) : un collège connu par son code.
class FakeOrganisationsRepository implements OrganisationsRepository {
  final List<Organisation> _mine = [
    const Organisation(id: 1, name: 'Entreprise A (Bonanjo)', type: 'entreprise', role: 'membre'),
  ];

  @override
  Future<List<Organisation>> mine() async => List.unmodifiable(_mine);

  @override
  Future<Organisation> join(String code) async {
    if (code.trim().toUpperCase() != 'COLB-2026') throw ApiException('Code inconnu : vérifiez-le auprès de l\'organisation');
    if (_mine.any((o) => o.id == 3)) throw ApiException('Vous faites déjà partie de Collège B (Bonapriso)');
    const college = Organisation(id: 3, name: 'Collège B (Bonapriso)', type: 'etablissement_scolaire', role: 'membre');
    _mine.add(college);
    return college;
  }

  @override
  Future<void> leave(int organisationId) async => _mine.removeWhere((o) => o.id == organisationId);
}
