import 'package:flutter/material.dart';

import 'app_services.dart';
import 'core/auth_session.dart';
import 'core/mboa_theme.dart';
import 'features/driver/presentation/driver_shell.dart';
import 'screens/registration_screen.dart';
import 'screens/request_ride_screen.dart';
import 'services/session.dart';

/// Application MboaRide : inscription ou connexion (API Node), puis demande de trajet
/// et services (API Python). Voir docs/demarrage-local.md pour tout lancer sur un PC.
///   --dart-define=START=driver   ouvre l'espace conducteur après la connexion
///   --dart-define=FAKE_API=true  données simulées, sans serveur (l'inscription exige le serveur)

const String _start = String.fromEnvironment('START', defaultValue: 'ride');

void main() {
  connectApiClientToSession();
  runApp(const MboarideApp());
}

class MboarideApp extends StatelessWidget {
  const MboarideApp({super.key});

  @override
  Widget build(BuildContext context) {
    Session.loginScreen = () => const RegistrationScreen();
    Session.homeScreen = () => _start == 'driver'
        ? DriverShell(
            repository: AppServices.driver,
            walletRepository: AppServices.payments,
            notifications: AppServices.notifications,
          )
        : RequestRideScreen(token: AuthSession.accessToken ?? '');
    return MaterialApp(
      title: 'MBOARIDE',
      debugShowCheckedModeBanner: false,
      theme: buildMboaTheme(),
      navigatorKey: Session.navigatorKey,
      scaffoldMessengerKey: Session.messengerKey,
      // Reprend la session enregistrée ; sinon, écran de connexion.
      home: const SessionGate(),
    );
  }
}