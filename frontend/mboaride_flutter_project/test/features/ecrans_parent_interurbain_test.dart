import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/features/children/data/children_repository.dart';
import 'package:mboaride/features/children/domain/child.dart';
import 'package:mboaride/features/children/presentation/child_journal_screen.dart';
import 'package:mboaride/features/children/presentation/children_screen.dart';
import 'package:mboaride/features/intercity/data/intercity_repository.dart';
import 'package:mboaride/features/intercity/presentation/intercity_screen.dart';
import 'package:mboaride/features/ride_request/data/place_search_service.dart';
import 'package:mboaride/features/ride_request/domain/ride_request.dart' show Place;

Widget _app(Widget home) => MaterialApp(theme: buildMboaTheme(), home: home);

void main() {
  test('un compte élève est refusé en dessous de 12 ans (US17)', () {
    expect(
      Child.validate(firstName: 'Marc', ageText: '10'),
      contains('12 à 17 ans'),
    );
    expect(Child.validate(firstName: 'Marc', ageText: '18'), contains('17'));
    expect(Child.validate(firstName: 'Marc', ageText: '12'), isNull);
  });

  testWidgets('le parent voit ses élèves et peut retirer l\'autorisation', (
    tester,
  ) async {
    final repository = FakeChildrenRepository();
    await tester.pumpWidget(_app(ChildrenScreen(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Ange'), findsOneWidget);
    expect(find.textContaining('Trajets autorisés'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Trajets suspendus'), findsNWidgets(2));
    // le second élève est déjà suspendu dans le jeu simulé
  });

  testWidgets('le journal montre le départ et l\'arrivée (US19)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ChildJournalScreen(
          repository: FakeChildrenRepository(),
          child: const Child(
            id: 1,
            firstName: 'Ange',
            age: 12,
            school: 'Collège B (Bonapriso)',
            authorized: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('est montée à bord à Makepe'), findsOneWidget);
    expect(find.textContaining('est arrivée à Bonapriso'), findsOneWidget);
  });

  testWidgets('une place interurbaine se réserve à l\'avance (US22)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(IntercityScreen(repository: FakeIntercityRepository())),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Douala → Yaoundé'), findsWidgets);

    await tester.tap(find.textContaining('Douala → Yaoundé').first);
    await tester.pumpAndSettle();
    expect(find.text('Point de montée'), findsOneWidget);

    await tester.tap(find.textContaining('Réserver ·'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Place confirmée'), findsOneWidget);
  });

  testWidgets('plusieurs places se réservent ensemble au même prix chacune (US22)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(IntercityScreen(repository: FakeIntercityRepository())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Douala → Yaoundé').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('nombre-de-places')), findsOneWidget);
    await tester.tap(find.byTooltip('Plus de places'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Réserver 2 places'), findsOneWidget);

    await tester.tap(find.textContaining('Réserver 2 places'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 places confirmées'), findsOneWidget);
  });

  group('point de départ choisi par le voyageur (US22)', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        _app(IntercityScreen(repository: FakeIntercityRepository(), placeSearch: _FakePlaces())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Douala → Yaoundé').first);
      await tester.pumpAndSettle();
    }

    Future<void> pickPlace(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const ValueKey('autre-point-de-depart')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'lieu');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('un point libre accepté par le conducteur se réserve', (tester) async {
      await openSheet(tester);
      await pickPlace(tester, 'Bonamoussadi, carrefour Shell');
      expect(find.byKey(const ValueKey('verification-depart')), findsOneWidget);
      expect(find.textContaining('Le conducteur vous prend vers 06:25'), findsOneWidget);

      await tester.tap(find.textContaining('Réserver ·'));
      await tester.pumpAndSettle();
      expect(find.textContaining('montée à Bonamoussadi, carrefour Shell à 06:25'), findsOneWidget);
    });

    testWidgets('un point trop loin du conducteur ne peut pas être réservé', (tester) async {
      await openSheet(tester);
      await pickPlace(tester, 'Bafoussam');
      expect(find.textContaining('de détour au conducteur'), findsOneWidget);
      final bouton = tester.widget<FilledButton>(find.ancestor(of: find.textContaining('Réserver ·'), matching: find.byType(FilledButton)));
      expect(bouton.onPressed, isNull);
    });
  });
}

class _FakePlaces implements PlaceSearchService {
  @override
  Future<List<Place>> search(String query) async => const [
    Place(name: 'Bonamoussadi, carrefour Shell', lat: 4.085, lng: 9.735),
    Place(name: 'Bafoussam', lat: 5.4737, lng: 10.4179),
  ];
}
