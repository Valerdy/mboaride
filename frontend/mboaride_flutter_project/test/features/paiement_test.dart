import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mboaride/core/api_client.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/features/payment/data/payment_repository.dart';
import 'package:mboaride/features/payment/domain/payment.dart';
import 'package:mboaride/features/payment/presentation/my_trips_screen.dart';
import 'package:mboaride/features/payment/presentation/payment_screen.dart';

Widget _app(Widget home) => MaterialApp(theme: buildMboaTheme(), home: home);

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(500, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('le numéro doit appartenir à l\'opérateur choisi', () {
    expect(MobileMoneyOperator.mtn.checkNumber('677 12 34 56'), isNull);
    expect(MobileMoneyOperator.orange.checkNumber('+237 699123456'), isNull);
    expect(MobileMoneyOperator.mtn.checkNumber('699123456'), contains('Orange Money'));
    expect(MobileMoneyOperator.mtn.checkNumber('12345'), contains('6 suivi de 8 chiffres'));
  });

  testWidgets('enregistrer son compte, payer avec le code secret, trajet confirmé', (tester) async {
    _tallScreen(tester);
    final repository = FakePaymentRepository();
    await tester.pumpWidget(_app(PaymentScreen(
      repository: repository, paymentId: 1, amountFcfa: 336, route: 'Kotto → Bonanjo',
      driver: 'Armand', date: DateTime(2026, 11, 18),
    )));
    await tester.pumpAndSettle();

    // Aucun compte : le formulaire d'enregistrement s'affiche d'emblée.
    expect(find.text('Enregistrer mon compte Mobile Money'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Numéro MTN Mobile Money'), '699 12 34 56');
    await tester.enterText(find.widgetWithText(TextField, 'Nom du titulaire du compte'), 'Lina Ebolo');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('n\'est pas un numéro MTN Mobile Money'), findsOneWidget);

    await tester.tap(find.text('Orange Money'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('+237 6 99 12 34 56 · Lina Ebolo'), findsOneWidget);

    await tester.tap(find.text('Payer 336 FCFA'));
    // Pendant la validation, l'indicateur du bouton tourne : on avance le temps.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Validez-la avec votre code secret Orange Money'), findsOneWidget);
    final validate = find.widgetWithText(FilledButton, 'Valider');
    expect(tester.widget<FilledButton>(validate).onPressed, isNull); // code secret obligatoire
    await tester.enterText(find.widgetWithText(TextField, 'Code secret'), '1234');
    await tester.pump();
    await tester.tap(validate);
    await tester.pumpAndSettle();

    expect(find.text('Paiement reçu : votre trajet est confirmé'), findsOneWidget);
    expect(find.text('Référence : MBR-DEMO'), findsOneWidget);
  });

  testWidgets('Mes trajets sépare les trajets à confirmer des trajets confirmés', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(_app(MyTripsScreen(repository: FakePaymentRepository())));
    await tester.pumpAndSettle();
    expect(find.text('À confirmer'), findsWidgets);
    expect(find.text('Confirmés'), findsOneWidget);
    expect(find.text('Payer 350 FCFA'), findsOneWidget);
    expect(find.textContaining('réf. MBR-1A2B3C4D'), findsOneWidget);
    // Trajet confirmé : point de ramassage, numéro du conducteur, suivi de la course.
    expect(find.textContaining('Carrefour Kotto, devant la pharmacie'), findsWidgets);
    expect(find.byTooltip('Appeler Armand'), findsOneWidget);
    expect(find.textContaining('Suivre la course'), findsOneWidget);

    await tester.tap(find.text('Renoncer').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Renoncer'));
    await tester.pumpAndSettle();
    expect(find.text('Annulés et passés'), findsOneWidget);
  });

  test('le paiement passe par le compte enregistré (POST /api/paiements/{id}/mobile-money)', () async {
    late http.Request sent;
    final repository = ApiPaymentRepository(client: ApiClient(client: MockClient((request) async {
      sent = request;
      return http.Response.bytes(utf8.encode(jsonEncode({
        'id_paiement': 9, 'statut': 'en_attente', 'montant_fcfa': 448, 'operateur': 'MTN Mobile Money',
        'message': 'Une demande de paiement de 448 FCFA a été envoyée',
      })), 200);
    })));
    final receipt = await repository.startPayment(paymentId: 9, accountId: 3);
    expect(sent.url.path, '/api/paiements/9/mobile-money');
    expect(jsonDecode(sent.body), {'id_compte': 3});
    expect(receipt.status, PaymentStatus.pending);
    expect(receipt.amountFcfa, 448);
  });
}
