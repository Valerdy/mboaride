import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/features/driver/data/driver_repository.dart';
import 'package:mboaride/features/driver/domain/driver.dart';
import 'package:mboaride/features/driver/presentation/approval_screen.dart';
import 'package:mboaride/features/driver/presentation/cancel_trip_screen.dart';
import 'package:mboaride/features/driver/presentation/crew_screen.dart';
import 'package:mboaride/features/driver/presentation/delay_screen.dart';
import 'package:mboaride/features/driver/presentation/driver_rules_screen.dart';
import 'package:mboaride/features/driver/presentation/driver_shell.dart';
import 'package:mboaride/features/driver/presentation/earnings_screen.dart';
import 'package:mboaride/features/driver/presentation/publish_trip_screen.dart';
import 'package:mboaride/features/driver/presentation/rate_passengers_screen.dart';

Widget _app(Widget home) => MaterialApp(theme: buildMboaTheme(), home: home);

FakeDriverRepository _repo({bool approved = true}) =>
    FakeDriverRepository(approvedAtStart: approved, delay: Duration.zero);

/// Espace insécable fin utilisé comme séparateur de milliers (« 3 769 FCFA »).
const String _thin = ' ';

/// Écran de test haut (400 × 1600) : les formulaires sont construits en entier.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Équipage de démonstration, disponible sans attente : dans un test de widgets, le temps
/// est simulé, et attendre le dépôt avant le premier `pump` bloquerait le test.
Crew _crew() => FakeDriverRepository.demoCrew();

