import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/payment_repository.dart';
import '../domain/payment.dart';
import 'payment_screen.dart';

/// Mes trajets : les trajets choisis par le passager.
/// « À confirmer » : place retenue, paiement à faire. « Confirmés » : payés, le conducteur
/// compte sur vous. Les trajets annulés ou passés sont regroupés en bas.
class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key, required this.repository});

  final PaymentRepository repository;

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  List<MyTrip>? _trips;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final trips = await widget.repository.myTrips();
      if (mounted) {
        setState(() {
          _trips = trips;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pay(MyTrip trip) async {
    final outcome = await Navigator.of(context).push<PaymentOutcome>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          repository: widget.repository,
          paymentId: trip.paymentId!,
          amountFcfa: trip.priceFcfa,
          route: trip.route,
          driver: trip.driver,
          date: trip.date,
        ),
      ),
    );
    if (outcome == PaymentOutcome.paid && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trajet confirmé.')));
    }
    _load();
  }

  Future<void> _cancel(MyTrip trip) async {
    final paid = trip.state == TripState.confirmed;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Renoncer à ce trajet ?'),
        content: Text(paid
            ? 'Votre place sera libérée, ${trip.driver} sera prévenu et vos ${trip.priceFcfa} FCFA remboursés.'
            : 'Votre place sera libérée et votre demande redeviendra ouverte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Garder')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MboaColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Renoncer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repository.cancelTrip(trip.bookingId);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    final toConfirm = trips?.where((t) => t.state == TripState.toConfirm).toList() ?? const [];
    final confirmed = trips?.where((t) => t.state == TripState.confirmed).toList() ?? const [];
    final past = trips?.where((t) => t.state == TripState.cancelled || t.state == TripState.done).toList() ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Mes trajets')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_error != null) Text(_error!, style: const TextStyle(color: MboaColors.red)),
            if (trips == null && _error == null) const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            ),
            if (trips != null && trips.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Text(
                  'Aucun trajet pour l\'instant. Faites une demande et choisissez une offre : '
                  'elle apparaîtra ici.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MboaColors.mutedText),
                ),
              ),
            if (toConfirm.isNotEmpty) ...[
              _title('À confirmer', 'Payez pour confirmer votre place auprès du conducteur.'),
              for (final t in toConfirm) _TripCard(trip: t, onPay: () => _pay(t), onCancel: () => _cancel(t)),
            ],
            if (confirmed.isNotEmpty) ...[
              _title('Confirmés', 'Payés : le conducteur compte sur vous.'),
              for (final t in confirmed) _TripCard(trip: t, onCancel: () => _cancel(t)),
            ],
            if (past.isNotEmpty) ...[
              _title('Annulés et passés', null),
              for (final t in past) _TripCard(trip: t),
            ],
          ],
        ),
      ),
    );
  }

  Widget _title(String text, String? hint) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: MboaColors.night)),
        if (hint != null) Text(hint, style: const TextStyle(fontSize: 13, color: MboaColors.mutedText)),
      ],
    ),
  );
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, this.onPay, this.onCancel});

  final MyTrip trip;
  final VoidCallback? onPay;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final (color, background) = switch (trip.state) {
      TripState.toConfirm => (const Color(0xFF6B4E00), const Color(0xFFFDF3D0)),
      TripState.confirmed => (MboaColors.green, const Color(0xFFE6F2ED)),
      _ => (MboaColors.mutedText, const Color(0xFFEDEFEE)),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MboaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(trip.route, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
                child: Text(trip.state.label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${frenchDate(trip.date)} · prise en charge ${trip.pickupTime}, arrivée ${trip.arrivalTime}'),
          Text('Avec ${trip.driver} · ${trip.vehicle}', style: const TextStyle(color: MboaColors.mutedText)),
          const SizedBox(height: 6),
          Text('${trip.priceFcfa} FCFA', style: const TextStyle(fontWeight: FontWeight.w700, color: MboaColors.green)),
          if (trip.state == TripState.confirmed && trip.reference != null)
            Text('Payé · réf. ${trip.reference}${trip.operatorLabel == null ? '' : ' · ${trip.operatorLabel}'}',
                style: const TextStyle(fontSize: 12.5, color: MboaColors.mutedText)),
          if (trip.state == TripState.toConfirm && trip.failureReason != null)
            Text('Dernier essai : ${trip.failureReason}', style: const TextStyle(fontSize: 12.5, color: MboaColors.red)),
          if (onPay != null || onCancel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onCancel != null)
                  TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(foregroundColor: MboaColors.red),
                    child: const Text('Renoncer'),
                  ),
                const Spacer(),
                if (onPay != null && trip.paymentId != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: onPay,
                    icon: const Icon(Icons.phone_iphone, size: 18),
                    label: Text('Payer ${trip.priceFcfa} FCFA'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
