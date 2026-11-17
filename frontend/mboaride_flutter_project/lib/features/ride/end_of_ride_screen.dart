import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/mboa_theme.dart';
import '../payment/data/payment_repository.dart';
import '../payment/domain/payment.dart';

/// Arrivée à destination : le passager valide la fin de la course, note la course et le
/// conducteur, et peut laisser un commentaire. Le conducteur est payé, dans son portefeuille,
/// quand tout l'équipage a validé.
class EndOfRideScreen extends StatefulWidget {
  const EndOfRideScreen({super.key, required this.repository, required this.tracking});

  final PaymentRepository repository;
  final RideTracking tracking;

  @override
  State<EndOfRideScreen> createState() => _EndOfRideScreenState();
}

class _EndOfRideScreenState extends State<EndOfRideScreen> {
  int _rating = 0;
  bool _serious = false;
  bool _busy = false;
  String? _error;
  EndOfRideResult? _result;
  final _comment = TextEditingController();

  static const List<String> _ratingLabels = ['', 'Mauvaise', 'Passable', 'Correcte', 'Bonne', 'Excellente'];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.validateEndOfRide(
        widget.tracking.bookingId,
        rating: _rating,
        comment: _comment.text,
        serious: _serious,
      );
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tracking;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Fin de la course'), automaticallyImplyLeading: result != null),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          const Icon(Icons.flag_circle, size: 64, color: MboaColors.green),
          const SizedBox(height: 10),
          Text(
            'Vous êtes arrivé à ${t.to.label}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MboaColors.night),
          ),
          const SizedBox(height: 6),
          const Text(
            "Merci d'avoir utilisé MboaRide !",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: MboaColors.green, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          if (result == null) ..._form(t) else ..._done(result),
        ],
      ),
    );
  }

  List<Widget> _form(RideTracking t) => [
    Text(
      'Notez la course et ${t.driver}',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var star = 1; star <= 5; star++)
          IconButton(
            key: ValueKey('etoile-$star'),
            tooltip: '$star sur 5',
            iconSize: 40,
            onPressed: _busy ? null : () => setState(() => _rating = star),
            icon: Icon(
              star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: star <= _rating ? MboaColors.sun : MboaColors.border,
            ),
          ),
      ],
    ),
    Text(
      _rating == 0 ? 'Touchez une étoile' : _ratingLabels[_rating],
      textAlign: TextAlign.center,
      style: const TextStyle(color: MboaColors.mutedText),
    ),
    const SizedBox(height: 18),
    TextField(
      controller: _comment,
      maxLines: 3,
      maxLength: 500,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'Votre commentaire (facultatif)',
        hintText: 'Ponctualité, conduite, propreté du véhicule…',
      ),
    ),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _serious,
      onChanged: _busy ? null : (v) => setState(() => _serious = v ?? false),
      title: const Text('Signaler un problème grave'),
      subtitle: const Text("L'agrément du conducteur est suspendu le temps de l'enquête."),
    ),
    if (_error != null) ...[
      const SizedBox(height: 8),
      Text(_error!, style: const TextStyle(color: MboaColors.red)),
    ],
    const SizedBox(height: 14),
    FilledButton.icon(
      onPressed: _busy || _rating == 0 ? null : _validate,
      icon: const Icon(Icons.check_circle_outline),
      label: Text(_busy ? 'Validation…' : 'Valider la fin de la course'),
    ),
  ];

  List<Widget> _done(EndOfRideResult r) => [
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFE6F2ED), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fin de course validée', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Vous avez donné ${r.rating}/5 à ${r.driver}.'),
        ],
      ),
    ),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: () => Navigator.of(context).pop(true),
      child: const Text('Terminer'),
    ),
  ];
}
