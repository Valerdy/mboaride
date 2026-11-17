import 'package:flutter/material.dart';

import '../../../core/mboa_theme.dart';
import '../../../services/session.dart';
import '../../notifications/notifications.dart';
import '../../payment/data/payment_repository.dart';
import '../../wallet/wallet_screen.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'approval_screen.dart';
import 'crew_screen.dart';
import 'driver_rules_screen.dart';
import 'driver_widgets.dart';
import 'rate_passengers_screen.dart';
import 'vehicle_screen.dart';

/// Accueil conducteur (wireframe 1) : agrément, prochain trajet, mode de réservation.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({
    super.key,
    required this.repository,
    required this.onOpenTab,
    this.showMapTiles = true,
    this.walletRepository,
    this.notifications,
  });

  final DriverRepository repository;
  final bool showMapTiles;
  final PaymentRepository? walletRepository;
  final NotificationsRepository? notifications;

  /// Ouvre un onglet de l'espace conducteur (1 : Trajets).
  final ValueChanged<int> onOpenTab;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late Future<DriverOverview> _loading = widget.repository.overview();

  void _reload() => setState(() => _loading = widget.repository.overview());

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace conducteur'),
        actions: [
          if (widget.notifications != null) NotificationBell(repository: widget.notifications!),
          if (widget.walletRepository != null)
            IconButton(
              tooltip: 'Mon portefeuille',
              icon: const Icon(Icons.account_balance_wallet_outlined),
              onPressed: () => _push(WalletScreen(repository: widget.walletRepository!, driver: true)),
            ),
          const SignOutButton(),
        ],
      ),
      body: AsyncView<DriverOverview>(
        future: _loading,
        onRetry: _reload,
        builder: (context, overview) => RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            children: [
              Text(
                overview.firstName.isEmpty ? 'Bonjour' : 'Bonjour ${overview.firstName}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              if (overview.approved != null) ...[
                _approvalCard(overview.approved!),
                const SizedBox(height: 14),
              ],
              _nextTripCard(overview.nextCrew),
              const SizedBox(height: 14),
              _modeCard(overview.automatic),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _tile(
                      icon: Icons.directions_car_outlined,
                      label: 'Mon véhicule',
                      onTap: () => _push(VehicleScreen(repository: widget.repository)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _tile(
                      icon: Icons.star_outline,
                      label: 'Évaluer mes passagers',
                      onTap: overview.nextCrew == null
                          ? null
                          : () => _push(RatePassengersScreen(
                                repository: widget.repository,
                                crew: overview.nextCrew!,
                              )),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _approvalCard(bool approved) => DriverCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: approved ? DriverColors.softGreen : DriverColors.softSun,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            approved ? Icons.verified_user_outlined : Icons.pending_actions_outlined,
            color: approved ? MboaColors.green : DriverColors.sunText,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approved ? 'Agrément validé' : 'Agrément à compléter',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                approved
                    ? 'Identité, permis, casier judiciaire et assurance vérifiés par MboaRide.'
                    : 'Aucun trajet ne peut être publié avant la vérification de vos 4 pièces.',
                style: const TextStyle(fontSize: 14, color: MboaColors.mutedText, height: 1.4),
              ),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => _push(ApprovalScreen(repository: widget.repository)),
                child: Text(approved ? 'Voir mes documents' : 'Compléter mon agrément'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _nextTripCard(Crew? crew) {
    if (crew == null) {
      return DriverCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('Prochain trajet'),
            const SizedBox(height: 8),
            const Text('Aucun trajet à venir', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => widget.onOpenTab(1), child: const Text('Publier un trajet')),
          ],
        ),
      );
    }
    return DriverCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('Prochain trajet'),
          const SizedBox(height: 8),
          Text(
            '${crew.dayLabel} · ${frenchTime(crew.departure)}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _place(Icons.trip_origin, MboaColors.green, crew.from),
          const SizedBox(height: 6),
          _place(Icons.place, MboaColors.red, crew.to),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill('${crew.passengers} place${crew.passengers > 1 ? 's' : ''} sur ${crew.seatsTotal} réservée${crew.passengers > 1 ? 's' : ''}'),
              if (crew.passengers > 0) const StatusPill('Équipage confirmé'),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => _push(
              CrewScreen(
                repository: widget.repository,
                crew: crew,
                showMapTiles: widget.showMapTiles,
                walletRepository: widget.walletRepository,
              ),
            ),
            child: const Text('Voir l\'équipage'),
          ),
        ],
      ),
    );
  }

  Widget _place(IconData icon, Color color, String label) => Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 15)),
    ],
  );

  Widget _modeCard(bool automatic) => DriverCard(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                automatic ? 'Réservation automatique' : 'Je valide chaque passager',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                automatic
                    ? 'Votre agent accepte les passagers compatibles avec vos règles.'
                    : 'Vous validez vous-même chaque passager proposé.',
                style: const TextStyle(fontSize: 13, color: MboaColors.mutedText, height: 1.4),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => _push(DriverRulesScreen(repository: widget.repository)),
          child: const Text('Modifier'),
        ),
      ],
    ),
  );

  Widget _tile({required IconData icon, required String label, VoidCallback? onTap}) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: DriverColors.line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: onTap == null ? MboaColors.border : MboaColors.green),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    ),
  );
}
