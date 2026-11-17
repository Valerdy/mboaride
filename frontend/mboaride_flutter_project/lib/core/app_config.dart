import 'package:flutter/foundation.dart';

/// Réglages de l'application, changés à la compilation sans toucher au code.
///
/// Deux API, une seule base PostgreSQL (docs/decision-backend.md) :
/// - API Node (AUTH_URL) : inscription, connexion, itinéraires OSRM ;
/// - API Python (API_URL) : profil, demandes, offres du moteur d'agents, réservations,
///   espace conducteur, élèves, voyages interurbains, console entreprise.
///
/// Par défaut : localhost pour le navigateur, 10.0.2.2 (le PC vu depuis l'émulateur)
/// pour Android. Sur un téléphone branché en USB, `adb reverse` rend le PC joignable en
/// 127.0.0.1 (c'est ce que fait scripts/lancer_tout.ps1) :
///   flutter run --dart-define=API_URL=http://127.0.0.1:8000 --dart-define=AUTH_URL=http://127.0.0.1:8101
class AppConfig {
  static const String _apiUrl = String.fromEnvironment('API_URL');
  static const String _authUrl = String.fromEnvironment('AUTH_URL');

  static String get _host => kIsWeb ? 'http://localhost' : 'http://10.0.2.2';

  /// API Python (FastAPI).
  static String get apiBaseUrl => _apiUrl.isNotEmpty ? _apiUrl : '$_host:8000';

  /// API Node : authentification et itinéraires.
  static String get authBaseUrl => _authUrl.isNotEmpty ? _authUrl : '$_host:8101';

  /// Données simulées, sans serveur : `--dart-define=FAKE_API=true`.
  static const bool useFakeApi = bool.fromEnvironment('FAKE_API');

  /// Zone de service (identique aux deux API) : Douala et environs.
  static const double minLat = 3.85;
  static const double maxLat = 4.25;
  static const double minLng = 9.45;
  static const double maxLng = 10.0;
  static const double centerLat = 4.05;
  static const double centerLng = 9.725;
}
