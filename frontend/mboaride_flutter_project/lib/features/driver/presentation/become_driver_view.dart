import 'package:flutter/material.dart';

import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import 'approval_screen.dart';
import 'driver_widgets.dart';

/// Ce que voit un passager qui n'est pas encore chauffeur : la procédure, et le bouton pour la commencer.
class BecomeDriverView extends StatelessWidget {
  const BecomeDriverView({super.key, required this.repository, required this.onChanged});

  final DriverRepository repository;

  /// Appelé au retour de la procédure : le dépôt d'une pièce fait de la personne un conducteur.
  final VoidCallback onChanged;

  Future<void> start(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ApprovalScreen(repository: repository)),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
    children: [
      const Text(
        'Devenez chauffeur MboaRide',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MboaColors.night),
      ),
      const SizedBox(height: 6),
      const Text(
        'Partagez vos trajets, couvrez vos frais et rendez service à vos collègues. '
        'La procédure se fait ici, en trois étapes.',
        style: TextStyle(fontSize: 15, color: MboaColors.mutedText, height: 1.45),
      ),
      const SizedBox(height: 16),
      const DriverCard(
        child: Column(
          children: [
            _Step(
              number: 1,
              title: 'Déposez vos 4 pièces en photo',
              detail: 'Pièce d\'identité, permis de conduire, extrait de casier judiciaire, assurance du véhicule.',
            ),
            Divider(height: 22, color: DriverColors.line),
            _Step(
              number: 2,
              title: 'MboaRide les vérifie',
              detail: 'Un administrateur ouvre chaque pièce, la valide ou la refuse avec un motif. Vous êtes prévenu à chaque décision.',
            ),
            Divider(height: 22, color: DriverColors.line),
            _Step(
              number: 3,
              title: 'Enregistrez votre véhicule et publiez vos trajets',
              detail: 'Dès que les quatre pièces sont validées, votre agrément est actif.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          key: const ValueKey('devenir-chauffeur'),
          onPressed: () => start(context),
          icon: const Icon(Icons.drive_eta_rounded),
          label: const Text('Devenir chauffeur'),
        ),
      ),
    ],
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.detail});

  final int number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 14,
        backgroundColor: MboaColors.sun,
        child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w700, color: MboaColors.night)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(detail, style: const TextStyle(fontSize: 13, color: MboaColors.mutedText, height: 1.4)),
          ],
        ),
      ),
    ],
  );
}
