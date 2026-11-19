import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/features/children/data/children_repository.dart';
import 'package:mboaride/features/children/presentation/children_screen.dart';
import 'package:mboaride/features/intercity/data/intercity_repository.dart';
import 'package:mboaride/features/organisations/data/organisations_repository.dart';
import 'package:mboaride/features/organisations/presentation/organisations_screen.dart';

Widget _app(Widget home) => MaterialApp(theme: buildMboaTheme(), home: home);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Scénario simple (docs/scenario-enfants-organisations.md) : mes organisations, puis mes enfants.
void main() {
  group('Mes organisations', () {
    testWidgets('rejoindre une école avec son code, puis la quitter', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_app(OrganisationsScreen(repository: FakeOrganisationsRepository())));
      await tester.pumpAndSettle();
      expect(find.text('Entreprise A (Bonanjo)'), findsOneWidget);
      expect(find.text('Collège B (Bonapriso)'), findsNothing);

      // Un code inconnu est refusé avec un message clair.
      await tester.tap(find.byKey(const ValueKey('rejoindre-organisation')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('code-organisation')), 'XXXX-0000');
      await tester.tap(find.text('Rejoindre'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Code inconnu'), findsOneWidget);

      // Le bon code : le collège rejoint la liste.
      await tester.enterText(find.byKey(const ValueKey('code-organisation')), 'colb-2026');
      await tester.tap(find.text('Rejoindre'));
      await tester.pumpAndSettle();
      expect(find.text('Collège B (Bonapriso)'), findsOneWidget);
      expect(find.textContaining('Vous avez rejoint Collège B'), findsOneWidget);

      // Quitter, après confirmation.
      await tester.tap(find.widgetWithText(TextButton, 'Quitter').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Quitter'));
      await tester.pumpAndSettle();
      expect(find.text('Collège B (Bonapriso)'), findsNothing);
    });
  });

  group('Mes enfants', () {
    testWidgets('ajouter un élève dans un établissement', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_app(ChildrenScreen(repository: FakeChildrenRepository())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter un élève'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Prénom de l\'élève'), 'Lina');
      await tester.enterText(find.widgetWithText(TextField, 'Âge'), '13');
      await tester.tap(find.byKey(const ValueKey('etablissement-eleve')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Campus C').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer le compte'));
      await tester.pumpAndSettle();
      expect(find.text('Lina'), findsOneWidget);
    });

    testWidgets('réserver un voyage au nom d\'un enfant autorisé seulement', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_app(ChildrenScreen(
        repository: FakeChildrenRepository(),
        intercityRepository: FakeIntercityRepository(),
      )));
      await tester.pumpAndSettle();
      // Ange est autorisé, pas Marc.
      expect(find.byKey(const ValueKey('reserver-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reserver-2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('reserver-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Douala → Yaoundé').first);
      await tester.pumpAndSettle();
      expect(find.text('Place réservée pour Ange.'), findsOneWidget);
      await tester.tap(find.textContaining('Réserver ·'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Place confirmée'), findsOneWidget);
    });

    testWidgets('le journal simule le départ et l\'arrivée, ou dit pourquoi c\'est impossible', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_app(ChildrenScreen(repository: FakeChildrenRepository())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voir le journal des trajets').first);      // Ange, qui a un trajet
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('simuler-trajet')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aucune réservation confirmée'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Voir le journal des trajets').last);       // Marc, sans réservation
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('simuler-trajet')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aucune réservation confirmée'), findsOneWidget);
    });
  });
}
