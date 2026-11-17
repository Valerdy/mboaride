// Course et fin de course, sans se déplacer : la position est simulée le long du tracé.
//
// Ces tests vérifient que la carte suit le déplacement, que l'arrivée à destination ouvre
// l'écran de fin de course (merci, note, commentaire), et que le conducteur est payé dans
// son portefeuille quand tout l'équipage a validé.
//
//   flutter test test/features/course_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mboaride/core/api_client.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/core/position_source.dart';
import 'package:mboaride/features/driver/data/driver_repository.dart';
import 'package:mboaride/features/driver/presentation/driver_ride_screen.dart';
import 'package:mboaride/features/notifications/notifications.dart';
import 'package:mboaride/features/payment/data/payment_repository.dart';
import 'package:mboaride/features/payment/domain/payment.dart';
import 'package:mboaride/features/payment/presentation/my_trips_screen.dart';
import 'package:mboaride/features/ride/live_ride_map.dart';
import 'package:mboaride/features/wallet/wallet_screen.dart';

Widget _app(Widget home) => MaterialApp(theme: buildMboaTheme(), home: home);

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(500, 1900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Tracé Kotto → Bonanjo qui suit (grossièrement) la route, comme le renverrait OSRM.
const List<LatLng> _kottoBonanjo = [
  LatLng(4.0720, 9.7660),
  LatLng(4.0655, 9.7520),
  LatLng(4.0560, 9.7340),
  LatLng(4.0500, 9.7130),
  LatLng(4.0465, 9.6990),
  LatLng(4.0435, 9.6908),
];

Future<List<LatLng>?> _fixedRoute(List<LatLng> stops) async => _kottoBonanjo;

/// La carte se redessine pendant la course : on avance le temps au lieu d'attendre la fin
/// de toutes les animations.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Avance le temps par pas de 500 ms jusqu'à ce que [finder] apparaisse.
Future<void> _pumpUntil(WidgetTester tester, Finder finder, {int maxSteps = 400}) async {
  for (var i = 0; i < maxSteps && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  test('la simulation parcourt le tracé de bout en bout, sans jamais reculer', () async {
    final ride = SimulatedRide(_kottoBonanjo, speedKmh: 25, acceleration: 400, tick: const Duration(milliseconds: 10));
    final positions = await ride.positions().toList();
    expect(positions.first, _kottoBonanjo.first);
    expect(positions.last, _kottoBonanjo.last);
    expect(positions.length, greaterThan(3));
    final remaining = [for (final p in positions) metersBetween(p, _kottoBonanjo.last)];
    for (var i = 1; i < remaining.length; i++) {
      expect(remaining[i], lessThanOrEqualTo(remaining[i - 1] + 1));
    }
    expect(hasArrived(positions.last, _kottoBonanjo.last), isTrue);
    expect(ride.lengthMeters, inInclusiveRange(8000, 13000)); // environ 9 km de Kotto à Bonanjo
  });

  testWidgets('le passager suit la course ; à l\'arrivée, il valide, note et commente', (tester) async {
    _tallScreen(tester);
    final repository = FakePaymentRepository();
    await tester.pumpWidget(_app(MyTripsScreen(
      repository: repository,
      showMapTiles: false,
      routeLoader: _fixedRoute,
      trackingMode: TrackingMode.simulation,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Suivre la course'));
    await _settle(tester); // fin de la transition vers l'écran de suivi
    expect(find.text('Suivi de la course'), findsOneWidget);
    expect(find.text('Carrefour Kotto, devant la pharmacie'), findsOneWidget);
    expect(find.byTooltip('Appeler Armand'), findsOneWidget);
    expect(find.textContaining('Simulation prête'), findsOneWidget);

    // On lance la simulation : la position apparaît et la distance restante diminue.
    await tester.tap(find.text('Lancer la simulation'));
    await tester.pump();
    expect(find.byKey(const ValueKey('position-courante')), findsWidgets);
    String progress() => tester.widget<Text>(find.byKey(const ValueKey('progression-course'))).data!;
    final start = progress();
    await tester.pump(const Duration(seconds: 3));
    expect(progress(), isNot(start));
    expect(progress(), startsWith('Encore'));

    // Arrivée à Bonanjo : l'écran de fin de course s'ouvre de lui-même.
    await _pumpUntil(tester, find.text("Merci d'avoir utilisé MboaRide !"));
    await _settle(tester);
    expect(find.text('Vous êtes arrivé à Bonanjo'), findsOneWidget);
    expect(find.text('Notez la course et Armand'), findsOneWidget);
    final validate = find.widgetWithText(FilledButton, 'Valider la fin de la course');
    expect(tester.widget<FilledButton>(validate).onPressed, isNull); // une note est demandée

    await tester.tap(find.byKey(const ValueKey('etoile-5')));
    await tester.enterText(find.widgetWithText(TextField, 'Votre commentaire (facultatif)'), 'Ponctuel et prudent');
    await tester.pump();
    await tester.tap(validate);
    await _settle(tester);

    expect(find.text('Fin de course validée'), findsOneWidget);
    // Plus de phrase sur le paiement du conducteur sur cet écran.
    expect(find.textContaining('sera payé'), findsNothing);
    expect(repository.lastRating, 5);
    expect(repository.lastComment, 'Ponctuel et prudent');

    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
    expect(find.text('Mes trajets'), findsOneWidget);
    expect(find.textContaining('votre note : 5/5'), findsOneWidget);
  });

  testWidgets('le conducteur arrive, suit les validations et reçoit le paiement', (tester) async {
    _tallScreen(tester);
    final repository = FakeDriverRepository(delay: Duration.zero);
    final crew = FakeDriverRepository.demoCrew();
    await tester.pumpWidget(_app(DriverRideScreen(
      repository: repository,
      crew: crew,
      showMapTiles: false,
      // Tracé qui passe par chaque prise en charge jusqu'à Bonabéri.
      routeLoader: (stops) async => stops,
      initialMode: TrackingMode.simulation,
      acceleration: 400,
      pollInterval: const Duration(seconds: 1),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('En route'), findsOneWidget);
    expect(find.text('Grâce Ebolo'), findsOneWidget);
    expect(find.byTooltip('Appeler Paul'), findsOneWidget);

    // La simulation mène à destination : l'arrivée est déclarée toute seule.
    await tester.tap(find.text('Lancer la simulation'));
    await _pumpUntil(tester, find.text('Fin de course : validations en cours'));
    expect(find.textContaining('0 passager(s) sur 3'), findsOneWidget);

    // Les passagers valident un à un ; au dernier, l'argent est versé au portefeuille.
    repository.validated.addAll(['Grâce', 'Paul']);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('En attente de Nadège'), findsOneWidget);
    repository.validated.add('Nadège');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Course réglée'), findsOneWidget);
    // 3 × 275 FCFA payés, 3 × 27 FCFA de commission : 744 FCFA pour le conducteur.
    expect(find.textContaining('744 FCFA ont été versés'), findsOneWidget);
  });

  testWidgets('le portefeuille se recharge depuis Mobile Money et paie un trajet', (tester) async {
    _tallScreen(tester);
    final repository = FakePaymentRepository(accounts: const [
      MobileMoneyAccount(id: 7, operator: MobileMoneyOperator.mtn, phone: '+237677000502', holder: 'Lina', isDefault: true),
    ]);
    await tester.pumpWidget(_app(WalletScreen(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('0 FCFA'), findsOneWidget);

    await tester.tap(find.text('Recharger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1000'));
    await tester.enterText(find.widgetWithText(TextField, 'Code secret MTN Mobile Money'), '1234');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Recharger').last);
    await tester.pumpAndSettle();
    expect(find.text('1000 FCFA'), findsOneWidget);
    expect(find.textContaining('Recharge depuis MTN Mobile Money'), findsOneWidget);

    final receipt = await repository.payWithWallet(1);
    expect(receipt.status, PaymentStatus.succeeded);
    expect(repository.balanceFcfa, 650);
    await repository.payWithWallet(1);
    // 300 FCFA restants pour un trajet à 350 : solde insuffisant.
    await expectLater(repository.payWithWallet(1), throwsA(isA<ApiException>()));
  });

  testWidgets('la cloche compte les notifications non lues et les affiche', (tester) async {
    final repository = FakeNotificationsRepository();
    await tester.pumpWidget(_app(Scaffold(
      appBar: AppBar(actions: [NotificationBell(repository: repository, interval: const Duration(seconds: 5))]),
    )));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('1 notification(s) non lue(s)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Armand a 10 min de retard'), findsOneWidget);
    expect(find.textContaining('Paiement de 350 FCFA reçu'), findsOneWidget);

    // Une nouvelle notification arrive : bandeau à l'écran.
    await tester.pageBack();
    await tester.pumpAndSettle();
    repository.items.insert(
      0,
      const AppNotification(id: 3, type: 'annulation', message: 'Votre conducteur a annulé le trajet du 18/11.', read: false),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Votre conducteur a annulé le trajet du 18/11.'), findsOneWidget);
    // Le bandeau se ferme seul après 5 secondes, malgré son bouton « Voir ».
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 500)); // entrée, 5 s d'affichage, sortie
    }
    expect(find.text('Votre conducteur a annulé le trajet du 18/11.'), findsNothing);
    // Fin du test : on retire la cloche pour arrêter son minuteur.
    await tester.pumpWidget(const SizedBox());
  });
}
