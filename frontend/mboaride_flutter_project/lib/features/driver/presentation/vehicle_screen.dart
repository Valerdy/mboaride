import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/mboa_theme.dart';
import '../data/driver_repository.dart';
import '../domain/driver.dart';
import 'driver_widgets.dart';

/// Mon véhicule (wireframe 3) : places offertes, consommation (base du prix), confort offert.
class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key, required this.repository});

  final DriverRepository repository;

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  late Future<Vehicle> _loading = widget.repository.vehicle().then(_fill);
  final _model = TextEditingController();
  final _plate = TextEditingController();
  final _consumption = TextEditingController();
  Vehicle? _vehicle;
  bool _saving = false;
  String? _error;

  Vehicle _fill(Vehicle v) {
    _model.text = v.model;
    _plate.text = v.plate;
    final c = v.consumptionL100;
    _consumption.text = c == c.roundToDouble() ? c.toStringAsFixed(0) : c.toString().replaceAll('.', ',');
    return v;
  }

  @override
  void dispose() {
    _model.dispose();
    _plate.dispose();
    _consumption.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current = _vehicle!;
    final consumption = double.tryParse(_consumption.text.trim().replaceAll(',', '.'));
    if (consumption == null) {
      setState(() => _error = 'Indiquez la consommation, par exemple 8.');
      return;
    }
    final candidate = current.copyWith(
      model: _model.text.trim(),
      plate: _plate.text.trim(),
      consumptionL100: consumption,
    );
    final error = candidate.error;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.saveVehicle(candidate);
      if (!mounted) return;
      setState(() {
        _vehicle = saved;
        _saving = false;
      });
      showDriverMessage(context, 'Véhicule enregistré.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDriverMessage(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mon véhicule')),
    body: AsyncView<Vehicle>(
      future: _loading,
      onRetry: () => setState(() => _loading = widget.repository.vehicle().then(_fill)),
      builder: (context, loaded) {
        final v = _vehicle ??= loaded;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            TextField(
              controller: _model,
              decoration: const InputDecoration(labelText: 'Marque et modèle'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Immatriculation'),
            ),
            const SizedBox(height: 14),
            DriverCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Places offertes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        Text('Hors conducteur', style: TextStyle(fontSize: 13, color: MboaColors.mutedText)),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Retirer une place',
                    onPressed: v.seats > Vehicle.minSeats
                        ? () => setState(() => _vehicle = v.copyWith(seats: v.seats - 1))
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${v.seats}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Ajouter une place',
                    onPressed: v.seats < Vehicle.maxSeats
                        ? () => setState(() => _vehicle = v.copyWith(seats: v.seats + 1))
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _consumption,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Consommation (L/100 km)',
                helperText: 'Valeur par défaut : 8. Elle sert à calculer la part de carburant de chaque passager.',
                helperMaxLines: 2,
              ),
            ),
            const SectionTitle('Confort offert'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final comfort in Comfort.values)
                  FilterChip(
                    label: Text(comfort.label),
                    selected: v.comfort.contains(comfort),
                    onSelected: (selected) => setState(() {
                      final next = {...v.comfort};
                      selected ? next.add(comfort) : next.remove(comfort);
                      _vehicle = v.copyWith(comfort: next);
                    }),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: MboaColors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Enregistrement…' : 'Enregistrer le véhicule'),
            ),
          ],
        );
      },
    ),
  );
}
