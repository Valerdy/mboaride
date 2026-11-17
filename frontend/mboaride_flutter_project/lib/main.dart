import 'package:flutter/material.dart';

import 'core/mboa_theme.dart';
import 'screens/registration_screen.dart';

/// Application MboaRide : inscription ou connexion (API Node), puis demande de trajet
/// et services (API Python). Voir docs/demarrage-local.md pour tout lancer sur un PC.
///   --dart-define=START=driver   ouvre l'espace conducteur après la connexion
///   --dart-define=FAKE_API=true  données simulées, sans serveur (l'inscription exige le serveur)

void main() => runApp(const MboarideApp());

class MboarideApp extends StatelessWidget {
  const MboarideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MBOARIDE',
      debugShowCheckedModeBanner: false,
      theme: buildMboaTheme(),
      home: const RegistrationScreen(),
    );
  }
}