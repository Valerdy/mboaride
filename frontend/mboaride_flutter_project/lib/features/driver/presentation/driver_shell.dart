import 'package:flutter/material.dart';

import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import 'agent_activity_screen.dart';
import 'driver_home_screen.dart';
import 'earnings_screen.dart';
import 'publish_trip_screen.dart';

/// Espace conducteur : quatre onglets en bas (Accueil, Trajets, Activité, Gains).
class DriverShell extends StatefulWidget {
  const DriverShell({super.key, required this.repository, this.initialTab = 0, this.showMapTiles = true});

  final DriverRepository repository;
  final int initialTab;

  /// Fond de carte OpenStreetMap de l'écran équipage ; désactivé dans les tests.
  final bool showMapTiles;

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  late int _tab = widget.initialTab;

  void _open(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final body = switch (_tab) {
      0 => DriverHomeScreen(repository: repository, onOpenTab: _open, showMapTiles: widget.showMapTiles),
      1 => PublishTripScreen(repository: repository),
      2 => AgentActivityScreen(repository: repository),
      _ => EarningsScreen(repository: repository),
    };
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _open,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE6F2ED),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: MboaColors.green),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route, color: MboaColors.green),
            label: 'Trajets',
          ),
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline, color: MboaColors.green),
            label: 'Activité',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet, color: MboaColors.green),
            label: 'Gains',
          ),
        ],
      ),
    );
  }
}
