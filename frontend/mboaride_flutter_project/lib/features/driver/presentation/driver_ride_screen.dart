import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../../../core/phone_call.dart';
import '../../payment/data/payment_repository.dart';
import '../../ride/live_ride_map.dart';
import '../../wallet/wallet_screen.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';

/// La course côté conducteur : la carte suit sa position (GPS ou simulation) le long des
/// prises en charge. À l'arrivée, les passagers sont invités à valider la fin de la course ;
/// l'écran suit leurs validations, puis le versement dans le portefeuille (prix moins 10 %).
class DriverRideScreen extends StatefulWidget {
  const DriverRideScreen({
    super.key,
    required this.repository,
    required this.crew,
    this.walletRepository,
    this.showMapTiles = true,
    this.routeLoader = roadRouteLoader,
    this.initialMode = TrackingMode.gps,
    this.pollInterval = const Duration(seconds: 5),
    this.acceleration = 20,
  });

  /// Simulation : vitesse multipliée (×20 par défaut, une course de ville en une minute).
  final double acceleration;

  final DriverRepository repository;
  final Crew crew;
  final PaymentRepository? walletRepository;
  final bool showMapTiles;
  final RouteLoader routeLoader;
  final TrackingMode initialMode;
  final Duration pollInterval;

  @override
  State<DriverRideScreen> createState() => _DriverRideScreenState();
}

class _DriverRideScreenState extends State<DriverRideScreen> {
  CourseState? _state;
  String? _error;
  bool _busy = false;
  Timer? _poll;

  Crew get _crew => widget.crew;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final state = await widget.repository.startCourse(_crew);
      if (!mounted) return;
      setState(() => _state = state);
      if (state.status == CourseStatus.arrived) _watch();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _arrive() async {
    if (_busy || _state?.status == CourseStatus.arrived || _state?.status == CourseStatus.settled) return;
    setState(() => _busy = true);
    try {
      final state = await widget.repository.arriveCourse(_crew);
      if (!mounted) return;
      setState(() => _state = state);
      _watch();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Suit les validations des passagers jusqu'au versement.
  void _watch() {
    _poll?.cancel();
    _poll = Timer.periodic(widget.pollInterval, (_) async {
      try {
        final state = await widget.repository.courseState(_crew);
        if (!mounted) return;
        setState(() => _state = state);
        if (state.paidOut) _poll?.cancel();
      } on ApiException {
        // réseau : on réessaie au prochain tour
      }
    });
  }

  List<LatLng> get _stops => [
    if (_crew.fromLat != null) LatLng(_crew.fromLat!, _crew.fromLng!),
    for (final s in _crew.stops)
      if (s.lat != null) LatLng(s.lat!, s.lng!),
    if (_crew.toLat != null) LatLng(_crew.toLat!, _crew.toLng!),
  ];

  @override
  Widget build(BuildContext context) {
    final stops = _stops;
    final state = _state;
    return Scaffold(
      appBar: AppBar(title: Text('Course ${_crew.from} → ${_crew.to}')),
      body: ListView(
        children: [
          if (stops.length >= 2 && _crew.toLat != null)
            LiveRideMap(
              stops: stops,
              destination: LatLng(_crew.toLat!, _crew.toLng!),
              markers: [
                RideMarker(stops.first, icon: Icons.trip_origin),
                for (final s in _crew.stops)
                  if (s.lat != null) RideMarker(LatLng(s.lat!, s.lng!), color: MboaColors.sun, icon: Icons.person_pin_circle),
                RideMarker(stops.last, color: MboaColors.red, icon: Icons.place),
              ],
              showMapTiles: widget.showMapTiles,
              routeLoader: widget.routeLoader,
              initialMode: widget.initialMode,
              acceleration: widget.acceleration,
              onArrived: _arrive,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  InfoBanner(_error!, icon: Icons.error_outline),
                  const SizedBox(height: 10),
                ],
                if (state != null) StatusPill(state.status.label, tone: state.paidOut ? PillTone.success : PillTone.warning),
                const SizedBox(height: 10),
                if (_crew.meetingPoint != null)
                  InfoBanner(
                    '${_crew.meetingPoint}${_crew.meetingInstructions == null ? '' : ' · ${_crew.meetingInstructions}'}',
                    title: 'Point de ramassage',
                    icon: Icons.place_outlined,
                  ),
                const SizedBox(height: 10),
                const Overline('Passagers'),
                const SizedBox(height: 6),
                for (final s in _crew.stops) _passenger(s, state),
                const SizedBox(height: 14),
                if (state == null || state.status == CourseStatus.running || state.status == CourseStatus.notStarted)
                  FilledButton.icon(
                    onPressed: _busy || state == null ? null : _arrive,
                    icon: const Icon(Icons.flag),
                    label: Text("Arrivé à ${_crew.to} : terminer la course"),
                  )
                else
                  _settlement(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _passenger(CrewStop s, CourseState? state) {
    final validated = state?.passengers.any((p) => p.firstName == s.passenger && p.validated) ?? s.endValidated;
    return DriverCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Icon(validated ? Icons.check_circle : Icons.person_outline, color: validated ? MboaColors.green : MboaColors.mutedText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${s.place} à ${frenchTime(s.pickupTime)}${validated ? ' · fin validée' : ''}',
                    style: const TextStyle(fontSize: 13, color: MboaColors.mutedText)),
              ],
            ),
          ),
          if (s.phone != null) CallButton(phone: s.phone!, name: s.passenger),
        ],
      ),
    );
  }

  Widget _settlement(CourseState state) {
    if (state.paidOut) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBanner(
            'Tout l\'équipage a validé la fin de la course. ${fcfa(state.driverAmountFcfa)} ont été versés dans '
            'votre portefeuille (prix payé ${fcfa(state.totalPaidFcfa)}, commission MboaRide de 10 % : '
            '${fcfa(state.commissionFcfa)}).',
            title: 'Course réglée',
            icon: Icons.savings_outlined,
          ),
          if (widget.walletRepository != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => WalletScreen(repository: widget.walletRepository!, driver: true)),
              ),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Voir mon portefeuille'),
            ),
          ],
        ],
      );
    }
    final waiting = state.waitingFor;
    return InfoBanner(
      '${state.validations} passager(s) sur ${state.passengers.length} ont validé la fin de la course. '
      '${waiting.isEmpty ? '' : 'En attente de ${waiting.join(', ')}. '}'
      'Vous recevrez ${fcfa(state.driverAmountFcfa)} dans votre portefeuille dès que tous auront validé.',
      title: 'Fin de course : validations en cours',
      warm: true,
    );
  }
}
