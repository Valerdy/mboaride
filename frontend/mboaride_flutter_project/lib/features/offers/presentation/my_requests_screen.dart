import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../../children/data/children_repository.dart';
import '../../children/presentation/children_screen.dart';
import '../../intercity/data/intercity_repository.dart';
import '../../intercity/presentation/intercity_screen.dart';
import '../../preferences/data/preferences_repository.dart';
import '../../preferences/presentation/preferences_screen.dart';
import '../data/offers_repository.dart';
import '../domain/offer.dart';
import 'offers_screen.dart';

/// Point d'entrée du parcours passager : les demandes en cours, l'accès aux
/// propositions des agents (US05) et aux exigences de confort (US02).
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({
    super.key,
    required this.offers,
    required this.preferences,
    this.childrenRepository,
    this.intercityRepository,
  });

  final OffersRepository offers;
  final PreferencesRepository preferences;

  /// Parcours parent (US17, US19) et voyages interurbains (US22). Quand ils
  /// sont absents, les raccourcis correspondants ne s'affichent pas.
  final ChildrenRepository? childrenRepository;
  final IntercityRepository? intercityRepository;

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  List<RideRequestSummary> _requests = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await widget.offers.openRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _openOffers(RideRequestSummary request) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OffersScreen(
          repository: widget.offers,
          request: request,
        ),
      ),
    );
    if (booked == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trajet confirmé.')),
      );
      _load();
    }
  }

  void _openChildren() {
    final repository = widget.childrenRepository;
    if (repository == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildrenScreen(repository: repository),
      ),
    );
  }

  void _openIntercity() {
    final repository = widget.intercityRepository;
    if (repository == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IntercityScreen(repository: repository),
      ),
    );
  }

  void _openPreferences() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreferencesScreen(repository: widget.preferences),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mes demandes'),
      actions: [
        IconButton(
          onPressed: _openPreferences,
          icon: const Icon(Icons.tune),
          tooltip: 'Mes exigences',
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
              children: [
                if (widget.childrenRepository != null ||
                    widget.intercityRepository != null) ...[
                  Row(
                    children: [
                      if (widget.intercityRepository != null)
                        Expanded(
                          child: _Shortcut(
                            icon: Icons.airport_shuttle,
                            label: 'Voyage interurbain',
                            onTap: _openIntercity,
                          ),
                        ),
                      if (widget.intercityRepository != null &&
                          widget.childrenRepository != null)
                        const SizedBox(width: 12),
                      if (widget.childrenRepository != null)
                        Expanded(
                          child: _Shortcut(
                            icon: Icons.family_restroom,
                            label: 'Mes enfants',
                            onTap: _openChildren,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: MboaColors.red),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _load,
                    child: const Text('Réessayer'),
                  ),
                ],
                if (_error == null && _requests.isEmpty)
                  const Text(
                    'Aucune demande en cours. Créez une demande de trajet pour '
                    'que les agents cherchent des conducteurs compatibles.',
                    style: TextStyle(color: MboaColors.mutedText),
                  ),
                ..._requests.map(
                  (request) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Text(
                        request.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: MboaColors.night,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Arrivée entre ${request.earliest} et ${request.latest}\n'
                          'Maximum ${formatFcfa(request.maxPriceFcfa)} · '
                          'mode ${request.modeCode}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: MboaColors.mutedText,
                          ),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openOffers(request),
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MboaColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, color: MboaColors.green),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MboaColors.night,
            ),
          ),
        ],
      ),
    ),
  );
}
