import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';

/// Publier un trajet (wireframes 5 et 6) : trajet régulier en ville, ou voyage interurbain
/// avec points de départ et péages. Le prix estimé suit la règle du produit : le carburant
/// du trajet commun est partagé entre le conducteur et les passagers à bord.
class PublishTripScreen extends StatefulWidget {
  const PublishTripScreen({super.key, required this.repository});

  final DriverRepository repository;

  @override
  State<PublishTripScreen> createState() => _PublishTripScreenState();
}

class _PublishTripScreenState extends State<PublishTripScreen> {
  static const double _maxUrbanDetourKm = 5;
  static const double _maxIntercityDetourKm = 10;

  final _from = TextEditingController(text: 'Logpom');
  final _to = TextEditingController(text: 'Bonabéri');
  final _departure = TextEditingController(text: '06:45');
  final _tolls = TextEditingController(text: '1000');

  TripKind _kind = TripKind.urban;
  Set<int> _days = {1, 2, 3, 4, 5};
  int _seats = 3;
  double _detourKm = 2;
  List<String> _points = const ['Akwa', 'Ndokoti'];

  double? _consumption;
  double? _distanceKm;
  String? _estimateError;
  bool _publishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVehicleThenEstimate();
  }

  @override
  void dispose() {
    for (final c in [_from, _to, _departure, _tolls]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadVehicleThenEstimate() async {
    try {
      final vehicle = await widget.repository.vehicle();
      if (!mounted) return;
      setState(() {
        _consumption = vehicle.consumptionL100;
        _seats = vehicle.seats;
      });
      await _estimate();
    } on ApiException catch (error) {
      if (mounted) setState(() => _estimateError = error.message);
    }
  }

  Future<void> _estimate() async {
    try {
      final distance = await widget.repository.estimateDistanceKm(_from.text, _to.text);
      if (!mounted) return;
      setState(() {
        _distanceKm = distance;
        _estimateError = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _estimateError = error.message);
    }
  }

  void _setKind(TripKind kind) {
    setState(() {
      _kind = kind;
      if (kind == TripKind.interurban) {
        _from.text = 'Douala';
        _to.text = 'Yaoundé';
        _departure.text = '14:00';
        _seats = 4;
        _detourKm = 6;
      } else {
        _from.text = 'Logpom';
        _to.text = 'Bonabéri';
        _departure.text = '06:45';
        _detourKm = 2;
      }
      _distanceKm = null;
      _error = null;
    });
    _estimate();
  }

  TripPlan get _plan => TripPlan(
    kind: _kind,
    from: _from.text.trim(),
    to: _to.text.trim(),
    weekdays: _kind == TripKind.urban ? _days : const {},
    departure: _departure.text.trim(),
    seats: _seats,
    maxDetourKm: _detourKm,
    tollsFcfa: _kind == TripKind.interurban ? int.tryParse(_tolls.text.trim()) ?? -1 : 0,
    pickupPoints: _kind == TripKind.interurban ? _points : const [],
  );

  PriceEstimate? get _priceEstimate {
    final distance = _distanceKm;
    final consumption = _consumption;
    if (distance == null || consumption == null) return null;
    final interurban = _kind == TripKind.interurban;
    return PriceEstimate.compute(
      distanceKm: distance,
      consumptionL100: consumption,
      seats: _seats,
      tollsFcfa: interurban ? (int.tryParse(_tolls.text.trim()) ?? 0) : 0,
      withCommission: interurban,
    );
  }

  Future<void> _publish() async {
    final plan = _plan;
    final error = plan.error;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      await widget.repository.publishTrip(plan);
      if (!mounted) return;
      setState(() => _publishing = false);
      showDriverMessage(
        context,
        plan.kind == TripKind.urban
            ? 'Trajet publié : votre agent répondra aux demandes compatibles.'
            : 'Voyage publié : les voyageurs peuvent réserver une place.',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = error.message;
      });
    }
  }

  Future<void> _addPoint() async {
    final controller = TextEditingController();
    final point = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter un point de départ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quartier ou lieu'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (point != null && point.isNotEmpty && !_points.contains(point)) {
      setState(() => _points = [..._points, point]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final interurban = _kind == TripKind.interurban;
    final maxDetour = interurban ? _maxIntercityDetourKm : _maxUrbanDetourKm;
    return Scaffold(
      appBar: AppBar(title: const Text('Publier un trajet')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          SegmentedButton<TripKind>(
            segments: const [
              ButtonSegment(value: TripKind.urban, label: Text('Urbain')),
              ButtonSegment(value: TripKind.interurban, label: Text('Interurbain')),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) => _setKind(selection.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _from,
            decoration: const InputDecoration(labelText: 'Départ'),
            onSubmitted: (_) => _estimate(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _to,
            decoration: const InputDecoration(labelText: 'Arrivée'),
            onSubmitted: (_) => _estimate(),
          ),
          const SizedBox(height: 12),
          if (!interurban) ...[
            const Text('Jours', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var day = 1; day <= 7; day++) ...[
                  if (day > 1) const SizedBox(width: 6),
                  Expanded(child: _dayButton(day)),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ] else ...[
            const Text('Points de départ possibles', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final point in _points)
                  InputChip(
                    label: Text(point),
                    onDeleted: _points.length > 1
                        ? () => setState(() => _points = _points.where((p) => p != point).toList())
                        : null,
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter un point'),
                  onPressed: _addPoint,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _departure,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Heure de départ', hintText: '06:45'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Places', contentPadding: EdgeInsets.fromLTRB(14, 4, 4, 4)),
                  child: Row(
                    children: [
                      Expanded(child: Text('$_seats', style: const TextStyle(fontSize: 16))),
                      IconButton(
                        tooltip: 'Retirer une place',
                        onPressed: _seats > Vehicle.minSeats ? () => setState(() => _seats--) : null,
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        tooltip: 'Ajouter une place',
                        onPressed: _seats < Vehicle.maxSeats ? () => setState(() => _seats++) : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (interurban) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _tolls,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Péages (FCFA)'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('Détour maximal accepté', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              Text(km(_detourKm), style: const TextStyle(fontWeight: FontWeight.w700, color: MboaColors.green)),
            ],
          ),
          Slider(
            value: _detourKm.clamp(0.5, maxDetour),
            min: 0.5,
            max: maxDetour,
            divisions: (maxDetour * 2 - 1).round(),
            label: km(_detourKm),
            onChanged: (v) => setState(() => _detourKm = v),
          ),
          _estimateBox(interurban),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: MboaColors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _publishing ? null : _publish,
            child: Text(_publishing ? 'Publication…' : (interurban ? 'Publier le voyage' : 'Publier le trajet')),
          ),
        ],
      ),
    );
  }

  Widget _dayButton(int day) {
    final selected = _days.contains(day);
    return Semantics(
      label: weekdayNames[day - 1],
      selected: selected,
      button: true,
      child: SizedBox(
        height: 44,
        child: selected
            ? FilledButton(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => setState(() => _days = {..._days}..remove(day)),
                child: Text(weekdayLetters[day - 1]),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => setState(() => _days = {..._days, day}),
                child: Text(weekdayLetters[day - 1]),
              ),
      ),
    );
  }

  Widget _estimateBox(bool interurban) {
    if (_estimateError != null) {
      return InfoBanner('Estimation du prix indisponible. $_estimateError', icon: Icons.cloud_off_outlined);
    }
    final estimate = _priceEstimate;
    if (estimate == null) {
      return const InfoBanner('Calcul de l\'estimation…', warm: true);
    }
    final consumption = _consumption!;
    final fuelLine =
        '${km(estimate.distanceKm)} × ${consumption.toStringAsFixed(consumption == consumption.roundToDouble() ? 0 : 1)} L/100 km '
        '× $fuelPricePerLitre FCFA = ${fcfa(estimate.fuelFcfa)} de carburant';
    if (!interurban) {
      return InfoBanner(
        '$fuelLine, partagés entre vous et les passagers à bord : '
        '${fcfa(estimate.alonePrice)} pour un passager seul, ${fcfa(estimate.fullPrice)} chacun '
        'quand vos $_seats places sont prises (hors détour).',
        title: 'Environ ${fcfa(estimate.fullPrice)} par passager, voiture pleine',
        warm: true,
      );
    }
    return InfoBanner(
      '$fuelLine, plus ${fcfa(estimate.tollsFcfa)} de péages, partagés entre vous et les passagers '
      'à bord, plus 10 % de commission MboaRide. Un passager seul paie ${fcfa(estimate.alonePrice)}. '
      'Billet de car classique : ${fcfa(3500)}.',
      title: 'Environ ${fcfa(estimate.fullPrice)} par passager, voiture pleine',
      warm: true,
    );
  }
}
