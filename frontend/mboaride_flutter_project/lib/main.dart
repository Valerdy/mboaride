import 'package:flutter/material.dart';

import 'core/mboa_theme.dart';
import 'screens/registration_screen.dart';
import 'screens/request_ride_screen.dart';

/// Écran de départ. Par défaut : l'inscription.
/// Pour ouvrir directement la demande de trajet pendant le développement :
///   flutter run --dart-define=START=ride
const String _startScreen =
String.fromEnvironment('START', defaultValue: 'registration');

void main() => runApp(const MboarideApp());

class MboarideApp extends StatelessWidget {
  const MboarideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MBOARIDE',
      debugShowCheckedModeBanner: false,
      theme: buildMboaTheme(),
      home: _startScreen == 'ride'
          ? const RequestRideScreen(token: '')
          : const RegistrationScreen(),
    );
  }
}