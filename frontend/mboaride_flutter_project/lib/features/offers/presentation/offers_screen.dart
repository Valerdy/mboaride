import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../../preferences/domain/preferences.dart';
import '../data/offers_repository.dart';
import '../domain/offer.dart';
import 'price_confirmation_screen.dart';

/// US05 · Recevoir des propositions de trajets compatibles.
///
/// Les offres sont celles que les agents ont négociées pour la demande. Quand
/// aucune n'est confirmable, l'écran explique pourquoi (nombre de trajets
/// examinés, motifs de rejet) et propose les actions correctives, dont
/// l'élargissement du cercle de confiance.
class OffersScreen extends StatefulWidget {
  const OffersScreen({
    super.key,
    required this.repository,
    required this.request,
  });

  final OffersRepository repository;
  final RideRequestSummary request;

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  List<Offer> _offers = const [];
  Diagnostic? _diagnostic;
  bool _loading = true;
  bool _widening = false;
  String? _error;
  String? _notice;

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
      final offers = await widget.repository.offersFor(widget.request.id);
      Diagnostic? diagnostic;
      if (!offers.any((o) => o.bookable)) {
        diagnostic = await widget.repository.diagnosticFor(widget.request.id);
      }
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _diagnostic = diagnostic;
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

  Future<void> _widen(Suggestion suggestion) async {
    final code = suggestion.circleCode;
    if (code == null || _widening) return;
    setState(() {
      _widening = true;
      _notice = null;
    });
    try {
      final offers = await widget.repository.widenCircle(widget.request.id, code);
      if (!mounted) return;
      Diagnostic? diagnostic;
      if (!offers.any((o) => o.bookable)) {
        diagnostic = await widget.repository.diagnosticFor(widget.request.id);
      }
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _diagnostic = diagnostic;
        _widening = false;
        _notice = offers.any((o) => o.bookable)
            ? 'Cercle élargi : ${offers.where((o) => o.bookable).length} offre(s) confirmable(s).'
            : 'Cercle élargi, mais aucune offre ne convient encore.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _widening = false;
        _notice = error.message;
      });
    }
  }

  Future<void> _open(Offer offer) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PriceConfirmationScreen(
          repository: widget.repository,
          offer: offer,
          date: widget.request.dateFor(DateTime.now()),
        ),
      ),
    );
    if (booked == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bookable = _offers.where((o) => o.bookable).toList();
    final rejected = _offers.where((o) => !o.bookable).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Propositions')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                children: [
                  _Header(request: widget.request, offers: _offers),
                  if (_notice != null) ...[
                    const SizedBox(height: 14),
                    _Notice(text: _notice!),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _Notice(text: _error!),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Réessayer'),
                    ),
                  ],
                  if (bookable.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const _SectionTitle('À confirmer'),
                    const SizedBox(height: 8),
                    ...bookable.map(
                      (offer) => _OfferCard(
                        offer: offer,
                        onTap: () => _open(offer),
                      ),
                    ),
                  ],
                  if (_diagnostic != null && bookable.isEmpty) ...[
                    const SizedBox(height: 18),
                    _DiagnosticPanel(
                      diagnostic: _diagnostic!,
                      busy: _widening,
                      onWiden: _widen,
                    ),
                  ],
                  if (rejected.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const _SectionTitle('Écartées par les agents'),
                    const SizedBox(height: 8),
                    ...rejected.map((offer) => _OfferCard(offer: offer)),
                  ],
                  if (_error == null && _offers.isEmpty && _diagnostic == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text(
                        'Aucun trajet ne correspond pour le moment. Tirez vers le '
                        'bas pour relancer la recherche.',
                        style: TextStyle(color: MboaColors.mutedText),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.request, required this.offers});

  final RideRequestSummary request;
  final List<Offer> offers;

  @override
  Widget build(BuildContext context) {
    final bookable = offers.where((o) => o.bookable).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MboaColors.night,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.label,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Arrivée entre ${request.earliest} et ${request.latest} · '
            'maximum ${formatFcfa(request.maxPriceFcfa)}',
            style: const TextStyle(fontSize: 13, color: Color(0xFFCBD6CF)),
          ),
          const SizedBox(height: 10),
          Text(
            offers.isEmpty
                ? 'Les agents n\'ont encore rien proposé.'
                : '${offers.length} proposition(s) · $bookable confirmable(s)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MboaColors.sun,
            ),
          ),
          if (request.modeCode == 'autonome')
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Mode autonome : l\'agent peut confirmer seul la meilleure offre.',
                style: TextStyle(fontSize: 12, color: Color(0xFFCBD6CF)),
              ),
            ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, this.onTap});

  final Offer offer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final blocked = !offer.bookable;
    final reason = offer.blockedReason;
    return Opacity(
      opacity: blocked ? 0.62 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: blocked ? MboaColors.border : MboaColors.green,
            width: blocked ? 1 : 1.5,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer.driver,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: MboaColors.night,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            offer.route,
                            style: const TextStyle(
                              fontSize: 13,
                              color: MboaColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatFcfa(offer.priceFcfa),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: offer.withinBudget
                            ? MboaColors.green
                            : MboaColors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Tag(text: offer.circleLabel),
                    if (offer.pickupTime != null)
                      _Tag(text: 'Départ ${offer.pickupTime}'),
                    if (offer.arrivalTime != null)
                      _Tag(text: 'Arrivée ${offer.arrivalTime}'),
                    if (offer.detourKm != null)
                      _Tag(
                        text:
                            'Détour ${offer.detourKm!.toStringAsFixed(1).replaceAll('.', ',')} km',
                      ),
                  ],
                ),
                if (blocked && reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.block, size: 16, color: MboaColors.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            reason,
                            style: const TextStyle(
                              fontSize: 13,
                              color: MboaColors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!blocked)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Voir le détail du prix et confirmer',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: MboaColors.green,
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
}

class _DiagnosticPanel extends StatelessWidget {
  const _DiagnosticPanel({
    required this.diagnostic,
    required this.busy,
    required this.onWiden,
  });

  final Diagnostic diagnostic;
  final bool busy;
  final Future<void> Function(Suggestion) onWiden;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: MboaColors.sun, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Aucune offre ne convient pour l\'instant',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MboaColors.night,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${diagnostic.examinedTrips} trajet(s) examiné(s) par les agents.',
          style: const TextStyle(fontSize: 13, color: MboaColors.mutedText),
        ),
        if (diagnostic.reasons.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...diagnostic.reasons.map(
            (reason) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('· ', style: TextStyle(color: MboaColors.night)),
                  Expanded(
                    child: Text(
                      '${reason.label} (${reason.trips} trajet(s))',
                      style: const TextStyle(
                        fontSize: 13,
                        color: MboaColors.night,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (diagnostic.suggestions.isNotEmpty) ...[
          const Divider(height: 24),
          const Text(
            'Ce que vous pouvez faire',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: MboaColors.night,
            ),
          ),
          const SizedBox(height: 8),
          ...diagnostic.suggestions.map(
            (suggestion) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MboaColors.night,
                    ),
                  ),
                  if (suggestion.action == 'elargir' &&
                      suggestion.circleCode != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: FilledButton(
                        onPressed: busy ? null : () => onWiden(suggestion),
                        child: Text(
                          'Élargir au cercle '
                          '${Circle.fromCode(suggestion.circleCode!).label.toLowerCase()}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: MboaColors.night,
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: MboaColors.sand,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: MboaColors.line),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: MboaColors.night),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: MboaColors.sun,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: MboaColors.night,
      ),
    ),
  );
}
