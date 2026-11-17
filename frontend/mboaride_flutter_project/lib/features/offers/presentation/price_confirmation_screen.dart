import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/offers_repository.dart';
import '../domain/offer.dart';
import '../../payment/data/payment_repository.dart';
import '../../payment/presentation/payment_screen.dart';

/// US09 · Connaître le prix avant de confirmer.
///
/// Le prix affiché est celui que les agents ont négocié. Il est recalculé par
/// le serveur au moment de la confirmation : s'il a changé entre-temps, rien
/// n'est réservé et le nouveau prix est montré avant toute validation.
class PriceConfirmationScreen extends StatefulWidget {
  const PriceConfirmationScreen({
    super.key,
    required this.repository,
    required this.offer,
    required this.date,
    this.payments,
  });

  final OffersRepository repository;

  /// Paiement Mobile Money qui confirme le trajet ; par défaut celui de l'application.
  final PaymentRepository? payments;
  final Offer offer;
  final DateTime date;

  @override
  State<PriceConfirmationScreen> createState() =>
      _PriceConfirmationScreenState();
}

class _PriceConfirmationScreenState extends State<PriceConfirmationScreen> {
  late int _priceFcfa = widget.offer.priceFcfa;
  late List<PriceLine> _lines = widget.offer.priceLines;
  bool _booking = false;
  String? _warning;
  Booking? _booked;
  bool _paid = false;

  Future<void> _confirm() async {
    setState(() {
      _booking = true;
      _warning = null;
    });
    try {
      final booking = await widget.repository.book(
        rideRequestId: widget.offer.rideRequestId,
        tripId: widget.offer.tripId,
        date: widget.date,
        announcedPriceFcfa: _priceFcfa,
      );
      if (!mounted) return;
      setState(() {
        _booked = booking;
        _booking = false;
      });
      await _pay();
    } on PriceChangedException catch (error) {
      if (!mounted) return;
      setState(() {
        _priceFcfa = error.newPriceFcfa;
        if (error.priceLines.isNotEmpty) _lines = error.priceLines;
        _warning =
            '${error.message} Rien n\'a été réservé. Le nouveau prix est '
            '${formatFcfa(error.newPriceFcfa)}.';
        _booking = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _warning = error.message;
        _booking = false;
      });
    }
  }

  /// La place est retenue : le paiement confirme le trajet (US10).
  Future<void> _pay() async {
    final booking = _booked;
    if (booking == null || booking.paymentId == null) return;
    final outcome = await Navigator.of(context).push<PaymentOutcome>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          repository: widget.payments ?? AppServices.payments,
          paymentId: booking.paymentId!,
          amountFcfa: booking.priceFcfa,
          route: widget.offer.route,
          driver: widget.offer.driver,
          date: widget.date,
        ),
      ),
    );
    if (!mounted) return;
    if (outcome == PaymentOutcome.paid) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _paid = false);
    }
  }

  bool get _withinBudget =>
      widget.offer.maxPriceFcfa == 0 || _priceFcfa <= widget.offer.maxPriceFcfa;

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmer le trajet')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          _Card(
            children: [
              Text(
                offer.route,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MboaColors.night,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Avec ${offer.driver} · ${offer.circleLabel}',
                style: const TextStyle(color: MboaColors.mutedText),
              ),
              const SizedBox(height: 10),
              _Row(
                icon: Icons.schedule,
                text:
                    'Prise en charge ${offer.pickupTime ?? '--:--'} · '
                    'arrivée ${offer.arrivalTime ?? '--:--'}',
              ),
              if (offer.detourKm != null)
                _Row(
                  icon: Icons.alt_route,
                  text:
                      'Détour imposé au conducteur : '
                      '${offer.detourKm!.toStringAsFixed(1).replaceAll('.', ',')} km',
                ),
              _Row(
                icon: Icons.event,
                text: 'Date : ${_frenchDate(widget.date)}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Card(
            children: [
              const Text(
                'Calcul du prix',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MboaColors.night,
                ),
              ),
              const SizedBox(height: 10),
              ..._lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          line.label,
                          style: const TextStyle(
                            fontSize: 13,
                            color: MboaColors.mutedText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        formatFcfa(line.amountFcfa),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MboaColors.night,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Vous payez',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: MboaColors.night,
                    ),
                  ),
                  Text(
                    formatFcfa(_priceFcfa),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: MboaColors.green,
                    ),
                  ),
                ],
              ),
              if (offer.maxPriceFcfa > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _withinBudget
                        ? 'Votre maximum : ${formatFcfa(offer.maxPriceFcfa)}'
                        : 'Au-dessus de votre maximum de ${formatFcfa(offer.maxPriceFcfa)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: _withinBudget
                          ? MboaColors.mutedText
                          : MboaColors.red,
                    ),
                  ),
                ),
              if (offer.formula.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    offer.formula,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MboaColors.mutedText,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
          if (_warning != null) ...[
            const SizedBox(height: 14),
            _Banner(text: _warning!),
          ],
          if (_booked != null) ...[
            const SizedBox(height: 14),
            _Success(booking: _booked!, paid: _paid),
          ],
          const SizedBox(height: 20),
          if (_booked == null)
            FilledButton(
              onPressed: _booking || !_withinBudget ? null : _confirm,
              child: _booking
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Confirmer · ${formatFcfa(_priceFcfa)}'),
            )
          else ...[
            if (_booked!.paymentId != null)
              FilledButton.icon(
                onPressed: _pay,
                icon: const Icon(Icons.phone_iphone),
                label: Text('Payer ${formatFcfa(_booked!.priceFcfa)} pour confirmer'),
              ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Plus tard : voir dans « Mes trajets »'),
            ),
          ],
          const SizedBox(height: 10),
          if (_booked == null)
            OutlinedButton(
              onPressed: _booking ? null : () => Navigator.of(context).pop(false),
              child: const Text('Retour aux offres'),
            ),
        ],
      ),
    );
  }

  static String _frenchDate(DateTime date) {
    const days = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche',
    ];
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
    return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE3DE)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 18, color: MboaColors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: MboaColors.night),
          ),
        ),
      ],
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

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

class _Success extends StatelessWidget {
  const _Success({required this.booking, this.paid = false});

  final Booking booking;
  final bool paid;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFE3EFE8),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: MboaColors.green),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: MboaColors.green),
            const SizedBox(width: 8),
            Text(
              paid
                  ? 'Trajet confirmé · ${formatFcfa(booking.priceFcfa)}'
                  : 'Place retenue · à confirmer en payant',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: MboaColors.night,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Prise en charge ${booking.pickupTime ?? '--:--'} · '
          'arrivée ${booking.arrivalTime ?? '--:--'}',
          style: const TextStyle(fontSize: 13, color: MboaColors.night),
        ),
        if (booking.payment.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              booking.payment,
              style: const TextStyle(fontSize: 13, color: MboaColors.mutedText),
            ),
          ),
      ],
    ),
  );
}
