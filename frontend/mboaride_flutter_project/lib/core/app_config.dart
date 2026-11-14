/// Réglages de l'application. On les change à la compilation, sans toucher au code :
///   flutter run --dart-define=API_URL=http://192.168.1.10:8000 --dart-define=FAKE_API=false
class AppConfig {
  /// 10.0.2.2 désigne le localhost de votre PC vu depuis l'émulateur Android.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// true tant que l'endpoint POST /ride-requests n'existe pas côté API.
  static const bool useFakeApi = bool.fromEnvironment(
    'FAKE_API',
    defaultValue: true,
  );

  /// Zone de service (identique à l'API) : Douala et environs.
  static const double minLat = 3.85;
  static const double maxLat = 4.25;
  static const double minLng = 9.45;
  static const double maxLng = 10.0;
  static const double centerLat = 4.05;
  static const double centerLng = 9.725;
}
