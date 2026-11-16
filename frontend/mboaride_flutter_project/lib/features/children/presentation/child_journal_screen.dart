import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/children_repository.dart';
import '../domain/child.dart';

/// US19 · Recevoir une notification au départ et à l'arrivée à l'école,
/// pour être rassuré. Les notifications sont simulées côté serveur : le
/// journal montre ce que le parent a reçu.
class ChildJournalScreen extends StatefulWidget {
  const ChildJournalScreen({
    super.key,
    required this.repository,
    required this.child,
  });

  final ChildrenRepository repository;
  final Child child;

  @override
  State<ChildJournalScreen> createState() => _ChildJournalScreenState();
}

class _ChildJournalScreenState extends State<ChildJournalScreen> {
  List<ChildEvent> _events = const [];
  bool _loading = true;
  String? _error;

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
      final events = await widget.repository.journal(widget.child.id);
      if (!mounted) return;
      setState(() {
        _events = events;
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.child.name)),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
              children: [
                Text(
                  '${widget.child.school} · ${widget.child.age} ans',
                  style: const TextStyle(
                    fontSize: 13,
                    color: MboaColors.mutedText,
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: MboaColors.red)),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _load,
                    child: const Text('Réessayer'),
                  ),
                ],
                if (_error == null && _events.isEmpty)
                  const Text(
                    'Aucun trajet pour le moment. Vous recevrez une '
                    'notification dès la montée à bord et à l\'arrivée à '
                    'l\'école.',
                    style: TextStyle(color: MboaColors.mutedText),
                  ),
                ..._events.map((event) => _EventTile(event: event)),
              ],
            ),
    ),
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final ChildEvent event;

  @override
  Widget build(BuildContext context) {
    final color = event.isArrival
        ? MboaColors.green
        : event.isDeparture
        ? MboaColors.sun
        : MboaColors.mutedText;
    final icon = event.isArrival
        ? Icons.school
        : event.isDeparture
        ? Icons.directions_car_filled
        : Icons.event_available;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE3DE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: MboaColors.sand,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MboaColors.night,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  event.driver == null
                      ? event.at
                      : '${event.at} · ${event.driver}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: MboaColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
