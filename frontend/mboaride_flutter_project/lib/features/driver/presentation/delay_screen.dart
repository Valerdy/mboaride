import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';

/// Signaler un retard (wireframe 9) : effet sur chaque passager. Ceux dont l'arrivée sort
/// de leur fenêtre pourront se retirer et relancer une recherche (protocole DELAY_REPORTED).
class DelayScreen extends StatefulWidget {
  const DelayScreen({super.key, required this.repository, required this.crew});

  final DriverRepository repository;
  final Crew crew;

  @override
  State<DelayScreen> createState() => _DelayScreenState();
}

class _DelayScreenState extends State<DelayScreen> {
  static const List<int> _choices = [5, 10, 15, 30];
  int _minutes = 10;
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await widget.repository.reportDelay(widget.crew, _minutes);
      if (!mounted) return;
      showDriverMessage(context, 'Vos passagers sont prévenus de votre retard de $_minutes min.');
      Navigator.of(context).pop(false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      showDriverMessage(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final impacts = delayImpacts(widget.crew, _minutes);
    final outside = impacts.where((i) => !i.withinWindow).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Signaler un retard')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          const SectionTitle('De combien êtes-vous en retard ?'),
          Row(
            children: [
              for (var i = 0; i < _choices.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: SizedBox(width: double.infinity, child: Text('+${_choices[i]} min', textAlign: TextAlign.center)),
                    selected: _minutes == _choices[i],
                    onSelected: (_) => setState(() => _minutes = _choices[i]),
                  ),
                ),
              ],
            ],
          ),
          const SectionTitle('Effet sur vos passagers'),
          for (final impact in impacts) ...[
            DriverCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${impact.stop.passenger} · ${impact.stop.place}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            Text(
                              impact.withinWindow
                                  ? 'Prise ${frenchTime(impact.newPickup)} · arrivée ${frenchTime(impact.newArrival)}'
                                  : 'Arrivée ${frenchTime(impact.newArrival)}, au plus tard ${frenchTime(impact.stop.latestArrival)}',
                              style: const TextStyle(fontSize: 14, color: MboaColors.mutedText),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(
                        impact.withinWindow ? 'Dans sa fenêtre' : 'Hors fenêtre',
                        tone: impact.withinWindow ? PillTone.success : PillTone.warning,
                      ),
                    ],
                  ),
                  if (!impact.withinWindow) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Son agent pourra se retirer de l\'équipage et chercher un autre conducteur.',
                      style: TextStyle(fontSize: 13, color: MboaColors.mutedText, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          InfoBanner(
            outside == 0
                ? 'Tous vos passagers restent dans leur fenêtre d\'arrivée.'
                : 'Chaque passager reçoit sa nouvelle heure de prise en charge. Prévenir tôt laisse '
                    'plus de choix à ceux qui doivent changer d\'équipage.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(_sending ? 'Envoi…' : 'Prévenir mes passagers'),
          ),
        ],
      ),
    );
  }
}
