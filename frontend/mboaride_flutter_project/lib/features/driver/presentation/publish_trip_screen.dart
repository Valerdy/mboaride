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
  final _meetingPoint = TextEditingController();
  final _meetingInstructions = TextEditingController();
  int _waitMinutes = 5;

  /// Trajet ponctuel (une date) plutôt que régulier (jours de la semaine).
  bool _oneDate = false;
  DateTime _date = DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));

  /// Trajets déjà préparés, publiés ensemble avec celui du formulaire.
  final List<TripPlan> _queue = [];

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
    for (final c in [_from, _to, _departure, _tolls, _meetingPoint, _meetingInstructions]) {
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
    weekdays: _kind == TripKind.urban && !_oneDate ? _days : const {},
    date: _kind == TripKind.interurban || _oneDate ? _date : null,
    departure: _departure.text.trim(),
    seats: _seats,
    maxDetourKm: _detourKm,
    tollsFcfa: _kind == TripKind.interurban ? int.tryParse(_tolls.text.trim()) ?? -1 : 0,
    pickupPoints: _kind == TripKind.interurban ? _points : const [],
    meetingPoint: _meetingPoint.text.trim(),
    meetingInstructions: _meetingInstructions.text.trim(),
    waitMinutes: _waitMinutes,
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
      withCommission: true,
    );
  }

  Future<void> _publish() async {
    final plan = _plan;
    final error = plan.error;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_queue.isNotEmpty) return _publishAll([..._queue, plan]);
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
      _closeIfPushed();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = error.message;
      });
    }
  }

  /// Plusieurs trajets d'un coup : chacun est publié ou refusé (doublon, lieu inconnu...).
  Future<void> _publishAll(List<TripPlan> plans) async {
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final result = await widget.repository.publishTrips(plans);
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _queue
          ..clear()
          ..addAll(result.refusals.keys.where((p) => p != plans.last));
        _error = result.refusals.isEmpty
            ? null
            : [for (final e in result.refusals.entries) '${e.key.from} → ${e.key.to} (${e.key.scheduleLabel}) : ${e.value}']
                  .join('\n');
      });
      showDriverMessage(
        context,
        '${result.published} trajet${result.published > 1 ? 's' : ''} programmé${result.published > 1 ? 's' : ''}'
        '${result.refusals.isEmpty ? '' : ', ${result.refusals.length} refusé${result.refusals.length > 1 ? 's' : ''}'}.',
        isError: result.published == 0,
      );
      if (result.refusals.isEmpty) _closeIfPushed();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = error.message;
      });
    }
  }

  /// Ouvert depuis « Mes trajets programmés » : on y revient après la publication.
  void _closeIfPushed() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop(true);
  }

  /// Garde le trajet du formulaire dans la liste, pour en préparer un autre.
  bool _addToQueue() {
    final plan = _plan;
    final error = plan.error;
    if (error != null) {
      setState(() => _error = error);
      return false;
    }
    setState(() {
      _queue.add(plan);
      _error = null;
    });
    return true;
  }

  /// Ajoute le trajet du formulaire à la liste et prépare le retour (départ et arrivée inversés).
  void _addReturn() {
    if (!_addToQueue()) return;
    setState(() {
      final from = _from.text;
      _from.text = _to.text;
      _to.text = from;
      _departure.text = _kind == TripKind.urban ? '17:30' : _departure.text;
      _meetingPoint.clear();
      _meetingInstructions.clear();
      _distanceKm = null;
    });
    _estimate();
    showDriverMessage(context, 'Aller ajouté. Précisez l\'heure et le point de ramassage du retour.');
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      helpText: 'Date du trajet',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Widget _dateTile() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _pickDate,
      icon: const Icon(Icons.event),
      label: Text('Le ${shortDate(_date)}'),
    ),
  );

  Widget _queueCard() => DriverCard(
    padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_queue.length} trajet${_queue.length > 1 ? 's' : ''} prêt${_queue.length > 1 ? 's' : ''} '
            'à programmer avec celui du formulaire',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        for (var i = 0; i < _queue.length; i++)
          Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: MboaColors.green),
              const SizedBox(width: 8),
              Expanded(child: Text('${_queue[i].from} → ${_queue[i].to} · ${_queue[i].scheduleLabel}')),
              IconButton(
                tooltip: 'Retirer de la liste',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _queue.removeAt(i)),
              ),
            ],
          ),
      ],
    ),
  );

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
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Chaque semaine'), icon: Icon(Icons.repeat, size: 18)),
                ButtonSegment(value: true, label: Text('Une date'), icon: Icon(Icons.event, size: 18)),
              ],
              selected: {_oneDate},
              onSelectionChanged: (s) => setState(() => _oneDate = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 10),
          ],
          if (!interurban && _oneDate) _dateTile(),
          if (interurban) _dateTile(),
          if (!interurban && !_oneDate) ...[
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
          ],
          if (interurban) ...[
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
          const SizedBox(height: 14),
          const Text('Point de ramassage', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('point-ramassage'),
            controller: _meetingPoint,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Lieu exact où vos passagers vous retrouvent',
              hintText: 'Station Total de Logpom, côté boulangerie',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _meetingInstructions,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Consignes (facultatif)',
              hintText: 'Berline grise LT 482 AB, je klaxonne deux fois',
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text('Attente maximale au point de ramassage', style: TextStyle(fontSize: 14)),
              ),
              DropdownButton<int>(
                value: _waitMinutes,
                items: [for (final m in const [0, 2, 3, 5, 10, 15]) DropdownMenuItem(value: m, child: Text('$m min'))],
                onChanged: (m) => setState(() => _waitMinutes = m ?? 5),
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
          if (_queue.isNotEmpty) ...[
            _queueCard(),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: _publishing ? null : _addToQueue,
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('Ajouter un autre'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: _publishing ? null : _addReturn,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Ajouter le retour'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _publishing ? null : _publish,
            child: Text(_publishing
                ? 'Publication…'
                : _queue.isNotEmpty
                ? 'Programmer les ${_queue.length + 1} trajets'
                : (interurban ? 'Publier le voyage' : 'Publier le trajet')),
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
        'quand vos $_seats places sont prises (hors détour). Le prix comprend la commission MboaRide '
        'de 10 % ; vous recevez le reste dans votre portefeuille à la fin de la course.',
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
