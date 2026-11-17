import 'package:flutter/material.dart';

import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_rules_screen.dart';
import 'driver_widgets.dart';

/// Activité de mon agent (wireframe 7) : ce que l'agent conducteur a fait pour vous,
/// réservations confirmées et refus automatiques avec leur motif (messages DECLINE).
class AgentActivityScreen extends StatefulWidget {
  const AgentActivityScreen({super.key, required this.repository});

  final DriverRepository repository;

  @override
  State<AgentActivityScreen> createState() => _AgentActivityScreenState();
}

enum _Filter { all, booked, declined }

class _AgentActivityScreenState extends State<AgentActivityScreen> {
  late Future<List<AgentEvent>> _loading = widget.repository.agentActivity();
  _Filter _filter = _Filter.all;

  void _reload() => setState(() => _loading = widget.repository.agentActivity());

  bool _keep(AgentEvent e) => switch (_filter) {
    _Filter.all => true,
    _Filter.booked => e.kind != AgentEventKind.declined,
    _Filter.declined => e.kind == AgentEventKind.declined,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activité de mon agent')),
    body: AsyncView<List<AgentEvent>>(
      future: _loading,
      onRetry: _reload,
      builder: (context, events) {
        final shown = events.where(_keep).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            const Text(
              'Demandes traitées pour votre prochain trajet',
              style: TextStyle(fontSize: 14, color: MboaColors.mutedText),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final (filter, label) in const [
                  (_Filter.all, 'Toutes'),
                  (_Filter.booked, 'Réservées'),
                  (_Filter.declined, 'Refusées'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Aucune demande dans cette catégorie.', textAlign: TextAlign.center),
              ),
            for (final event in shown) ...[
              _eventTile(event),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            DriverCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Votre agent répond à chaque demande selon vos règles : vous n\'avez rien à faire.',
                    style: TextStyle(fontSize: 13, height: 1.45),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => DriverRulesScreen(repository: widget.repository)),
                    ),
                    child: const Text('Modifier mes règles'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _eventTile(AgentEvent event) {
    final (icon, background, foreground) = switch (event.kind) {
      AgentEventKind.booked => (Icons.check, DriverColors.softGreen, MboaColors.green),
      AgentEventKind.offerSent => (Icons.schedule, DriverColors.softSun, DriverColors.sunText),
      AgentEventKind.declined => (Icons.close, DriverColors.softGrey, MboaColors.mutedText),
    };
    return DriverCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 18, backgroundColor: background, child: Icon(icon, size: 18, color: foreground)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.heading, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(event.detail, style: const TextStyle(fontSize: 14, color: MboaColors.mutedText, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
