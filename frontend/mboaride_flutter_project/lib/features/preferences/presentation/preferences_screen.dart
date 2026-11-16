import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/preferences_repository.dart';
import '../domain/preferences.dart';

/// US02 · Renseigner mes exigences de confort et mon cercle de confiance.
///
/// Les cercles sont emboîtés : choisir « Public vérifié » accepte aussi les
/// partenaires et les collègues. Le serveur refuse toute autre combinaison.
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key, required this.repository});

  final PreferencesRepository repository;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late Future<Preferences> _loading;
  final TextEditingController _priceController = TextEditingController();
  Preferences? _preferences;
  bool _saving = false;
  String? _priceError;

  @override
  void initState() {
    super.initState();
    _loading = widget.repository.load().then((p) {
      _priceController.text = p.maxPriceFcfa.toString();
      return p;
    });
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _update(Preferences next) => setState(() {
    _preferences = next;
    _priceError = null;
  });

  Future<void> _save() async {
    final current = _preferences;
    if (current == null) return;
    final parsed = int.tryParse(_priceController.text.trim());
    if (parsed == null) {
      setState(() => _priceError = 'Entrez un montant en FCFA.');
      return;
    }
    final candidate = current.copyWith(maxPriceFcfa: parsed);
    final error = candidate.priceError;
    if (error != null) {
      setState(() => _priceError = error);
      return;
    }
    setState(() {
      _saving = true;
      _priceError = null;
    });
    try {
      final saved = await widget.repository.save(candidate);
      if (!mounted) return;
      setState(() {
        _preferences = saved;
        _saving = false;
      });
      _priceController.text = saved.maxPriceFcfa.toString();
      _tell('Vos exigences sont enregistrées.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _tell(error.message, isError: true);
    }
  }

  void _tell(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? MboaColors.red : MboaColors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes exigences')),
      body: FutureBuilder<Preferences>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: () => setState(() {
                _loading = widget.repository.load();
              }),
            );
          }
          final preferences = _preferences ??= snapshot.data!;
          return _form(preferences);
        },
      ),
    );
  }

  Widget _form(Preferences p) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
    children: [
      const _SectionTitle('Confort souhaité'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilterChip(
            label: const Text('Climatisation'),
            selected: p.airConditioning,
            onSelected: (v) => _update(p.copyWith(airConditioning: v)),
          ),
          FilterChip(
            label: const Text('Non-fumeur'),
            selected: p.nonSmoking,
            onSelected: (v) => _update(p.copyWith(nonSmoking: v)),
          ),
          FilterChip(
            label: const Text('Silence'),
            selected: p.quiet,
            onSelected: (v) => _update(p.copyWith(quiet: v)),
          ),
        ],
      ),
      const _Hint(
        'La climatisation est une exigence ferme : un véhicule qui ne la propose '
        'pas ne vous sera pas présenté.',
      ),
      const _SectionTitle('Prix maximal par trajet'),
      TextField(
        controller: _priceController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          suffixText: 'FCFA',
          errorText: _priceError,
          hintText: '500',
        ),
      ),
      const _SectionTitle('Cercle de confiance'),
      ...Circle.values.map(
        (circle) => _ChoiceRow(
          label: circle.label,
          description: circle.description,
          selected: p.circle == circle,
          onTap: () => _update(p.copyWith(circle: circle)),
        ),
      ),
      const _Hint(
        'Les cercles sont emboîtés : le public vérifié comprend aussi les '
        'partenaires et vos collègues. Tout conducteur du réseau public est '
        'agréé par MboaRide, pièce d\'identité, permis, casier et assurance.',
      ),
      const _SectionTitle('Mode de réservation'),
      ...BookingMode.values.map(
        (mode) => _ChoiceRow(
          label: mode.label,
          description: mode.description,
          selected: p.mode == mode,
          onTap: () => _update(p.copyWith(mode: mode)),
        ),
      ),
      const _SectionTitle('Je privilégie'),
      SegmentedButton<RidePriority>(
        segments: RidePriority.values
            .map(
              (priority) => ButtonSegment<RidePriority>(
                value: priority,
                label: Text(priority.label),
              ),
            )
            .toList(),
        selected: {p.priority},
        onSelectionChanged: (s) => _update(p.copyWith(priority: s.first)),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Enregistrer'),
      ),
    ],
  );
}

/// Ligne à choix unique, écrite à la main pour rester compatible avec les
/// versions de Flutter utilisées par l'équipe.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? MboaColors.green : MboaColors.border,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: MboaColors.night,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
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
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: MboaColors.night,
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: MboaColors.mutedText),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 40, color: MboaColors.mutedText),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    ),
  );
}
