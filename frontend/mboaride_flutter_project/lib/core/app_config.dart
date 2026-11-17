import 'package:flutter/foundation.dart';

class AppConfig {
  static const bool useFakeApi = false;

  // Port de votre serveur Node.js (8000 ou 3000 selon src/config.ts)
  static const int _serverPort = 8000;

  static String get apiBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:$_serverPort';
    }
    return 'http://10.0.2.2:$_serverPort';
  }

  // Bornes géographiques de la ville de Douala (Cameroun)
  static const double minLat = 3.90;
  static const double maxLat = 4.20;
  static const double minLng = 9.55;
  static const double maxLng = 9.90;
}