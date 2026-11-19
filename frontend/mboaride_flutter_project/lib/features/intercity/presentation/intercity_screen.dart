import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/intercity_repository.dart';
import '../domain/intercity_trip.dart';

/// US22 · Réserver une place plusieurs jours à l'avance, pour organiser mon
/// voyage. Le voyageur choisit la date, le voyage, puis son point de montée.
class IntercityScreen extends StatefulWidget {
  const IntercityScreen({
    super.key,
    required this.repository,
    this.childId,
    this.childName,
  });

  final IntercityRepository repository;

  /// Réservation faite par un parent pour un élève autorisé (US17).
  final int? childId;
  final String? childName;

  @override
  State<IntercityScreen> createState() => _IntercityScreenState();
}

class _IntercityScreenState extends State<IntercityScreen> {
  late DateTime _date = _today.add(const Duration(days: 2));
  List<IntercityTrip> _trips = const [];
  bool _loading = true;
  String? _error;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trips = await widget.repository.trips(_date);
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _pickDate(DateTime date) {
    if (date == _date) return;
    setState(() => _date = date);
    _load();
  }

  Future<void> _book(IntercityTrip trip) async {
    final booking = await showModalBottomSheet<SeatBooking>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SeatSheet(
        repository: widget.repository,
        trip: trip,
        date: _date,
        childId: widget.childId,
        childName: widget.childName,
      ),
    );
    if (booking != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${booking.seats > 1 ? '${booking.seats} places confirmées' : 'Place confirmée'} · ${formatFcfa(booking.priceFcfa)} · '
            'montée à ${booking.pickupLabel} à ${booking.pickupTime}',
          ),
        ),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(15, (i) => _today.add(Duration(days: i + 1)));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.childName == null
              ? 'Voyages interurbains'
              : 'Voyage pour ${widget.childName}',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Réservez jusqu\'à deux semaines à l\'avance. Date du voyage : '
                '${_frenchDate(_date)}.',
                style: const TextStyle(
                  fontSize: 13,
                  color: MboaColors.mutedText,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final day = days[index];
                final selected = day == _date;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickDate(day),
                  child: Container(
                    width: 64,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? MboaColors.green : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? MboaColors.green
                            : MboaColors.border,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _shortDay(day),
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? Colors.white70
                                : MboaColors.mutedText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          day.day.toString(),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : MboaColors.night,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
                      children: [
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: const TextStyle(color: MboaColors.red),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _load,
                            child: const Text('Réessayer'),
                          ),
                        ],
                        if (_error == null && _trips.isEmpty)
                          const Text(
                            'Aucun voyage publié pour cette date. Essayez une '
                            'autre date : les conducteurs publient souvent une '
                            'semaine à l\'avance.',
                            style: TextStyle(color: MboaColors.mutedText),
                          ),
                        ..._trips.map(
                          (trip) => _TripCard(
                            trip: trip,
                            onTap: trip.isFull ? null : () => _book(trip),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _shortDay(DateTime date) {
    const days = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    return days[date.weekday - 1];
  }

  static String _frenchDate(DateTime date) {
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, this.onTap});

  final IntercityTrip trip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: trip.isFull ? 0.6 : 1,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: trip.isFull ? MboaColors.border : MboaColors.green,
          width: trip.isFull ? 1 : 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.route,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: MboaColors.night,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Départ ${trip.departureTime} · ${trip.driver}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: MboaColors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    trip.priceLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: MboaColors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Tag(
                    text: trip.seatsLabel,
                    strong: !trip.isFull && trip.seatsLeft <= 1,
                  ),
                  _Tag(text: '${trip.points.length} point(s) de montée'),
                  ...trip.comfort.map((c) => _Tag(text: c)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  trip.isFull
                      ? 'Ce voyage est complet.'
                      : 'Choisir mon point de montée et réserver',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: trip.isFull ? MboaColors.red : MboaColors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SeatSheet extends StatefulWidget {
  const _SeatSheet({
    required this.repository,
    required this.trip,
    required this.date,
    this.childId,
    this.childName,
  });

  final IntercityRepository repository;
  final IntercityTrip trip;
  final DateTime date;
  final int? childId;
  final String? childName;

  @override
  State<_SeatSheet> createState() => _SeatSheetState();
}

class _SeatSheetState extends State<_SeatSheet> {
  late int _pointId = widget.trip.points.isEmpty
      ? 0
      : widget.trip.points.first.id;
  bool _saving = false;
  String? _error;
  int _seats = 1;

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final booking = await widget.repository.bookSeat(
        tripId: widget.trip.id,
        pickupPointId: _pointId,
        date: widget.date,
        childId: widget.childId,
        seats: _seats,
        announcedPriceFcfa: widget.trip.priceFcfa * _seats,
      );
      if (!mounted) return;
      Navigator.of(context).pop(booking);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      18,
      18,
      18,
      18 + MediaQuery.of(context).viewInsets.bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.trip.route,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: MboaColors.night,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Départ ${widget.trip.departureTime} · ${widget.trip.driver} · '
          '${widget.trip.priceLabel}',
          style: const TextStyle(fontSize: 13, color: MboaColors.mutedText),
        ),
        if (widget.childName != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Place réservée pour ${widget.childName}.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MboaColors.green,
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Point de montée',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: MboaColors.night,
          ),
        ),
        const SizedBox(height: 6),
        ...widget.trip.points.map(
          (point) => InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _pointId = point.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _pointId == point.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: _pointId == point.id
                        ? MboaColors.green
                        : MboaColors.border,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      point.label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: MboaColors.night,
                      ),
                    ),
                  ),
                  Text(
                    point.time,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MboaColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.childId == null && widget.trip.seatsLeft > 1) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Places à réserver',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: MboaColors.night),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Moins de places',
                onPressed: _seats > 1 ? () => setState(() => _seats--) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '$_seats',
                  key: const ValueKey('nombre-de-places'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Plus de places',
                onPressed: _seats < widget.trip.seatsLeft ? () => setState(() => _seats++) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const Text(
            'Chaque place coûte le même prix.',
            style: TextStyle(fontSize: 12, color: MboaColors.mutedText),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: MboaColors.red),
            ),
          ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _saving || widget.trip.points.isEmpty ? null : _confirm,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_seats > 1
                  ? 'Réserver $_seats places · ${formatFcfa(widget.trip.priceFcfa * _seats)}'
                  : 'Réserver · ${widget.trip.priceLabel}'),
        ),
      ],
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: strong ? MboaColors.sun : MboaColors.sand,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: MboaColors.line),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
        color: MboaColors.night,
      ),
    ),
  );
}
