import 'package:flutter/material.dart';
import 'screens/registration_screen.dart';

void main() {
  runApp(const MboarideApp());
}

class MboarideApp extends StatelessWidget {
  const MboarideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MBOARIDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        primaryColor: const Color(0xFF006644),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006644),
          primary: const Color(0xFF006644),
        ),
        useMaterial3: true,
      ),
      home: const RegistrationScreen(),
    );
  }
}
