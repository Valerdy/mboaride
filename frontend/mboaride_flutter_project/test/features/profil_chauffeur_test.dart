import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mboaride/core/api_client.dart';
import 'package:mboaride/core/auth_session.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/screens/profile_screen.dart';
import 'package:mboaride/services/auth_service.dart';

AuthService _service({required bool driver}) => AuthService(
  api: ApiClient(
    client: MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'prenom': 'Lina',
            'nom': 'Ebolo',
            'email': 'lina@exemple.cm',
            'telephone': '+237690000602',
            'organisations': <dynamic>[],
            'est_conducteur': driver,
            'statut_agrement': driver ? 'en_verification' : 'aucun',
          }),
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, {required bool driver}) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AuthSession.accessToken = 'jeton';
  addTearDown(AuthSession.clear);
  await tester.pumpWidget(
    MaterialApp(theme: buildMboaTheme(), home: ProfileScreen(authService: _service(driver: driver))),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un passager n\'a ni espace conducteur ni véhicule, mais un bouton pour devenir chauffeur', (tester) async {
    await _open(tester, driver: false);
    expect(find.byKey(const ValueKey('devenir-chauffeur')), findsOneWidget);
    expect(find.text('Espace conducteur'), findsNothing);
    expect(find.text('Mon véhicule'), findsNothing);
    expect(find.text('Mes trajets'), findsOneWidget);     // ses services de passager restent là
  });

  testWidgets('une fois la procédure commencée, l\'espace conducteur et le véhicule apparaissent', (tester) async {
    await _open(tester, driver: true);
    expect(find.byKey(const ValueKey('devenir-chauffeur')), findsNothing);
    expect(find.text('Espace conducteur'), findsOneWidget);
    expect(find.text('Mon véhicule'), findsOneWidget);
  });
}
