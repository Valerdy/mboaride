import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/mboa_theme.dart';
import '../../core/phone_call.dart';
import '../payment/data/payment_repository.dart';
import '../payment/domain/payment.dart';
import 'end_of_ride_screen.dart';
import 'live_ride_map.dart';

/// Suivi de la course par le passager : point de ramassage, conducteur à appeler, carte
/// qui suit sa position. À l'arrivée (moins de 80 m de la destination), l'écran de fin de
/// course s'ouvre de lui-même : merci, note, commentaire, validation.
class TripTrackingScreen extends StatefulWidget {
  const TripTrackingScreen({
    super.key,
    required this.repository,
    required this.bookingId,
    this.showMapTiles = true,
    this.routeLoader = roadRouteLoader,
    this.initialMode = TrackingMode.gps,
    this.autoStartSimulation = false,
    this.acceleration = 20,
  });

  final PaymentRepository repository;
  final int bookingId;
  final bool showMapTiles;
  final RouteLoader routeLoader;
  final TrackingMode initialMode;
  final bool autoStartSimulation;
  final double acceleration;

  @override
  State<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends State<TripTrackingScreen> {
  RideTracking? _tracking;
  String? _error;
  bool _endOpened = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.repository.tracking(widget.bookingId);
      if (mounted) setState(() => _tracking = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openEndOfRide() async {
    final t = _tracking;
    if (t == null || _endOpened) return;
    _endOpened = true;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EndOfRideScreen(repository: widget.repository, tracking: t)),
    );
    if (!mounted) return;
    if (done == true) {
      Navigator.of(context).pop(true);
    } else {
      _endOpened = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _tracking;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi de la course')),
      body: t == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
            )
          : ListView(
              children: [
                LiveRideMap(
                  stops: [LatLng(t.from.lat, t.from.lng), LatLng(t.to.lat, t.to.lng)],
                  destination: LatLng(t.to.lat, t.to.lng),
                  markers: [
                    RideMarker(LatLng(t.from.lat, t.from.lng), icon: Icons.trip_origin),
                    RideMarker(LatLng(t.to.lat, t.to.lng), color: MboaColors.red, icon: Icons.place),
                  ],
                  showMapTiles: widget.showMapTiles,
                  routeLoader: widget.routeLoader,
                  initialMode: widget.initialMode,
                  autoStartSimulation: widget.autoStartSimulation,
                  acceleration: widget.acceleration,
                  onArrived: () {
                    if (t.endValidated) return;
                    _openEndOfRide();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${t.from.label} → ${t.to.label}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${frenchDate(t.date)} · prise en charge ${t.pickupTime}, arrivée ${t.arrivalTime} · '
                        '${t.courseStatus.label}',
                        style: const TextStyle(color: MboaColors.mutedText),
                      ),
                      const SizedBox(height: 12),
                      _card(
                        icon: Icons.place_outlined,
                        title: 'Point de ramassage',
                        lines: [
                          t.pickupPoint,
                          if (t.pickupInstructions != null) t.pickupInstructions!,
                          'Le conducteur attend ${t.waitMinutes} min au plus.',
                        ],
                      ),
                      const SizedBox(height: 10),
                      _card(
                        icon: Icons.person_outline,
                        title: [t.driver, t.driverLastName].whereType<String>().join(' '),
                        lines: [t.vehicle, if (t.driverPhone != null) t.driverPhone!],
                        trailing: t.driverPhone == null ? null : CallButton(phone: t.driverPhone!, name: t.driver),
                      ),
                      const SizedBox(height: 16),
                      if (t.endValidated)
                        const Text(
                          'Vous avez validé la fin de cette course. Merci !',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MboaColors.green, fontWeight: FontWeight.w600),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: t.canValidate ? _openEndOfRide : null,
                          icon: const Icon(Icons.flag_outlined),
                          label: const Text('Je suis arrivé : valider la fin de la course'),
                        ),
                      if (!t.paid)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Payez votre place pour confirmer ce trajet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: MboaColors.red),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card({required IconData icon, required String title, required List<String> lines, Widget? trailing}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MboaColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: MboaColors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  for (final l in lines) Text(l, style: const TextStyle(color: MboaColors.mutedText)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );
}
