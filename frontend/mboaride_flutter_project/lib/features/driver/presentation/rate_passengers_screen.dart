import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';

/// Évaluer après le trajet (wireframe 12, écran E10 du dossier) : une note par passager,
/// et un signalement si besoin. Un signalement grave est examiné par MboaRide.
class RatePassengersScreen extends StatefulWidget {
  const RatePassengersScreen({super.key, required this.repository, required this.crew});

  final DriverRepository repository;
  final Crew crew;

  @override
  State<RatePassengersScreen> createState() => _RatePassengersScreenState();
}

class _RatePassengersScreenState extends State<RatePassengersScreen> {
  late final Map<String, int> _stars = {for (final s in widget.crew.stops) s.passenger: 0};
  final Set<String> _reports = {};
  bool _serious = false;
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await widget.repository.ratePassengers(
        widget.crew,
        [for (final e in _stars.entries) PassengerRating(passenger: e.key, stars: e.value)],
        reports: _reports,
        serious: _serious,
      );
      if (!mounted) return;
      showDriverMessage(context, 'Merci, votre évaluation est envoyée.');
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      showDriverMessage(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final crew = widget.crew;
    return Scaffold(
      appBar: AppBar(title: const Text('Évaluer le trajet')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          InfoBanner(
            '${crew.dayLabel} · ${crew.from} → ${crew.to}',
            title: 'Trajet terminé',
            icon: Icons.check_circle_outline,
          ),
          const SectionTitle('Notez vos passagers'),
          DriverCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < crew.stops.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: DriverColors.line),
                  _ratingRow(crew.stops[i]),
                ],
              ],
            ),
          ),
          const SectionTitle('Signaler un problème'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in reportKinds)
                FilterChip(
                  label: Text(kind),
                  selected: _reports.contains(kind),
                  onSelected: (selected) => setState(() => selected ? _reports.add(kind) : _reports.remove(kind)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DriverCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: _serious,
              onChanged: (v) => setState(() => _serious = v),
              activeTrackColor: MboaColors.green,
              title: const Text('Signalement grave', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'Examiné par MboaRide, qui peut suspendre le compte concerné.',
                style: TextStyle(fontSize: 13, color: MboaColors.mutedText),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(_sending ? 'Envoi…' : 'Envoyer mon évaluation'),
          ),
        ],
      ),
    );
  }

  Widget _ratingRow(CrewStop stop) {
    final stars = _stars[stop.passenger] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text('${stop.passenger} · ${stop.place}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
          for (var value = 1; value <= 5; value++)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '$value étoile${value > 1 ? 's' : ''} pour ${stop.passenger}',
              onPressed: () => setState(() => _stars[stop.passenger] = value),
              icon: Icon(
                value <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                color: value <= stars ? MboaColors.sun : MboaColors.mutedText,
              ),
            ),
        ],
      ),
    );
  }
}
