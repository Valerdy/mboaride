import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';

/// Agrément conducteur (wireframe 2) : identité, permis, casier judiciaire, assurance.
class ApprovalScreen extends StatefulWidget {
  const ApprovalScreen({super.key, required this.repository});

  final DriverRepository repository;

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  late Future<Approval> _loading = widget.repository.approval();
  Approval? _approval;
  String? _uploading;

  void _reload() => setState(() {
    _approval = null;
    _loading = widget.repository.approval();
  });

  Future<void> _upload(DriverDocument document) async {
    setState(() => _uploading = document.kind);
    try {
      final approval = await widget.repository.uploadDocument(document.kind);
      if (!mounted) return;
      setState(() {
        _approval = approval;
        _uploading = null;
      });
      showDriverMessage(context, '${document.label} déposée : MboaRide la vérifie.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _uploading = null);
      showDriverMessage(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agrément conducteur')),
    body: AsyncView<Approval>(
      future: _loading,
      onRetry: _reload,
      builder: (context, loaded) {
        final approval = _approval ??= loaded;
        final total = approval.documents.length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            const Text(
              'Déposez vos 4 pièces. MboaRide les vérifie avant votre premier trajet : '
              'aucun trajet ne peut être publié avant l\'agrément.',
              style: TextStyle(fontSize: 15, color: MboaColors.mutedText, height: 1.45),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pièces validées', style: TextStyle(fontWeight: FontWeight.w500)),
                Text('${approval.validatedCount} sur $total', style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : approval.validatedCount / total,
                minHeight: 10,
                backgroundColor: DriverColors.line,
                color: MboaColors.green,
                semanticsLabel: '${approval.validatedCount} pièces validées sur $total',
              ),
            ),
            const SizedBox(height: 16),
            DriverCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < approval.documents.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: DriverColors.line),
                    _documentRow(approval.documents[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const InfoBanner(
              'Chaque pièce est redemandée à sa date d\'expiration. Un signalement grave suspend '
              'l\'agrément le temps de l\'examen. Les documents sont stockés à part, avec un accès restreint.',
            ),
            if (approval.approved) ...[
              const SizedBox(height: 14),
              const InfoBanner(
                'Votre agrément est validé : vous pouvez publier vos trajets.',
                icon: Icons.verified_user_outlined,
              ),
            ],
          ],
        );
      },
    ),
  );

  Widget _documentRow(DriverDocument document) {
    final (label, tone) = switch (document.status) {
      DocumentStatus.validated => ('Validée', PillTone.success),
      DocumentStatus.pending => ('En vérification', PillTone.warning),
      DocumentStatus.missing => ('À déposer', PillTone.danger),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(document.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    if (document.detail != null) ...[
                      const SizedBox(height: 3),
                      Text(document.detail!, style: const TextStyle(fontSize: 13, color: MboaColors.mutedText)),
                    ],
                  ],
                ),
              ),
              StatusPill(label, tone: tone),
            ],
          ),
          if (document.status == DocumentStatus.missing) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _uploading == null ? () => _upload(document) : null,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: const BorderSide(color: MboaColors.green, width: 1.5),
                ),
                icon: _uploading == document.kind
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_outlined),
                label: Text('Déposer : ${document.label.toLowerCase()}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
