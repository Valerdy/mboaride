import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mboaride/core/mboa_theme.dart';
import 'package:mboaride/features/bench/data/bench_repository.dart';
import 'package:mboaride/features/bench/presentation/bench_screen.dart';
import 'package:mboaride/features/console/data/console_repository.dart';
import 'package:mboaride/features/console/presentation/company_console_screen.dart';

Widget _desktop(Widget home) => MaterialApp(
  theme: buildMboaTheme(),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(1440, 1200)),
    child: home,
  ),
);

void main() {
  testWidgets('la console montre l\'adoption et l\'impact (US13, US14)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _desktop(CompanyConsoleScreen(repository: FakeConsoleRepository())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Adoption'), findsOneWidget);
    expect(find.text('51.7 %'), findsOneWidget);
    expect(find.text('Économies et CO2 évité'), findsOneWidget);
    expect(find.textContaining('421 à 1263 kg'), findsOneWidget);
  });

  testWidgets('une adresse hors du domaine est écartée avec son motif (US13)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _desktop(CompanyConsoleScreen(repository: FakeConsoleRepository())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Adresses professionnelles'),
      'paul.njoya@gmail.com, flore.sime@entreprise-a.cm',
    );
    await tester.tap(find.text('Envoyer les invitations'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('paul.njoya@gmail.com · hors du domaine'),
      findsOneWidget,
    );
    expect(find.textContaining('Invitée : flore.sime@entreprise-a.cm'),
        findsOneWidget);
  });

  testWidgets('au-delà de trois relances, le bouton disparaît (US13)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _desktop(CompanyConsoleScreen(repository: FakeConsoleRepository())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Limite atteinte'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Relancer'), findsOneWidget);
  });

  testWidgets('le banc affiche les quatre critères de la grille (US15)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _desktop(BenchScreen(repository: FakeBenchRepository())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lancer la mesure'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Convergence en moins de 2 secondes'),
        findsOneWidget);
    expect(find.textContaining('Moins de 20 messages par équipage'),
        findsOneWidget);
    expect(find.textContaining('Même solution à chaque exécution'),
        findsOneWidget);
    expect(find.textContaining('Mémoire stable'), findsOneWidget);
    expect(find.text('atteinte'), findsNWidgets(4));
  });
}
