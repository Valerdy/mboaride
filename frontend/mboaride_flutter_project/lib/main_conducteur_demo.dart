import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/auth_session.dart';
import 'core/mboa_theme.dart';
import 'features/driver/data/driver_repository.dart';
import 'features/driver/presentation/driver_shell.dart';

/// Espace conducteur (wireframes conducteur, US03, US07, US08, US10, US11) :
///   flutter run -t lib/main_conducteur_demo.dart
/// Avec FAKE_API=true (défaut), tous les écrans tournent sur des données simulées
/// (Armand, Logpom → Bonabéri). Avec FAKE_API=false, seuls « mes trajets » et
/// l'annulation sont branchés sur l'API FastAPI :
///   flutter run -t lib/main_conducteur_demo.dart \
///     --dart-define=FAKE_API=false --dart-define=API_URL=http://10.0.2.2:8000
void main() {
  AuthSession.demoUserId = 1; // conducteur des données d'exemple de l'API
  runApp(const _DriverDemoApp());
}

class _DriverDemoApp extends StatelessWidget {
  const _DriverDemoApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MboaRide · Conducteur',
    debugShowCheckedModeBanner: false,
    theme: buildMboaTheme(),
    home: DriverShell(
      repository: AppConfig.useFakeApi
          ? FakeDriverRepository()
          : ApiDriverRepository(client: ApiClient(baseUrl: AppConfig.apiBaseUrl)),
    ),
  );
}
