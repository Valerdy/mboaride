import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/api_client.dart';
import 'core/auth_session.dart';
import 'core/mboa_theme.dart';
import 'features/offers/data/offers_repository.dart';
import 'features/offers/presentation/my_requests_screen.dart';
import 'features/preferences/data/preferences_repository.dart';

/// Parcours passager (US02, US05, US09) :
///   flutter run -t lib/main_passager_demo.dart \
///     --dart-define=FAKE_API=false --dart-define=API_URL=http://10.0.2.2:8000
/// Avec FAKE_API=true (défaut), les écrans tournent sur des données simulées.
void main() {
  AuthSession.demoUserId = 2; // Grâce, passagère des données d'exemple
  runApp(const _PassengerDemoApp());
}

class _PassengerDemoApp extends StatelessWidget {
  const _PassengerDemoApp();

  @override
  Widget build(BuildContext context) {
    final client = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    return MaterialApp(
      title: 'MboaRide',
      debugShowCheckedModeBanner: false,
      theme: buildMboaTheme(),
      home: MyRequestsScreen(
        offers: AppConfig.useFakeApi
            ? FakeOffersRepository()
            : ApiOffersRepository(client),
        preferences: AppConfig.useFakeApi
            ? FakePreferencesRepository()
            : ApiPreferencesRepository(client),
      ),
    );
  }
}
