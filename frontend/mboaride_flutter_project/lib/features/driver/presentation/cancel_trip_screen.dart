import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';

/// Annuler le trajet (wireframe 10, US07) : les passagers sont prévenus et leur agent
/// relance aussitôt une recherche sans ce conducteur. L'écran affiche ensuite le résultat.
class CancelTripScreen extends StatefulWidget {
  const CancelTripScreen({super.key, required this.repository, required this.crew});

  final DriverRepository repository;
  final Crew crew;

  @override
  State<CancelTripScreen> createState() => _CancelTripScreenState();
}

class _CancelTripScreenState extends State<CancelTripScreen> {
  final _note = TextEditingController();
  CancelReason _reason = CancelReason.personal;
  bool _sending = false;
  CancellationResult? _result;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _sending = true);
    try {
      final result = await widget.repository.cancelTrip(widget.crew, _reason, note: _note.text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _sending = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      showDriverMessage(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return PopScope(
      canPop: result == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && result != null) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(result == null ? 'Annuler le trajet' : 'Trajet annulé')),
        body: result == null ? _form() : _outcome(result),
      ),
    );
  }

  Widget _form() {
    final crew = widget.crew;
    final passengers = crew.passengers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        DriverCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${crew.dayLabel} · ${frenchTime(crew.departure)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '${crew.from} → ${crew.to} · $passengers passager${passengers > 1 ? 's' : ''} réservé${passengers > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 14, color: MboaColors.mutedText),
              ),
            ],
          ),
        ),
        const SectionTitle('Pourquoi annulez-vous ?'),
        for (final reason in CancelReason.values) ...[
          _reasonOption(reason),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        TextField(
          controller: _note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Précisez (facultatif)', alignLabelWithHint: true),
        ),
        const SizedBox(height: 14),
        InfoBanner(
          passengers == 0
              ? 'Aucun passager n\'est encore réservé sur ce trajet.'
              : 'Vos $passengers passagers sont prévenus et réaffectés automatiquement : leur agent cherche '
                  'aussitôt un autre conducteur, en quelques secondes. Les paiements déjà faits sont remboursés.',
          icon: Icons.groups_outlined,
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: MboaColors.red),
          onPressed: _sending ? null : _confirm,
          child: Text(_sending ? 'Annulation…' : 'Confirmer l\'annulation'),
        ),
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Garder mon trajet'),
        ),
      ],
    );
  }

  Widget _reasonOption(CancelReason reason) {
    final selected = _reason == reason;
    return Material(
      color: selected ? DriverColors.softGreen : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? MboaColors.green : MboaColors.border, width: selected ? 2 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _reason = reason),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? MboaColors.green : MboaColors.mutedText),
              const SizedBox(width: 10),
              Text(reason.label, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _outcome(CancellationResult result) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
    children: [
      InfoBanner(
        result.cancelledBookings == 0
            ? 'Votre trajet est annulé. Aucun passager n\'était réservé.'
            : '${result.cancelledBookings} réservation${result.cancelledBookings > 1 ? 's' : ''} annulée${result.cancelledBookings > 1 ? 's' : ''}, '
                '${result.reassignedCount} passager${result.reassignedCount > 1 ? 's' : ''} déjà réaffecté${result.reassignedCount > 1 ? 's' : ''}.',
        icon: Icons.check_circle_outline,
      ),
      const SectionTitle('Ce que deviennent vos passagers'),
      for (final outcome in result.outcomes) ...[
        DriverCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(outcome.passenger, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      outcome.reassigned
                          ? 'Nouveau conducteur : ${outcome.newDriver ?? 'trouvé'}'
                          : outcome.offersAvailable > 0
                              ? '${outcome.offersAvailable} autre${outcome.offersAvailable > 1 ? 's' : ''} offre${outcome.offersAvailable > 1 ? 's' : ''} à choisir'
                              : 'Aucun autre conducteur pour l\'instant ; sa demande reste ouverte',
                      style: const TextStyle(fontSize: 14, color: MboaColors.mutedText),
                    ),
                  ],
                ),
              ),
              StatusPill(
                outcome.reassigned ? 'Réaffecté' : 'En recherche',
                tone: outcome.reassigned ? PillTone.success : PillTone.warning,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 10),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Retour'),
      ),
    ],
  );
}
