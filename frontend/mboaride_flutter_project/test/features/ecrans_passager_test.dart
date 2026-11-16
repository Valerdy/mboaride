import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/features/offers/data/offers_repository.dart';
import 'package:mboaride/features/offers/presentation/my_requests_screen.dart';
import 'package:mboaride/features/offers/presentation/offers_screen.dart';
import 'package:mboaride/features/preferences/data/preferences_repository.dart';
import 'package:mboaride/features/preferences/presentation/preferences_screen.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: buildMboaTheme(), home: home);

void main() {
  testWidgets('les exigences de confort s\'affichent (US02)', (tester) async {
    await tester.pumpWidget(
      _app(PreferencesScreen(repository: FakePreferencesRepository())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mes exigences'), findsWidgets);
    expect(find.textContaining('Cercle de confiance'), findsWidgets);
  });

  testWidgets('les demandes en cours mènent aux propositions', (tester) async {
    await tester.pumpWidget(
      _app(
        MyRequestsScreen(
          offers: FakeOffersRepository(),
          preferences: FakePreferencesRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsWidgets);
    await tester.tap(find.byType(Card).first);
    await tester.pumpAndSettle();
    expect(find.byType(OffersScreen), findsOneWidget);
    expect(find.text('À confirmer'), findsOneWidget);
  });

  testWidgets('sans offre confirmable, le diagnostic explique pourquoi', (
    tester,
  ) async {
    final repository = FakeOffersRepository(empty: true);
    final requests = await repository.openRequests();
    await tester.pumpWidget(
      _app(OffersScreen(repository: repository, request: requests.first)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Aucune offre ne convient'),
      findsOneWidget,
    );
    expect(find.textContaining('Élargir au cercle'), findsWidgets);
  });
}
