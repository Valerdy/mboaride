import 'package:flutter/material.dart';

import '../../../core/mboa_theme.dart';
import '../../payment/data/payment_repository.dart';
import '../../wallet/wallet_screen.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';

/// Gains et frais couverts (wireframe 11). L'objectif du document de vision est que les
/// passagers couvrent au moins la moitié des frais de carburant du conducteur.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key, required this.repository, this.walletRepository});

  final DriverRepository repository;
  final PaymentRepository? walletRepository;

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  late Future<Earnings> _loading = widget.repository.earnings();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gains et frais')),
    body: AsyncView<Earnings>(
      future: _loading,
      onRetry: () => setState(() => _loading = widget.repository.earnings()),
      builder: (context, earnings) {
        final coverage = earnings.lastTripCoverage;
        final percent = (coverage * 100).round();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(earnings.monthLabel, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (widget.walletRepository != null) ...[
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => WalletScreen(repository: widget.walletRepository!, driver: true),
                )),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Mon portefeuille : solde, virements'),
              ),
              const SizedBox(height: 12),
            ],
            DriverCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Overline('Part de vos frais couverte'),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 8,
                    children: [
                      Text('$percent %', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: MboaColors.green)),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text('sur votre dernier trajet', style: TextStyle(fontSize: 14, color: MboaColors.mutedText)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _coverageBar(coverage),
                  const SizedBox(height: 8),
                  Text(
                    '${fcfa(earnings.lastTripReceivedFcfa)} reçus pour ${fcfa(earnings.lastTripFuelFcfa)} de carburant · '
                    'objectif ${(coverageTarget * 100).round()} %',
                    style: const TextStyle(fontSize: 13, color: MboaColors.mutedText),
                  ),
                  const Divider(height: 24, color: DriverColors.line),
                  Text(
                    'Ce mois : ${fcfa(earnings.receivedThisMonthFcfa)} reçus'
                    '${earnings.pendingFcfa > 0 ? ' · ${fcfa(earnings.pendingFcfa)} en attente' : ''}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SectionTitle('Courses · versées à la fin de la course, commission déduite'),
            DriverCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < earnings.payments.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: DriverColors.line),
                    _paymentRow(earnings.payments[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const InfoBanner(
              'Le carburant du trajet commun, détour compris, est partagé entre vous et les passagers à bord. '
              'Plus votre voiture est pleine, plus vos frais sont couverts. MboaRide garde 10 % du prix de '
              'chaque place et vous verse le reste quand tout l\'équipage a validé la fin de la course.',
              title: 'Comment votre part est calculée',
              warm: true,
            ),
          ],
        );
      },
    ),
  );

  Widget _coverageBar(double coverage) => Semantics(
    label: '${(coverage * 100).round()} % des frais couverts, objectif ${(coverageTarget * 100).round()} %',
    child: SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: coverage.clamp(0, 1).toDouble(),
                minHeight: 12,
                backgroundColor: DriverColors.line,
                color: coverage >= coverageTarget ? MboaColors.green : MboaColors.sun,
              ),
            ),
            Positioned(
              left: constraints.maxWidth * coverageTarget - 1,
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: MboaColors.night),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _paymentRow(Payment payment) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${payment.dateLabel} · ${payment.route}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Text('${payment.passengers} passager${payment.passengers > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 13, color: MboaColors.mutedText)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fcfa(payment.amountFcfa), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            if (payment.commissionFcfa > 0)
              Text('commission ${fcfa(payment.commissionFcfa)}',
                  style: const TextStyle(fontSize: 11.5, color: MboaColors.mutedText)),
            Text(
              payment.received ? 'Versé au portefeuille' : 'Fin de course à valider',
              style: TextStyle(fontSize: 12, color: payment.received ? MboaColors.green : DriverColors.sunText),
            ),
          ],
        ),
      ],
    ),
  );
}
