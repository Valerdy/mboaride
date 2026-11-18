import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';
import 'publish_trip_screen.dart';

/// Mes trajets programmés : tous les trajets du conducteur, en ligne, retirés ou passés.
///
/// Programmer plusieurs trajets d'un coup (aller et retour, plusieurs dates), retirer un
/// trajet (ses passagers sont prévenus et remboursés), le republier, ou rétablir une date
/// annulée.
class ScheduledTripsScreen extends StatefulWidget {
  const ScheduledTripsScreen({super.key, required this.repository});

  final DriverRepository repository;

  @override
  State<ScheduledTripsScreen> createState() => _ScheduledTripsScreenState();
}

class _ScheduledTripsScreenState extends State<ScheduledTripsScreen> {
  late Future<List<PublishedTrip>> _loading = widget.repository.publishedTrips();
  bool _busy = false;

  void _reload() => setState(() { _loading = widget.repository.publishedTrips(); });

  Future<void> _schedule() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PublishTripScreen(repository: widget.repository)),
    );
    if (published == true || mounted) _reload();
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showDriverMessage(context, success);
    } on ApiException catch (e) {
      if (mounted) showDriverMessage(context, e.message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  Future<void> _withdraw(PublishedTrip trip) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retirer ce trajet ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trip.upcomingBookings == 0
                ? 'Il ne sera plus proposé aux passagers. Vous pourrez le republier.'
                : '${trip.upcomingBookings} réservation(s) à venir : ces passagers seront prévenus, remboursés '
                      'et réaffectés à un autre conducteur si possible. Vous pourrez republier le trajet.'),
            const SizedBox(height: 12),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif (facultatif)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Garder')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MboaColors.red, minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    final motif = reason.text;
    reason.dispose();
    if (ok != true) return;
    await _run(() => widget.repository.withdrawTrip(trip.id, reason: motif), 'Trajet retiré.');
  }

  Future<void> _republish(PublishedTrip trip) async {
    DateTime? date;
    if (trip.oneOff) {
      final today = DateUtils.dateOnly(DateTime.now());
      date = await showDatePicker(
        context: context,
        initialDate: today.add(const Duration(days: 1)),
        firstDate: today,
        lastDate: today.add(const Duration(days: 90)),
        helpText: 'Nouvelle date du trajet',
        cancelText: 'Annuler',
        confirmText: 'Republier',
      );
      if (date == null) return;
    }
    await _run(
      () => widget.repository.republishTrip(trip.id, date: date),
      date == null ? 'Trajet de nouveau en ligne.' : 'Trajet republié pour le ${shortDate(date)}.',
    );
  }

  Future<void> _restore(PublishedTrip trip, DateTime day) => _run(
    () => widget.repository.restoreDate(trip.id, day),
    'Le ${shortDate(day)} est rétabli : le trajet est de nouveau proposé ce jour-là.',
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mes trajets programmés')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _busy ? null : _schedule,
      icon: const Icon(Icons.add),
      label: const Text('Programmer des trajets'),
    ),
    body: AsyncView<List<PublishedTrip>>(
      future: _loading,
      onRetry: _reload,
      builder: (context, trips) {
        final active = trips.where((t) => t.state == PublishedState.active).toList();
        final others = trips.where((t) => t.state != PublishedState.active).toList();
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (trips.isEmpty)
                const InfoBanner(
                  'Aucun trajet programmé. Touchez « Programmer des trajets » : vous pouvez en préparer plusieurs '
                  'à la fois, par exemple l\'aller et le retour.',
                ),
              if (active.isNotEmpty) ...[
                const SectionTitle('En ligne'),
                for (final t in active) _card(t),
              ],
              if (others.isNotEmpty) ...[
                const SectionTitle('Retirés et passés'),
                for (final t in others) _card(t),
              ],
            ],
          ),
        );
      },
    ),
  );

  Widget _card(PublishedTrip t) {
    final active = t.state == PublishedState.active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DriverCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${t.from} → ${t.to}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                StatusPill(
                  switch (t.state) {
                    PublishedState.active => 'En ligne',
                    PublishedState.withdrawn => 'Retiré',
                    PublishedState.past => 'Passé',
                  },
                  tone: active ? PillTone.success : PillTone.neutral,
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 4),
            Text('${t.scheduleLabel} · ${t.seats} place${t.seats > 1 ? 's' : ''}',
                style: const TextStyle(color: MboaColors.mutedText)),
            if (t.meetingPoint != null)
              Text('Ramassage : ${t.meetingPoint}', style: const TextStyle(fontSize: 13, color: MboaColors.mutedText)),
            if (active && t.nextDeparture != null)
              Text(
                'Prochain départ : ${shortDate(t.nextDeparture!)}'
                '${t.upcomingBookings > 0 ? ' · ${t.upcomingBookings} réservation(s) à venir' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
            if (active && t.cancelledDates.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final d in t.cancelledDates)
                    InputChip(
                      avatar: const Icon(Icons.event_busy, size: 16),
                      label: Text('Annulé le ${shortDate(d)}'),
                      deleteIcon: const Icon(Icons.restore, size: 18),
                      deleteButtonTooltipMessage: 'Rétablir cette date',
                      onDeleted: _busy ? null : () => _restore(t, d),
                    ),
                ],
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: active
                  ? TextButton.icon(
                      onPressed: _busy ? null : () => _withdraw(t),
                      style: TextButton.styleFrom(foregroundColor: MboaColors.red),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('Retirer'),
                    )
                  : TextButton.icon(
                      onPressed: _busy ? null : () => _republish(t),
                      icon: const Icon(Icons.replay, size: 18),
                      label: Text(t.oneOff ? 'Republier à une nouvelle date' : 'Republier'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
