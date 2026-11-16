import '../../../core/api_client.dart';
import '../domain/preferences.dart';

/// Lecture et enregistrement des exigences du passager (US02).
abstract class PreferencesRepository {
  Future<Preferences> load();

  Future<Preferences> save(Preferences preferences);
}

/// Appelle `GET` et `PUT /api/moi/preferences`.
class ApiPreferencesRepository implements PreferencesRepository {
  ApiPreferencesRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;
  static const String _path = '/api/moi/preferences';

  @override
  Future<Preferences> load() async {
    final body = await _client.get(_path);
    return Preferences.fromJson(body as Map<String, dynamic>);
  }

  @override
  Future<Preferences> save(Preferences preferences) async {
    final body = await _client.put(_path, preferences.toJson());
    return Preferences.fromJson(body as Map<String, dynamic>);
  }
}

/// Sert à montrer l'écran sans serveur.
class FakePreferencesRepository implements PreferencesRepository {
  FakePreferencesRepository([Preferences? initial])
    : _stored =
          initial ??
          const Preferences(
            airConditioning: true,
            nonSmoking: false,
            quiet: false,
            maxPriceFcfa: 400,
            circle: Circle.partenaires,
            mode: BookingMode.manuel,
            priority: RidePriority.heure,
          );

  Preferences _stored;

  @override
  Future<Preferences> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return _stored;
  }

  @override
  Future<Preferences> save(Preferences preferences) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _stored = preferences;
    return _stored;
  }
}