void main() {
  accesConducteurTests();
  group('calculs', () {
    test('le prix suit la règle du produit du moteur d\'agents', () {
      // Logpom → Bonabéri : 15 km × 8 L/100 km × 840 FCFA = 1 008 FCFA de carburant.
      final urban = PriceEstimate.compute(distanceKm: 15, consumptionL100: 8, seats: 3);
      expect(urban.fuelFcfa, 1008);
      // 1 008 FCFA partagés à parts égales entre le conducteur et ses 3 places : 252 FCFA ; le prix payé
      // comprend 10 % de commission MboaRide, arrondi aux 25 FCFA supérieurs. Tous les passagers paient
      // la même somme, voiture pleine ou non.
      expect(urban.perPassengerByOccupancy, [300, 300, 300]);
      expect(urban.alonePrice, urban.fullPrice);
      expect(passengerPrice(40), 100); // jamais moins de 100 FCFA

      // Douala-Yaoundé : 240 km, 1 000 FCFA de péage, commission de 10 %.
      final intercity = PriceEstimate.compute(
        distanceKm: 240,
        consumptionL100: 8,
        seats: 4,
        tollsFcfa: 1000,
        withCommission: true,
      );
      expect(intercity.fuelFcfa, 16128);
      expect(intercity.fullPrice, 3825); // (16 128 + 1 000) / 5 = 3 426, ÷ 0,9 = 3 807, arrondi à 3 825
    });

    test('un retard fait sortir de sa fenêtre le passager le plus serré', () async {
      final crew = _crew();
      final late10 = delayImpacts(crew, 10);
      expect({for (final i in late10) i.stop.passenger: i.withinWindow}, {
        'Grâce': true,
        'Paul': false, // arrivée 7 h 40, au plus tard 7 h 35
        'Nadège': true,
      });
      expect(delayImpacts(crew, 5).every((i) => i.withinWindow), isTrue);
      expect(late10.first.newPickup, '07:08');
    });

    test('les saisies invalides sont refusées', () {
      const vehicle = Vehicle(model: 'Berline', plate: 'LT 1', seats: 3, consumptionL100: 8, comfort: {});
      expect(vehicle.error, isNull);
      expect(vehicle.copyWith(seats: 0).error, contains('places'));
      expect(vehicle.copyWith(consumptionL100: 40).error, contains('Consommation'));

      const plan = TripPlan(
        kind: TripKind.urban,
        from: 'Logpom',
        to: 'Bonabéri',
        weekdays: {1},
        departure: '06:45',
        seats: 3,
        maxDetourKm: 2,
        meetingPoint: 'Station Total de Logpom',
      );
      expect(plan.error, isNull);
      expect(plan.copyWith(meetingPoint: '').error, contains('point de ramassage'));
      expect(plan.copyWith(departure: '6h45').error, contains('HH:MM'));
      expect(plan.copyWith(weekdays: {}).error, contains('jour'));
      expect(plan.copyWith(kind: TripKind.interurban, weekdays: {}).error, isNull);

      const rules = DriverRules(
        colleagues: false,
        partners: false,
        publicNetwork: false,
        acceptsStudents: false,
        minPriceFcfa: 0,
        automatic: true,
      );
      expect(rules.error, contains('au moins un cercle'));
    });

    test('les motifs de refus du protocole sont traduits', () {
      const event = AgentEvent(
        kind: AgentEventKind.declined,
        title: 'Demande refusée',
        detail: '',
        reasonCode: 'OUTSIDE_WINDOW',
      );
      expect(event.heading, 'Refus automatique · hors fenêtre');
      expect(declineReasonLabels.keys, containsAll(['DETOUR_TOO_LONG', 'NO_SEAT', 'PRICE_TOO_HIGH']));
    });
  });

  group('écrans', () {
    testWidgets('l\'accueil montre l\'agrément, le prochain trajet et les onglets', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_app(DriverShell(repository: _repo(), showMapTiles: false)));
      await tester.pumpAndSettle();
      expect(find.text('Bonjour Armand'), findsOneWidget);
      expect(find.text('Agrément validé'), findsOneWidget);
      expect(find.text('Demain · 6 h 45'), findsOneWidget);
      expect(find.text('3 places sur 3 réservées'), findsOneWidget);

      await tester.tap(find.text('Activité'));
      await tester.pumpAndSettle();
      expect(find.text('Refus automatique · détour trop long'), findsOneWidget);
      expect(find.text('Réservation confirmée · Grâce'), findsOneWidget);

      await tester.tap(find.text('Refusées'));
      await tester.pumpAndSettle();
      expect(find.text('Réservation confirmée · Grâce'), findsNothing);
      expect(find.text('Refus automatique · hors fenêtre'), findsOneWidget);

      await tester.tap(find.text('Gains'));
      await tester.pumpAndSettle();
      expect(find.text('74 %'), findsOneWidget);
    });

    testWidgets('une pièce déposée passe en vérification', (tester) async {
      _tallScreen(tester);
      PickedDocument? envoye;
      await tester.pumpWidget(_app(ApprovalScreen(
        repository: _repo(approved: false),
        picker: (_) async => envoye = const PickedDocument(bytes: [1, 2, 3], contentType: 'image/jpeg'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('2 sur 4'), findsOneWidget);
      expect(find.text('À déposer'), findsOneWidget);
      expect(find.text('En vérification'), findsOneWidget);

      await _tapVisible(tester, find.textContaining('Déposer :'));
      expect(envoye, isNotNull);
      expect(find.text('À déposer'), findsNothing);
      expect(find.text('En vérification'), findsNWidgets(2));
    });

    testWidgets('la publication estime le prix en ville et en interurbain', (tester) async {
      _tallScreen(tester);
      final repository = _repo();
      await tester.pumpWidget(_app(PublishTripScreen(repository: repository)));
      await tester.pumpAndSettle();
      expect(find.text('Environ 300 FCFA par place, le même pour tous'), findsOneWidget);
      expect(find.textContaining('chaque passager paie 300 FCFA'), findsOneWidget);

      // Sans point de ramassage, la publication est refusée.
      await _tapVisible(tester, find.text('Publier le trajet'));
      expect(find.textContaining('Précisez le point de ramassage'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('point-ramassage')), 'Station Total de Logpom');
      await _tapVisible(tester, find.text('Publier le trajet'));
      expect(find.textContaining('Trajet publié'), findsOneWidget);
      expect(repository.published.single.weekdays, {1, 2, 3, 4, 5});
      expect(repository.published.single.meetingPoint, 'Station Total de Logpom');

      await _tapVisible(tester, find.text('Interurbain'));
      expect(find.text('Points de départ possibles'), findsOneWidget);
      expect(find.text('Environ 3${_thin}825 FCFA par place, le même pour tous'), findsOneWidget);
    });

    testWidgets('un conducteur non agréé ne peut pas publier', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_app(PublishTripScreen(repository: _repo(approved: false))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('point-ramassage')), 'Station Total de Logpom');
      await _tapVisible(tester, find.text('Publier le trajet'));
      expect(find.textContaining('agrément doit être validé'), findsOneWidget);
    });

    testWidgets('l\'équipage montre l\'ordre de prise en charge', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_app(CrewScreen(repository: _repo(), crew: _crew(), showMapTiles: false)));
      // La carte redessine en continu : on avance le temps au lieu d'attendre la fin des animations.
      await tester.pump(const Duration(milliseconds: 500));
      // Le conducteur voit le nom complet et le téléphone de chaque passager, et peut l'appeler.
      expect(find.text('Grâce Ebolo · Kotto'), findsOneWidget);
      expect(find.text('Nadège Kamga · Deido'), findsOneWidget);
      expect(find.text('+237690000201'), findsOneWidget);
      expect(find.byTooltip('Appeler Grâce'), findsOneWidget);
      expect(find.textContaining('Station Total de Logpom, côté boulangerie'), findsOneWidget);
      expect(find.text('Démarrer la course'), findsOneWidget);
      expect(find.text('Équipage confirmé'), findsOneWidget);
      expect(find.text('Annuler le trajet'), findsOneWidget);
    });

    testWidgets('l\'annulation réaffecte les passagers (US07)', (tester) async {
      _tallScreen(tester);
      final repository = _repo();
      await tester.pumpWidget(_app(CancelTripScreen(repository: repository, crew: _crew())));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vos 3 passagers sont prévenus'), findsOneWidget);

      await _tapVisible(tester, find.text('Panne du véhicule'));
      await _tapVisible(tester, find.text('Confirmer l\'annulation'));
      expect(find.text('Ce que deviennent vos passagers'), findsOneWidget);
      expect(find.text('Nouveau conducteur : Mireille'), findsOneWidget);
      expect(find.text('En recherche'), findsOneWidget);
      expect(repository.published, isEmpty); // l'annulation ne publie rien
    });

    testWidgets('le retard montre qui sort de sa fenêtre', (tester) async {
      _tallScreen(tester);
      final repository = _repo();
      await tester.pumpWidget(_app(DelayScreen(repository: repository, crew: _crew())));
      await tester.pumpAndSettle();
      expect(find.text('Hors fenêtre'), findsOneWidget); // +10 min par défaut : Paul

      await tester.tap(find.text('+5 min'));
      await tester.pumpAndSettle();
      expect(find.text('Hors fenêtre'), findsNothing);
      expect(find.textContaining('restent dans leur fenêtre'), findsOneWidget);
    });

    testWidgets('les gains comparent les frais couverts à l\'objectif', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_app(EarningsScreen(repository: _repo())));
      await tester.pumpAndSettle();
      expect(find.text('74 %'), findsOneWidget);
      expect(find.textContaining('objectif 50 %'), findsOneWidget);
      expect(find.textContaining('en attente'), findsOneWidget);
    });

    testWidgets('les règles exigent au moins un cercle', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_app(DriverRulesScreen(repository: _repo())));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Mes collègues'));
      await _tapVisible(tester, find.text('Entreprises partenaires'));
      await _tapVisible(tester, find.text('Enregistrer mes règles'));
      expect(find.text('Acceptez au moins un cercle de passagers.'), findsOneWidget);
    });

    testWidgets('l\'évaluation demande au moins une note', (tester) async {
      _tallScreen(tester);
      final repository = _repo();
      await tester.pumpWidget(_app(RatePassengersScreen(repository: repository, crew: _crew())));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Envoyer mon évaluation'));
      expect(find.text('Notez au moins un passager.'), findsOneWidget);

      await _tapVisible(tester, find.byTooltip('5 étoiles pour Grâce'));
      await _tapVisible(tester, find.text('Envoyer mon évaluation'));
      expect(repository.lastRatings.firstWhere((r) => r.passenger == 'Grâce').stars, 5);
    });
  });
}

void accesConducteurTests() {
  group('accès à l\'espace conducteur', () {
    testWidgets('un passager voit la procédure pour devenir chauffeur, sans onglets ni véhicule', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_app(DriverShell(
        repository: FakeDriverRepository(isDriver: false, delay: Duration.zero),
        showMapTiles: false,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Devenez chauffeur MboaRide'), findsOneWidget);
      expect(find.byKey(const ValueKey('devenir-chauffeur')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Mon véhicule'), findsNothing);

      // Le bouton ouvre le dépôt des pièces.
      await tester.tap(find.byKey(const ValueKey('devenir-chauffeur')));
      await tester.pumpAndSettle();
      expect(find.text('Agrément conducteur'), findsOneWidget);
    });

    testWidgets('un conducteur garde l\'accueil complet et ses onglets', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_app(DriverShell(repository: _repo(), showMapTiles: false)));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Mon véhicule'), findsWidgets);
      expect(find.byKey(const ValueKey('devenir-chauffeur')), findsNothing);
    });
  });
}
