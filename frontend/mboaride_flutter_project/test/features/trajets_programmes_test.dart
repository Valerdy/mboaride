import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/features/driver/data/driver_repository.dart';
import 'package:mboaride/features/driver/domain/driver.dart';
import 'package:mboaride/features/driver/presentation/publish_trip_screen.dart';
import 'package:mboaride/features/driver/presentation/scheduled_trips_screen.dart';

Widget _app(Widget home) => MaterialApp(theme: buildMboaTheme(), home: home);

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('libellés des horaires programmés', () {
    expect(weekdaysLabel({1, 2, 3, 4, 5}), 'Lun. à ven.');
    expect(weekdaysLabel({6, 7}), 'Sam., dim.');
    expect(weekdaysLabel({1, 2, 3, 4, 5, 6, 7}), 'Tous les jours');
    expect(shortDate(DateTime(2026, 11, 19)), 'jeu. 19 nov.');
  });

  testWidgets('programmer l\'aller et le retour en une fois', (tester) async {
    _tallScreen(tester);
    final repository = FakeDriverRepository(delay: Duration.zero);
    await tester.pumpWidget(_app(PublishTripScreen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('point-ramassage')), 'Station Total de Logpom');
    await _tap(tester, find.text('Ajouter le retour'));
    // Le formulaire prépare le retour : départ et arrivée inversés, 17:30, ramassage à préciser.
    expect(find.text('1 trajet prêt à programmer avec celui du formulaire'), findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Départ')).controller!.text, 'Bonabéri');
    expect(find.text('Programmer les 2 trajets'), findsOneWidget);

    await _tap(tester, find.text('Programmer les 2 trajets'));
    expect(find.textContaining('Précisez le point de ramassage'), findsOneWidget);   // celui du retour manque
    await tester.enterText(find.byKey(const ValueKey('point-ramassage')), 'Carrefour Bonabéri');
    await _tap(tester, find.text('Programmer les 2 trajets'));

    expect(find.text('2 trajets programmés.'), findsOneWidget);
    expect(repository.published.map((p) => '${p.from} → ${p.to} ${p.departure}'),
        ['Logpom → Bonabéri 06:45', 'Bonabéri → Logpom 17:30']);
  });

  testWidgets('un trajet à une date précise', (tester) async {
    _tallScreen(tester);
    final repository = FakeDriverRepository(delay: Duration.zero);
    await tester.pumpWidget(_app(PublishTripScreen(repository: repository)));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Une date'));
    expect(find.textContaining(RegExp(r'^Le \w+\. \d+ ')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('point-ramassage')), 'Station Total de Logpom');
    await _tap(tester, find.text('Publier le trajet'));
    final plan = repository.published.single;
    expect(plan.date, isNotNull);
    expect(plan.weekdays, isEmpty);
  });

  testWidgets('retirer un trajet, le republier, rétablir une date annulée', (tester) async {
    _tallScreen(tester);
    final repository = FakeDriverRepository(delay: Duration.zero);
    await tester.pumpWidget(_app(ScheduledTripsScreen(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('En ligne'), findsWidgets);
    expect(find.text('Logpom → Bonabéri'), findsOneWidget);
    expect(find.text('Retirés et passés'), findsOneWidget);
    expect(find.text('Lun. à ven. · 06:45 · 3 places'), findsOneWidget);

    // Rétablir la date annulée de l'aller.
    await _tap(tester, find.byTooltip('Rétablir cette date'));
    expect(find.textContaining('est rétabli'), findsOneWidget);
    expect(find.byTooltip('Rétablir cette date'), findsNothing);

    // Retirer l'aller : ses 3 passagers sont prévenus.
    await _tap(tester, find.text('Retirer'));
    expect(find.textContaining('3 réservation(s) à venir'), findsWidgets);
    await _tap(tester, find.widgetWithText(FilledButton, 'Retirer'));
    expect(find.text('Trajet retiré.'), findsOneWidget);
    expect(find.text('En ligne'), findsNothing);

    // Republier le retour, retiré plus tôt.
    await _tap(tester, find.text('Republier').first);
    expect(find.text('Trajet de nouveau en ligne.'), findsOneWidget);
    // Le retour est de nouveau en ligne (vérifié à l'écran : dans un test de widgets, attendre
    // directement le dépôt bloquerait, son délai ne s'écoulant qu'avec tester.pump).
    expect(find.text('En ligne'), findsNWidgets(2)); // titre de section et pastille du trajet
    expect(find.text('Bonabéri → Logpom'), findsOneWidget);
    expect(find.text('Republier'), findsOneWidget); // l'aller, retiré juste avant
  });
}
