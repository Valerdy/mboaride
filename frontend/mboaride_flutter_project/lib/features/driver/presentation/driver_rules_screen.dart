import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';

/// Cercles et règles (wireframe 4) : qui peut monter, élèves, prix minimal, réponse aux demandes.
class DriverRulesScreen extends StatefulWidget {
  const DriverRulesScreen({super.key, required this.repository});

  final DriverRepository repository;

  @override
  State<DriverRulesScreen> createState() => _DriverRulesScreenState();
}

class _DriverRulesScreenState extends State<DriverRulesScreen> {
  late Future<DriverRules> _loading = widget.repository.rules().then(_fill);
  final _minPrice = TextEditingController();
  DriverRules? _rules;
  bool _saving = false;
  String? _error;

  DriverRules _fill(DriverRules r) {
    _minPrice.text = r.minPriceFcfa.toString();
    return r;
  }

  @override
  void dispose() {
    _minPrice.dispose();
    super.dispose();
  }

  void _set(DriverRules next) => setState(() {
    _rules = next;
    _error = null;
  });

  Future<void> _save() async {
    final minPrice = int.tryParse(_minPrice.text.trim());
    if (minPrice == null) {
      setState(() => _error = 'Entrez un montant en FCFA (0 si aucun minimum).');
      return;
    }
    final candidate = _rules!.copyWith(minPriceFcfa: minPrice);
    final error = candidate.error;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.repository.saveRules(candidate);
      if (!mounted) return;
      setState(() {
        _rules = saved;
        _saving = false;
      });
      showDriverMessage(context, 'Vos règles sont enregistrées.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDriverMessage(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cercles et règles')),
    body: AsyncView<DriverRules>(
      future: _loading,
      onRetry: () => setState(() => _loading = widget.repository.rules().then(_fill)),
      builder: (context, loaded) {
        final r = _rules ??= loaded;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const SectionTitle('Qui peut monter dans ma voiture ?'),
            DriverCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _switch(
                    'Mes collègues',
                    'Membres de mon entreprise',
                    r.colleagues,
                    (v) => _set(r.copyWith(colleagues: v)),
                  ),
                  const Divider(height: 1, color: DriverColors.line),
                  _switch(
                    'Entreprises partenaires',
                    'Salariés des entreprises liées à la mienne',
                    r.partners,
                    (v) => _set(r.copyWith(partners: v)),
                  ),
                  const Divider(height: 1, color: DriverColors.line),
                  _switch(
                    'Réseau public vérifié',
                    'Passagers vérifiés hors entreprise ; ils paient 10 % de commission à MboaRide',
                    r.publicNetwork,
                    (v) => _set(r.copyWith(publicNetwork: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            DriverCard(
              padding: EdgeInsets.zero,
              child: _switch(
                'Accepter des élèves',
                '12 ans et plus, avec autorisation parentale ; le parent suit le trajet',
                r.acceptsStudents,
                (v) => _set(r.copyWith(acceptsStudents: v)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _minPrice,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Prix minimal par passager (FCFA)',
                helperText: 'Facultatif. En dessous de ce prix, votre agent ne propose pas de place.',
                helperMaxLines: 2,
              ),
            ),
            const SectionTitle('Réponse aux demandes'),
            _modeOption(
              title: 'Automatique',
              subtitle: 'Mon agent propose une place à chaque passager compatible avec mes règles.',
              selected: r.automatic,
              onTap: () => _set(r.copyWith(automatic: true)),
            ),
            const SizedBox(height: 8),
            _modeOption(
              title: 'Je valide chaque passager',
              subtitle: 'Version cible : pas encore prévue par le moteur côté conducteur.',
              selected: !r.automatic,
              onTap: null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: MboaColors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Enregistrement…' : 'Enregistrer mes règles'),
            ),
          ],
        );
      },
    ),
  );

  Widget _switch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeTrackColor: MboaColors.green,
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, color: MboaColors.mutedText)),
      );

  Widget _modeOption({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback? onTap,
  }) => Material(
    color: selected ? DriverColors.softGreen : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? MboaColors.green : MboaColors.border, width: selected ? 2 : 1.5),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: onTap == null && !selected ? MboaColors.border : MboaColors.green,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: MboaColors.mutedText, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
