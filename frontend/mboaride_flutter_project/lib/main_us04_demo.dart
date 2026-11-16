import 'package:flutter/material.dart';

import 'core/mboa_theme.dart';
import 'features/ride_request/presentation/ride_request_screen.dart';

/// Lance uniquement l'écran US04 :  flutter run -t lib/main_us04_demo.dart
void main() => runApp(const _Us04DemoApp());

class _Us04DemoApp extends StatelessWidget {
  const _Us04DemoApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MboaRide',
    debugShowCheckedModeBanner: false,
    theme: buildMboaTheme(),
    home: const RideRequestScreen(),
  );
}
