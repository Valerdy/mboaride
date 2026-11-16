import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/features/children/data/children_repository.dart';
import 'package:mboaride/features/children/domain/child.dart';
import 'package:mboaride/features/children/presentation/child_journal_screen.dart';
import 'package:mboaride/features/children/presentation/children_screen.dart';
import 'package:mboaride/features/intercity/data/intercity_repository.dart';
import 'package:mboaride/features/intercity/presentation/intercity_screen.dart';

Widget _app(Widget home) => MaterialApp(theme: buildMboaTheme(), home: home);

void main() {
  test('un compte élève est refusé en dessous de 12 ans (US17)', () {
    expect(
      Child.validate(name: 'Yves Mbarga', ageText: '10', school: 'Saint-Michel'),
      contains('12 ans'),
    );
    expect(
      Child.validate(name: 'Yves Mbarga', ageText: '12', school: 'Saint-Michel'),
      isNull,
    );
  });

  testWidgets('le parent voit ses élèves et peut retirer l\'autorisation', (
    tester,
  ) async {
    final repository = FakeChildrenRepository();
    await tester.pumpWidget(_app(ChildrenScreen(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Ariane Mbarga'), findsOneWidget);
    expect(find.textContaining('Trajets autorisés'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Trajets suspendus'), findsNWidgets(2));
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
            name: 'Ariane Mbarga',
            age: 14,
            school: 'Collège Saint-Michel, Bonabéri',
            authorized: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Montée à bord'), findsOneWidget);
    expect(find.textContaining('Déposée au collège'), findsOneWidget);
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
}
