import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/auth_session.dart';
import 'core/mboa_theme.dart';
import 'features/bench/data/bench_repository.dart';
import 'features/bench/presentation/bench_screen.dart';
import 'features/console/data/console_repository.dart';
import 'features/console/presentation/company_console_screen.dart';

/// Écrans bureau (US13, US14, US15), pensés pour un navigateur :
///   flutter run -d chrome -t lib/main_bureau_demo.dart \
///     --dart-define=FAKE_API=false --dart-define=API_URL=http://localhost:8000
void main() {
  AuthSession.demoUserId = 5; // Hélène, administratrice d'Entreprise A
  runApp(const _DesktopDemoApp());
}

class _DesktopDemoApp extends StatelessWidget {
  const _DesktopDemoApp();

  @override
  Widget build(BuildContext context) {
    final client = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    return MaterialApp(
      title: 'MboaRide · Console',
      debugShowCheckedModeBanner: false,
      theme: buildMboaTheme(),
      home: _DesktopHome(
        console: AppConfig.useFakeApi
            ? FakeConsoleRepository()
            : ApiConsoleRepository(client: client),
        bench: AppConfig.useFakeApi
            ? FakeBenchRepository()
            : ApiBenchRepository(client: client),
      ),
    );
  }
}

class _DesktopHome extends StatefulWidget {
  const _DesktopHome({required this.console, required this.bench});

  final ConsoleRepository console;
  final BenchRepository bench;

  @override
  State<_DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<_DesktopHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        NavigationRail(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.business_center_outlined),
              selectedIcon: Icon(Icons.business_center),
              label: Text('Entreprise'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.speed_outlined),
              selectedIcon: Icon(Icons.speed),
              label: Text('Banc'),
            ),
          ],
        ),
        Expanded(
          child: _tab == 0
              ? CompanyConsoleScreen(repository: widget.console)
              : BenchScreen(repository: widget.bench),
        ),
      ],
    ),
  );
}
