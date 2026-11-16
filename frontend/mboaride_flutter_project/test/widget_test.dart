// Test de démarrage : l'application se construit et ouvre l'écran d'accueil.
// Il remplace le test généré par `flutter create`, qui cherchait un compteur
// et une classe MyApp qui n'ont jamais existé dans ce projet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mboaride/main.dart';

void main() {
  testWidgets('l\'application démarre sur l\'écran d\'accueil', (tester) async {
    await tester.pumpWidget(const MboarideApp());
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'MBOARIDE');
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
